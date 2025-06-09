#!/bin/bash

# Test script for distributed locking mechanism
# This demonstrates how multiple instances handle lock contention

set -e

echo "🧪 Testing Distributed Locking Mechanism"
echo "========================================"

# Check for required environment variables
if [ -z "${BUCKET_NAME:-}" ]; then
    echo "❌ ERROR: BUCKET_NAME environment variable is not set"
    echo "Please set: export BUCKET_NAME='your-tigris-bucket'"
    exit 1
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "❌ ERROR: AWS credentials not set"
    echo "Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    exit 1
fi

# Set Tigris endpoint
export AWS_ENDPOINT_URL_S3="${AWS_ENDPOINT_URL_S3:-https://fly.storage.tigris.dev}"
export AWS_REGION="${AWS_REGION:-auto}"

# Test configuration
LOCK_KEY="test-lock/scheduler.lock"
LOCK_TIMEOUT=60  # 1 minute for testing
INSTANCE_ID="test_instance_$$_$(date +%s)"

echo "Configuration:"
echo "  Bucket: $BUCKET_NAME"
echo "  Lock Key: $LOCK_KEY"
echo "  Instance ID: $INSTANCE_ID"
echo "  Endpoint: $AWS_ENDPOINT_URL_S3"
echo ""

# Function to acquire lock
acquire_lock() {
    local lock_content="{\"instance_id\":\"$INSTANCE_ID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"timeout\":$LOCK_TIMEOUT,\"test\":true}"
    
    echo "🔒 Attempting to acquire lock..."
    if aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --body <(echo "$lock_content") \
        --if-none-match "*" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1; then
        echo "✅ Lock acquired successfully!"
        return 0
    else
        echo "❌ Lock acquisition failed (another instance has the lock)"
        return 1
    fi
}

# Function to check lock status
check_lock_status() {
    echo "🔍 Checking current lock status..."
    if aws s3api get-object \
        --bucket "$BUCKET_NAME" \
        --key "$LOCK_KEY" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" \
        /tmp/current_lock.json 2>/dev/null; then
        
        echo "📋 Current lock holder:"
        echo "   $(cat /tmp/current_lock.json)"
        rm -f /tmp/current_lock.json
        return 0
    else
        echo "🟢 No active lock found"
        return 1
    fi
}

# Function to release lock
release_lock() {
    echo "🔓 Releasing lock..."
    if aws s3 rm "s3://$BUCKET_NAME/$LOCK_KEY" \
        --endpoint-url "$AWS_ENDPOINT_URL_S3" >/dev/null 2>&1; then
        echo "✅ Lock released successfully"
    else
        echo "⚠️  Lock may have already been released"
    fi
}

# Function to simulate work
simulate_work() {
    echo "🏃 Simulating scheduler work..."
    for i in {1..5}; do
        echo "   Processing step $i/5..."
        sleep 2
    done
    echo "✅ Work completed"
}

# Main test flow
main() {
    echo "🏁 Starting lock test..."
    echo ""
    
    # Check initial lock status
    check_lock_status
    echo ""
    
    # Try to acquire lock
    if acquire_lock; then
        echo ""
        echo "🎉 Lock acquired! Proceeding with work..."
        echo ""
        
        # Simulate the scheduler work
        simulate_work
        echo ""
        
        # Release lock
        release_lock
        echo ""
        echo "✅ Test completed successfully"
    else
        echo ""
        echo "🔄 Testing lock contention scenario..."
        check_lock_status
        echo ""
        echo "💡 To test lock expiration, wait $(( LOCK_TIMEOUT + 5 )) seconds and try again"
        echo "💡 Or manually remove the lock with:"
        echo "   aws s3 rm s3://$BUCKET_NAME/$LOCK_KEY --endpoint-url $AWS_ENDPOINT_URL_S3"
    fi
}

# Cleanup on exit
cleanup() {
    echo ""
    echo "🧹 Cleaning up test artifacts..."
    release_lock
}
trap cleanup EXIT

# Run the test
main

echo ""
echo "🎯 Test Summary:"
echo "   This script demonstrates the distributed locking mechanism"
echo "   that prevents multiple scheduler instances from running simultaneously."
echo ""
echo "📖 To test multiple instances:"
echo "   1. Run this script in one terminal"
echo "   2. While it's running, run it again in another terminal"
echo "   3. The second instance should wait or fail gracefully"