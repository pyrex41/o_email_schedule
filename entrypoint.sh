#!/bin/bash
set -e

# Enable strict error handling
set -euo pipefail

echo "🚀 Starting Email Scheduler with GCS Sync..."

# Check for required environment variables
if [ -z "${GCS_KEYFILE_JSON:-}" ]; then
    echo "❌ ERROR: GCS_KEYFILE_JSON environment variable is not set"
    echo "Please set this secret with: flyctl secrets set GCS_KEYFILE_JSON='<keyfile-content>'"
    exit 1
fi

if [ -z "${GCS_BUCKET_NAME:-}" ]; then
    echo "❌ ERROR: GCS_BUCKET_NAME environment variable is not set"
    echo "Please set this in fly.toml or as a secret"
    exit 1
fi

# Write GCS keyfile to temporary location
echo "🔐 Setting up GCS authentication..."
echo "$GCS_KEYFILE_JSON" > /tmp/gcs-key.json
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcs-key.json

# Mount GCS bucket using gcsfuse
echo "📁 Mounting GCS bucket: $GCS_BUCKET_NAME..."
gcsfuse --key-file /tmp/gcs-key.json "$GCS_BUCKET_NAME" /gcs

# Verify mount was successful
if ! mountpoint -q /gcs; then
    echo "❌ ERROR: Failed to mount GCS bucket"
    exit 1
fi

echo "✅ GCS bucket mounted successfully"

# Define paths
REMOTE_DB_PATH="/gcs/org-data/99.db"
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
    echo "📥 Syncing database from GCS to local working copy..."
    
    # Use sqlite3_rsync to sync from remote to local
    if sqlite3_rsync "$REMOTE_DB_PATH" "$LOCAL_DB_PATH"; then
        echo "✅ Database synced from GCS successfully"
    else
        echo "❌ ERROR: Failed to sync database from GCS"
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

# Sync the modified database back to GCS
echo "📤 Syncing modified database back to GCS..."

# Ensure remote directory exists
mkdir -p "$(dirname "$REMOTE_DB_PATH")"

if sqlite3_rsync "$LOCAL_DB_PATH" "$REMOTE_DB_PATH"; then
    echo "✅ Database synced back to GCS successfully"
else
    echo "❌ ERROR: Failed to sync database back to GCS"
    exit 1
fi

# Clean up
echo "🧹 Cleaning up..."
rm -f /tmp/gcs-key.json

# Unmount GCS (optional - container will terminate anyway)
if mountpoint -q /gcs; then
    fusermount -u /gcs || echo "⚠️  Could not unmount GCS (non-critical)"
fi

echo "🎉 Email Scheduler completed successfully!"
echo "Local database: $LOCAL_DB_PATH"
echo "Remote database: $REMOTE_DB_PATH"
echo "Run ID: $RUN_ID"