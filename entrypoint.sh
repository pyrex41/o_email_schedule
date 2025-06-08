#!/bin/bash
set -e

# Enable strict error handling
set -euo pipefail

echo "🚀 Starting Email Scheduler with Tigris Sync..."

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

# Clean up and unmount Tigris (optional - container will terminate anyway)
echo "🧹 Cleaning up..."
if mountpoint -q /tigris; then
    fusermount -u /tigris || echo "⚠️  Could not unmount Tigris (non-critical)"
fi

echo "🎉 Email Scheduler completed successfully!"
echo "Local database: $LOCAL_DB_PATH"
echo "Remote database: $REMOTE_DB_PATH"
echo "Run ID: $RUN_ID"