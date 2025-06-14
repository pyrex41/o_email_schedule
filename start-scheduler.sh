#!/bin/bash

# Start Email Scheduler Machine
set -e

APP_NAME="email-scheduler"

echo "🚀 Starting email scheduler machine..."
echo "======================================"

flyctl machine start -a "$APP_NAME"

echo ""
echo "✅ Machine started!"
echo ""
echo "📋 Next steps:"
echo "  SSH in:    ./ssh-scheduler.sh"
echo "  Check DB:  flyctl ssh console -a $APP_NAME -C 'db-info'"
echo "  Run job:   flyctl ssh console -a $APP_NAME -C 'run-highperf-scheduler /data/org.db 8'"
echo "  Stop:      ./stop-scheduler.sh"