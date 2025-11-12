#!/bin/bash
# test-state-locking.sh
# This script tests if state locking is working properly

set -e

echo "=========================================="
echo "Testing Terraform State Locking"
echo "=========================================="

cd cloud-projects/dev

echo ""
echo "Step 1: Running terraform plan in background (will hold lock)..."
terraform plan -lock-timeout=30s &
PLAN_PID=$!

echo "PID of first plan: $PLAN_PID"
sleep 5

echo ""
echo "Step 2: Attempting second terraform plan (should fail due to lock)..."
echo "This should error with 'Error acquiring the state lock'"

if terraform plan -lock-timeout=5s 2>&1 | grep -q "Error acquiring the state lock"; then
    echo ""
    echo "✓ SUCCESS! State locking is working correctly."
    echo "  Second operation was blocked by the first operation's lock."
else
    echo ""
    echo "✗ FAILURE! State locking is NOT working."
    echo "  Second operation should have been blocked but wasn't."
    kill $PLAN_PID 2>/dev/null || true
    exit 1
fi

# Clean up
echo ""
echo "Step 3: Cleaning up background process..."
kill $PLAN_PID 2>/dev/null || true
wait $PLAN_PID 2>/dev/null || true

echo ""
echo "Step 4: Checking DynamoDB for lock entries..."
aws dynamodb scan \
    --table-name tf-locks \
    --region us-east-1 \
    --max-items 5

echo ""
echo "=========================================="
echo "Test Complete!"
echo "=========================================="