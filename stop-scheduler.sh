#!/bin/bash

# Stop Email Scheduler Machine
set -e

APP_NAME="email-scheduler"

echo "🛑 Stopping email scheduler machine..."
echo "======================================"

flyctl machine stop -a "$APP_NAME"

echo ""
echo "✅ Machine stopped!"
echo ""
echo "💡 Machine is preserved and can be restarted with: ./start-scheduler.sh"
echo "💾 Persistent volume data is safe"