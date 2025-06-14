#!/bin/bash

# SSH into Email Scheduler Machine
set -e

APP_NAME="email-scheduler"

echo "🔐 Connecting to email scheduler machine..."
echo "==========================================="
echo ""
echo "💡 Available commands once connected:"
echo "  scheduler-help           - Show all available commands"
echo "  db-info                  - Check database volume status"
echo "  run-reliable-scheduler   - Run conservative scheduler"  
echo "  run-highperf-scheduler   - Run high-performance scheduler"
echo ""

flyctl ssh console -a "$APP_NAME"