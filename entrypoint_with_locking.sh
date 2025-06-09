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
LOCK_KEY="org-data/99.db.lock"
LOCK_TIMEOUT=3600  # 1 hour timeout

echo "🔒 Attempting to acquire processing lock..."
echo "Instance ID: $INSTANCE_ID"

# Function to acquire lock using conditional PUT
acquire_lock() {
    local lock_content="{\"instance_id\":\"$INSTANCE_ID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"timeout\":$LOCK_TIMEOUT}"
    
    # Try to create lock file with conditional write (if-none-match)
    if aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --body <(echo "$lock_content") \
        --if-none-match "*" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1; then
        echo "✅ Lock acquired successfully"
        return 0
    else
        return 1
    fi
}

# Function to release lock
release_lock() {
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
        
        local lock_timestamp=$(jq -r '.timestamp' /tmp/lock_info.json 2>/dev/null || echo "")
        if [ -n "$lock_timestamp" ]; then
            local lock_epoch=$(date -d "$lock_timestamp" +%s 2>/dev/null || echo "0")
            local now_epoch=$(date +%s)
            local age=$((now_epoch - lock_epoch))
            
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
    fi
    return 0
}

# Try to acquire lock with retry logic
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if acquire_lock; then
        break
    else
        echo "🔒 Lock acquisition failed, checking if lock is expired..."
        if check_lock_expiry; then
            continue  # Try again after removing expired lock
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            WAIT_TIME=$((RETRY_COUNT * 30))  # Exponential backoff
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

# Define paths
REMOTE_DB_PATH="/tigris/org-data/99.db"
LOCAL_DB_PATH="/app/data/working_copy.db"
ORG_ID="${ORG_ID:-99}"

# Create local data directory if it doesn't exist
mkdir -p /app/data

# Check if remote database exists
if [ ! -f "$REMOTE_DB_PATH" ]; then
    echo "⚠️  Remote database not found at $REMOTE_DB_PATH"
    echo "This might be the first run - creating empty local database"
    touch "$LOCAL_DB_PATH"
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

if sqlite3_rsync "$LOCAL_DB_PATH" "$REMOTE_DB_PATH"; then
    echo "✅ Database synced back to Tigris successfully"
else
    echo "❌ ERROR: Failed to sync database back to Tigris"
    exit 1
fi

echo "🎉 Email Scheduler completed successfully!"
echo "Local database: $LOCAL_DB_PATH"
echo "Remote database: $REMOTE_DB_PATH"
echo "Run ID: $RUN_ID"
echo "Instance ID: $INSTANCE_ID"