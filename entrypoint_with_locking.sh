#!/bin/bash
set -e

# Enable strict error handling
set -euo pipefail

echo "🚀 Starting Email Scheduler with Tigris Sync and Locking..."

# Check for required environment variables
if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "❌ ERROR: AWS_ACCESS_KEY_ID environment variable is not set"
    echo "Please set this secret with: flyctl secrets set AWS_ACCESS_KEY_ID='<your-tigris-access-key>'"
    exit 1
fi

if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "❌ ERROR: AWS_SECRET_ACCESS_KEY environment variable is not set"
    echo "Please set this secret with: flyctl secrets set AWS_SECRET_ACCESS_KEY='<your-tigris-secret-key>'"
    exit 1
fi

if [ -z "${BUCKET_NAME:-}" ]; then
    echo "❌ ERROR: BUCKET_NAME environment variable is not set"
    echo "Please set this in fly.toml or as a secret"
    exit 1
fi

# Set Tigris endpoint (Fly.io optimized endpoint)
export AWS_ENDPOINT_URL_S3="${AWS_ENDPOINT_URL_S3:-https://fly.storage.tigris.dev}"
export AWS_REGION="${AWS_REGION:-auto}"

echo "🔐 Setting up Tigris authentication..."
echo "Using endpoint: $AWS_ENDPOINT_URL_S3"
echo "Bucket: $BUCKET_NAME"

# Generate unique instance ID
INSTANCE_ID="instance_$(date +%Y%m%d_%H%M%S)_$$_$(hostname)"
# Tenant / organization ID (defaults to 99 if not provided)
ORG_ID="${ORG_ID:-99}"

# Use tenant-specific paths for lock files to avoid cross-tenant contention
LOCK_KEY="org-data/${ORG_ID}.db.lock"
LOCK_TIMEOUT=3600  # 1 hour timeout
# Track whether this instance successfully acquired the lock
LOCK_ACQUIRED=0

echo "🔒 Attempting to acquire processing lock..."
echo "Instance ID: $INSTANCE_ID"

# Function to properly escape JSON strings
json_escape() {
    printf '%s' "$1" | jq -Rs .
}

# Function to acquire lock using conditional PUT
acquire_lock() {
    # Create a temporary file for the lock content
    local temp_file=$(mktemp)
    local escaped_instance_id=$(json_escape "$INSTANCE_ID")
    local lock_content="{\"instance_id\":$escaped_instance_id,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"timeout\":$LOCK_TIMEOUT}"
    
    # Write lock content to temporary file
    echo "$lock_content" > "$temp_file"
    
    # Try to create lock file with conditional write (if-none-match)
    if aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --body "$temp_file" \
        --if-none-match "*" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1; then
        echo "✅ Lock acquired successfully"
        LOCK_ACQUIRED=1  # remember that we hold the lock
        rm -f "$temp_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to release lock
release_lock() {
    # Only attempt to delete the lock object if *this* instance still owns it
    if [ "$LOCK_ACQUIRED" -ne 1 ]; then
        echo "🔓 No lock held by this instance – skipping release"
        return
    fi

    # Verify that the lock file is still owned by this instance (avoid race)
    if aws s3api get-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" \
        /tmp/current_lock_release.json 2>/dev/null; then
        current_instance_id=$(jq -r '.instance_id' /tmp/current_lock_release.json 2>/dev/null || echo "")
        rm -f /tmp/current_lock_release.json
        if [ "$current_instance_id" != "$INSTANCE_ID" ]; then
            echo "⚠️  Lock is now owned by another instance ($current_instance_id) – not deleting"
            return
        fi
    else
        # Lock file already gone – nothing to clean up
        echo "ℹ️  Lock file already absent; nothing to release"
        return
    fi

    echo "🔓 Releasing processing lock..."
    aws s3 rm "s3://$BUCKET_NAME/$LOCK_KEY" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1 || true
}

# Function to check if existing lock is expired
check_lock_expiry() {
    local lock_info
    if lock_info=$(aws s3api get-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" \
        /tmp/lock_info.json 2>/dev/null); then
        
        local lock_timestamp=$(jq -r '.timestamp' /tmp/lock_info.json 2>/dev/null)
        
        # Check if timestamp parsing failed or is empty
        if [ -z "$lock_timestamp" ] || [ "$lock_timestamp" = "null" ]; then
            echo "⚠️ Invalid lock file format (no timestamp found)"
            return 1  # Don't remove the lock, consider it active
        fi
        
        # Parse ISO8601 timestamp using compatible method for Alpine/BusyBox
        # Format expected: 2023-04-15T12:34:56Z
        if [[ ! "$lock_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
            echo "⚠️ Invalid timestamp format in lock file: $lock_timestamp"
            return 1  # Keep the lock, consider it active
        fi
        
        # Extract date parts
        local year=${lock_timestamp:0:4}
        local month=${lock_timestamp:5:2}
        local day=${lock_timestamp:8:2}
        local hour=${lock_timestamp:11:2}
        local minute=${lock_timestamp:14:2}
        local second=${lock_timestamp:17:2}
        
        # Convert to seconds since epoch using a more reliable approach
        local lock_epoch=""

        # 1) Try GNU coreutils date parsing (supports "-d <iso8601>")
        lock_epoch=$(date -u -d "$lock_timestamp" +%s 2>/dev/null || true)

        # 2) If that failed, fall back to BusyBox date which requires an explicit format via -D
        if [ -z "$lock_epoch" ]; then
            local temp_date="${year}-${month}-${day} ${hour}:${minute}:${second}"
            lock_epoch=$(date -u -D "%Y-%m-%d %H:%M:%S" -d "$temp_date" +%s 2>/dev/null || true)
        fi

        # If date parsing still failed, consider the lock active
        if [ -z "$lock_epoch" ]; then
            echo "⚠️ Failed to parse lock timestamp"
            return 1  # Keep the lock, consider it active
        fi
        
        local now_epoch=$(date +%s)
        local age=$((now_epoch - lock_epoch))
        
        # Ensure we got a reasonable value
        if [ $age -lt 0 ] || [ $age -gt 31536000 ]; then  # > 1 year is unreasonable
            echo "⚠️ Calculated lock age is unreasonable: ${age}s"
            return 1  # Keep the lock, consider it active
        fi
        
        if [ $age -gt $LOCK_TIMEOUT ]; then
            echo "⏰ Existing lock expired (age: ${age}s), removing..."
            aws s3 rm "s3://$BUCKET_NAME/$LOCK_KEY" \
                --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1 || true
            return 0
        else
            echo "🔒 Active lock found (age: ${age}s), waiting..."
            return 1
        fi
    fi
    return 0
}

# Try to acquire lock with retry logic
MAX_RETRIES=10
RETRY_COUNT=0
BASE_WAIT=30  # Base wait time in seconds

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if acquire_lock; then
        break
    else
        echo "🔒 Lock acquisition failed, checking if lock is expired..."
        if check_lock_expiry; then
            continue  # Try again after removing expired lock
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            # Exponential backoff: 30s, 60s, 120s, 240s, etc.
            WAIT_TIME=$((BASE_WAIT * (1 << (RETRY_COUNT - 1))))
            echo "⏳ Waiting ${WAIT_TIME}s before retry (attempt $RETRY_COUNT/$MAX_RETRIES)..."
            sleep $WAIT_TIME
        fi
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ ERROR: Could not acquire processing lock after $MAX_RETRIES attempts"
    echo "Another instance may be running. Please check and manually remove lock if needed:"
    echo "aws s3 rm s3://$BUCKET_NAME/$LOCK_KEY --endpoint-url $AWS_ENDPOINT_URL_S3"
    exit 1
fi

# Set up cleanup trap
cleanup() {
    echo "🧹 Cleaning up..."
    release_lock
    if mountpoint -q /tigris 2>/dev/null; then
        fusermount -u /tigris || echo "⚠️  Could not unmount Tigris (non-critical)"
    fi
}
trap cleanup EXIT

# Mount Tigris bucket using TigrisFS
echo "📁 Mounting Tigris bucket: $BUCKET_NAME..."
tigrisfs "$BUCKET_NAME" /tigris \
    --file-mode=0666 \
    --dir-mode=0777 \
    --endpoint="$AWS_ENDPOINT_URL_S3" \
    --region="$AWS_REGION"

# Verify mount was successful
if ! mountpoint -q /tigris; then
    echo "❌ ERROR: Failed to mount Tigris bucket"
    exit 1
fi

echo "✅ Tigris bucket mounted successfully"

# Define paths (tenant-specific)
REMOTE_DB_PATH="/tigris/org-data/${ORG_ID}.db"
LOCAL_DB_PATH="/app/data/working_copy.db"

# Create local data directory if it doesn't exist
mkdir -p /app/data

# Ensure the local database file exists so that sqlite3_rsync has a valid destination
if [ ! -f "$LOCAL_DB_PATH" ]; then
    sqlite3 "$LOCAL_DB_PATH" "PRAGMA user_version;" >/dev/null 2>&1
fi

# Check if remote database exists
if [ ! -f "$REMOTE_DB_PATH" ]; then
    echo "⚠️  Remote database not found at $REMOTE_DB_PATH"
    echo "This might be the first run - initializing new local database"

    # Create an empty, but valid, SQLite database
    sqlite3 "$LOCAL_DB_PATH" "PRAGMA user_version;" >/dev/null 2>&1
else
    echo "📥 Syncing database from Tigris to local working copy..."
    
    # Use sqlite3_rsync to sync from remote to local
    if sqlite3_rsync "$REMOTE_DB_PATH" "$LOCAL_DB_PATH"; then
        echo "✅ Database synced from Tigris successfully"
    else
        echo "❌ ERROR: Failed to sync database from Tigris"
        exit 1
    fi
fi

# Verify local database exists
if [ ! -f "$LOCAL_DB_PATH" ]; then
    echo "❌ ERROR: Local working copy database not found"
    exit 1
fi

echo "🏃 Running OCaml Email Scheduler..."
echo "Database: $LOCAL_DB_PATH"

# Generate unique run ID
RUN_ID="run_$(date +%Y%m%d_%H%M%S)_$$"
echo "Run ID: $RUN_ID"

# Execute the OCaml scheduler
if /app/scheduler_cli "$LOCAL_DB_PATH"; then
    echo "✅ OCaml scheduler completed successfully"
else
    echo "❌ ERROR: OCaml scheduler failed"
    
    # Still try to sync back even if scheduler failed to preserve any partial changes
    echo "⚠️  Attempting to sync back partial changes..."
fi

# Sync the modified database back to Tigris
echo "📤 Syncing modified database back to Tigris..."

# Ensure remote directory exists
mkdir -p "$(dirname "$REMOTE_DB_PATH")"

if [ -f "$REMOTE_DB_PATH" ]; then
    # Remote DB exists – perform incremental sync
    if sqlite3_rsync "$LOCAL_DB_PATH" "$REMOTE_DB_PATH"; then
        echo "✅ Database synced back to Tigris successfully (rsync)"
    else
        echo "❌ ERROR: Failed to rsync database back to Tigris"
        exit 1
    fi
else
    # Remote DB does not exist yet – first-time upload
    if cp "$LOCAL_DB_PATH" "$REMOTE_DB_PATH"; then
        echo "✅ Initial database uploaded to Tigris successfully"
    else
        echo "❌ ERROR: Failed to upload initial database to Tigris"
        exit 1
    fi
fi

echo "🎉 Email Scheduler completed successfully!"
echo "Local database: $LOCAL_DB_PATH"
echo "Remote database: $REMOTE_DB_PATH"
echo "Run ID: $RUN_ID"
echo "Instance ID: $INSTANCE_ID"