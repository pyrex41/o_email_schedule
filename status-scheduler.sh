#!/bin/bash

# Check Email Scheduler Machine Status
set -e

APP_NAME="email-scheduler"

echo "📊 EMAIL SCHEDULER STATUS"
echo "========================="
echo ""

echo "🖥️  Machine Status:"
flyctl status -a "$APP_NAME"

echo ""
echo "💾 Volume Status:"
flyctl volumes list -a "$APP_NAME"

echo ""
echo "🔧 Management Commands:"
echo "  Start:   ./start-scheduler.sh"
echo "  Stop:    ./stop-scheduler.sh" 
echo "  SSH:     ./ssh-scheduler.sh"
echo "  Deploy:  ./deploy-scheduler.sh"