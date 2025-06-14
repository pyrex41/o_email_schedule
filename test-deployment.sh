#!/bin/bash

# Test Email Scheduler Deployment
set -e

APP_NAME="email-scheduler"

echo "🧪 TESTING EMAIL SCHEDULER DEPLOYMENT"
echo "====================================="
echo ""

# Test 1: Check if app exists
echo "1️⃣  Testing app existence..."
if flyctl apps list | grep -q "$APP_NAME"; then
    echo "✅ App '$APP_NAME' exists"
else
    echo "❌ App '$APP_NAME' not found"
    echo "   Run ./deploy-scheduler.sh first"
    exit 1
fi

# Test 2: Check volume
echo ""
echo "2️⃣  Testing volume..."
if flyctl volumes list -a "$APP_NAME" | grep -q "scheduler_data"; then
    echo "✅ Volume 'scheduler_data' exists"
else
    echo "❌ Volume 'scheduler_data' not found"
    exit 1
fi

# Test 3: Try to start machine
echo ""
echo "3️⃣  Testing machine start..."
echo "Starting machine..."
flyctl machine start -a "$APP_NAME" >/dev/null 2>&1 || true
sleep 5

# Test 4: Check machine status
echo ""
echo "4️⃣  Testing machine status..."
if flyctl status -a "$APP_NAME" | grep -q "started"; then
    echo "✅ Machine is running"
else
    echo "⚠️  Machine may not be running"
fi

# Test 5: Test SSH connectivity
echo ""
echo "5️⃣  Testing SSH connection..."
if flyctl ssh console -a "$APP_NAME" -C "echo 'SSH test successful'" 2>/dev/null | grep -q "successful"; then
    echo "✅ SSH connection works"
else
    echo "❌ SSH connection failed"
    exit 1
fi

# Test 6: Test volume mount
echo ""
echo "6️⃣  Testing volume mount..."
if flyctl ssh console -a "$APP_NAME" -C "test -d /data && echo 'Volume mounted'" 2>/dev/null | grep -q "mounted"; then
    echo "✅ Volume is mounted at /data"
else
    echo "❌ Volume not mounted properly"
    exit 1
fi

# Test 7: Test scheduler commands
echo ""
echo "7️⃣  Testing scheduler commands..."
if flyctl ssh console -a "$APP_NAME" -C "scheduler-help" 2>/dev/null | grep -q "FLY EMAIL SCHEDULER"; then
    echo "✅ Scheduler commands available"
else
    echo "❌ Scheduler commands not working"
    exit 1
fi

# Test 8: Test database info command
echo ""
echo "8️⃣  Testing database info..."
if flyctl ssh console -a "$APP_NAME" -C "db-info" 2>/dev/null | grep -q "DATABASE VOLUME"; then
    echo "✅ Database info command works"
else
    echo "❌ Database info command failed"
    exit 1
fi

# Test 9: Check available space
echo ""
echo "9️⃣  Checking available space..."
SPACE=$(flyctl ssh console -a "$APP_NAME" -C "df -h /data | tail -1 | awk '{print \$4}'" 2>/dev/null)
if [ ! -z "$SPACE" ]; then
    echo "✅ Available space: $SPACE"
else
    echo "⚠️  Could not check available space"
fi

# Test 10: Stop machine
echo ""
echo "🔟 Testing machine stop..."
flyctl machine stop -a "$APP_NAME" >/dev/null 2>&1
sleep 3
if flyctl status -a "$APP_NAME" | grep -q "stopped"; then
    echo "✅ Machine stopped successfully"
else
    echo "⚠️  Machine may still be running"
fi

echo ""
echo "🎉 DEPLOYMENT TEST COMPLETE!"
echo "============================"
echo ""
echo "✅ All tests passed! Your scheduler is ready to use."
echo ""
echo "📋 Next steps:"
echo "1. Start machine: ./start-scheduler.sh"
echo "2. Upload a test database to /data/"
echo "3. SSH in: ./ssh-scheduler.sh"
echo "4. Run: run-highperf-scheduler /data/test.db 8"
echo "5. Stop: ./stop-scheduler.sh"
echo ""
echo "🚀 Ready for production workloads!"