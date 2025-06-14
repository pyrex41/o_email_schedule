#!/bin/bash

# Email Scheduler Fly Machine Deployment Script
set -e

echo "🚀 EMAIL SCHEDULER FLY MACHINE DEPLOYMENT"
echo "=========================================="
echo ""

# Configuration
APP_NAME="email-scheduler"
REGION="iad"  # Change this to your preferred region
VOLUME_NAME="scheduler_data"
VOLUME_SIZE="10gb"
CONFIG_FILE="fly.scheduler.toml"

# Check if flyctl is installed
if ! command -v flyctl &> /dev/null; then
    echo "❌ flyctl not found. Please install Fly CLI first:"
    echo "   https://fly.io/docs/hands-on/install-flyctl/"
    exit 1
fi

# Check if logged in
if ! flyctl auth whoami &> /dev/null; then
    echo "❌ Not logged in to Fly. Please run: flyctl auth login"
    exit 1
fi

echo "✅ Fly CLI ready"
echo ""

# Step 1: Create the app if it doesn't exist
echo "📱 Checking/creating Fly app..."
if flyctl apps list | grep -q "$APP_NAME"; then
    echo "✅ App '$APP_NAME' already exists"
else
    echo "🆕 Creating new app '$APP_NAME'..."
    flyctl apps create "$APP_NAME" --org personal
    echo "✅ App created"
fi
echo ""

# Step 2: Create the volume if it doesn't exist  
echo "💾 Checking/creating persistent volume..."
if flyctl volumes list -a "$APP_NAME" | grep -q "$VOLUME_NAME"; then
    echo "✅ Volume '$VOLUME_NAME' already exists"
else
    echo "🆕 Creating $VOLUME_SIZE volume '$VOLUME_NAME' in $REGION..."
    flyctl volumes create "$VOLUME_NAME" --size "$VOLUME_SIZE" --region "$REGION" -a "$APP_NAME"
    echo "✅ Volume created"
fi
echo ""

# Step 3: Deploy the machine
echo "🏗️  Deploying scheduler machine..."
echo "   Configuration: $CONFIG_FILE"
echo "   Machine type: performance-8x (8 vCPU, 16GB RAM)"
echo "   Volume: $VOLUME_NAME ($VOLUME_SIZE)"
echo ""

flyctl deploy --config "$CONFIG_FILE" --app "$APP_NAME"

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================"
echo ""
echo "📋 Next Steps:"
echo "1. Check deployment status:"
echo "   flyctl status -a $APP_NAME"
echo ""
echo "2. SSH into the machine:"
echo "   flyctl ssh console -a $APP_NAME"
echo ""
echo "3. Check volume mount:"
echo "   flyctl ssh console -a $APP_NAME -C 'db-info'"
echo ""
echo "4. Upload a test database to /data/ and run scheduler:"
echo "   flyctl ssh console -a $APP_NAME -C 'run-highperf-scheduler /data/test.db 8'"
echo ""
echo "5. Stop the machine when done:"
echo "   flyctl machine stop -a $APP_NAME"
echo ""
echo "6. Start the machine when needed:"
echo "   flyctl machine start -a $APP_NAME"
echo ""
echo "🔧 Machine Management:"
echo "   Start:  ./start-scheduler.sh"
echo "   Stop:   ./stop-scheduler.sh"
echo "   SSH:    ./ssh-scheduler.sh"
echo "   Status: ./status-scheduler.sh"
echo ""
echo "📊 Performance:"
echo "   - 15k+ contacts/second processing"
echo "   - 2GB SQLite cache"
echo "   - 8-thread parallel processing"
echo "   - Enterprise-scale capability"