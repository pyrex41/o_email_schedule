#!/bin/bash

# Migration script from GCS to Tigris
# This script helps migrate your database from Google Cloud Storage to Tigris

set -e

echo "🔄 Email Scheduler Migration: GCS → Tigris"
echo "==========================================="

# Check for required tools
command -v flyctl >/dev/null 2>&1 || { echo "❌ flyctl is required but not installed. Please install it first."; exit 1; }
command -v gsutil >/dev/null 2>&1 || { echo "❌ gsutil is required but not installed. Please install Google Cloud SDK."; exit 1; }

# Get configuration from user
echo ""
echo "📝 Configuration"
echo "Please provide the following information:"

read -p "GCS bucket name (e.g., your-email-scheduler-bucket): " GCS_BUCKET
read -p "Tigris bucket name (e.g., your-tigris-bucket): " TIGRIS_BUCKET
read -p "Organization ID (default: 99): " ORG_ID
ORG_ID=${ORG_ID:-99}

echo ""
echo "🔍 Verifying configuration..."
echo "GCS Bucket: $GCS_BUCKET"
echo "Tigris Bucket: $TIGRIS_BUCKET"
echo "Organization ID: $ORG_ID"
echo ""

read -p "Does this look correct? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ Migration cancelled"
    exit 1
fi

# Create backup directory
BACKUP_DIR="./migration_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "📁 Created backup directory: $BACKUP_DIR"

# Download database from GCS
echo ""
echo "📥 Downloading database from GCS..."
GCS_DB_PATH="gs://$GCS_BUCKET/org-data/$ORG_ID.db"
LOCAL_DB_PATH="$BACKUP_DIR/database_backup.db"

if gsutil cp "$GCS_DB_PATH" "$LOCAL_DB_PATH"; then
    echo "✅ Database downloaded successfully"
    echo "   Local copy: $LOCAL_DB_PATH"
else
    echo "❌ Failed to download database from GCS"
    echo "   Attempted path: $GCS_DB_PATH"
    echo "   Please verify the bucket name and organization ID"
    exit 1
fi

# Verify database integrity
echo ""
echo "🔍 Verifying database integrity..."
if sqlite3 "$LOCAL_DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "✅ Database integrity check passed"
else
    echo "⚠️  Database integrity check failed - proceeding anyway"
fi

# Check if Tigris credentials are set
echo ""
echo "🔐 Checking Tigris credentials..."

# Try to get secrets from flyctl
if flyctl secrets list 2>/dev/null | grep -q "AWS_ACCESS_KEY_ID"; then
    echo "✅ Tigris credentials found in Fly.io secrets"
else
    echo "⚠️  Tigris credentials not found in Fly.io secrets"
    echo ""
    echo "Please set your Tigris credentials:"
    echo "flyctl secrets set AWS_ACCESS_KEY_ID='tid_xxxxx'"
    echo "flyctl secrets set AWS_SECRET_ACCESS_KEY='tsec_xxxxx'"
    echo ""
    read -p "Have you set the Tigris credentials? (y/N): " CREDS_SET
    if [[ ! $CREDS_SET =~ ^[Yy]$ ]]; then
        echo "❌ Please set Tigris credentials first"
        exit 1
    fi
fi

# Upload database to Tigris
echo ""
echo "📤 Uploading database to Tigris..."

# Set Tigris environment variables for AWS CLI compatibility
export AWS_ENDPOINT_URL_S3="https://fly.storage.tigris.dev"
export AWS_REGION="auto"

# Check if AWS CLI is available, if not, provide instructions
if command -v aws >/dev/null 2>&1; then
    TIGRIS_DB_PATH="s3://$TIGRIS_BUCKET/org-data/$ORG_ID.db"
    
    # Get credentials from flyctl if possible
    if AWS_ACCESS_KEY_ID=$(flyctl secrets list 2>/dev/null | grep AWS_ACCESS_KEY_ID | awk '{print $2}' 2>/dev/null); then
        export AWS_ACCESS_KEY_ID
    fi
    
    if AWS_SECRET_ACCESS_KEY=$(flyctl secrets list 2>/dev/null | grep AWS_SECRET_ACCESS_KEY | awk '{print $2}' 2>/dev/null); then
        export AWS_SECRET_ACCESS_KEY
    fi
    
    if aws s3 cp "$LOCAL_DB_PATH" "$TIGRIS_DB_PATH" --endpoint-url "$AWS_ENDPOINT_URL_S3"; then
        echo "✅ Database uploaded to Tigris successfully"
        echo "   Tigris path: $TIGRIS_DB_PATH"
    else
        echo "❌ Failed to upload database to Tigris"
        echo "   Please check your Tigris credentials and bucket name"
        exit 1
    fi
else
    echo "⚠️  AWS CLI not found. Please upload manually:"
    echo "   1. Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    echo "   2. Configure with your Tigris credentials"
    echo "   3. Upload with: aws s3 cp $LOCAL_DB_PATH s3://$TIGRIS_BUCKET/org-data/$ORG_ID.db --endpoint-url $AWS_ENDPOINT_URL_S3"
fi

# Update fly.toml
echo ""
echo "📝 Updating fly.toml configuration..."

if [ -f "fly.toml" ]; then
    # Backup original fly.toml
    cp fly.toml "$BACKUP_DIR/fly.toml.backup"
    echo "✅ Backed up original fly.toml"
    
    # Update bucket name in fly.toml
    if sed -i.tmp "s/GCS_BUCKET_NAME = .*/BUCKET_NAME = \"$TIGRIS_BUCKET\"/" fly.toml && rm fly.toml.tmp; then
        # Add Tigris-specific environment variables if not present
        if ! grep -q "AWS_ENDPOINT_URL_S3" fly.toml; then
            echo "  AWS_REGION = \"auto\"" >> fly.toml
            echo "  AWS_ENDPOINT_URL_S3 = \"https://fly.storage.tigris.dev\"" >> fly.toml
        fi
        echo "✅ Updated fly.toml configuration"
    else
        echo "⚠️  Could not automatically update fly.toml"
        echo "   Please manually update BUCKET_NAME in fly.toml"
    fi
else
    echo "⚠️  fly.toml not found in current directory"
fi

# Deployment instructions
echo ""
echo "🚀 Next Steps"
echo "============="
echo ""
echo "1. Review the updated configuration:"
echo "   - Check fly.toml for correct BUCKET_NAME"
echo "   - Verify Tigris credentials are set as secrets"
echo ""
echo "2. Deploy the updated application:"
echo "   flyctl deploy"
echo ""
echo "3. Test the deployment:"
echo "   flyctl logs"
echo ""
echo "4. Verify successful operation:"
echo "   Look for: '✅ Database synced from Tigris successfully'"
echo ""
echo "📁 Backup Location: $BACKUP_DIR"
echo "   - Original database: $LOCAL_DB_PATH"
echo "   - Original fly.toml: $BACKUP_DIR/fly.toml.backup"
echo ""
echo "🎉 Migration preparation complete!"
echo ""
echo "ℹ️  For detailed deployment instructions, see: TIGRIS_DEPLOYMENT.md"