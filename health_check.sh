#!/bin/bash
set -e

# Retry logic wrapper
run_health_checks() {
    echo "=========================================="
    echo "POST-DEPLOYMENT HEALTH CHECKS"
    echo "=========================================="
    echo ""
    echo "Waiting 30 seconds for AWS resources to stabilize..."
    sleep 30
    echo ""

    # Get outputs from Terragrunt
    VPC_ID=$(terragrunt output -raw vpc_id 2>/dev/null || echo "")
    ALB_DNS=$(terragrunt output -raw alb_dns_name 2>/dev/null || echo "")
    BASTION_ID=$(terragrunt output -raw bastion_instance_id 2>/dev/null || echo "")
    WEB_1_ID=$(terragrunt output -raw web_1_instance_id 2>/dev/null || echo "")
    WEB_2_ID=$(terragrunt output -raw web_2_instance_id 2>/dev/null || echo "")
    S3_BUCKET=$(terragrunt output -raw s3_bucket_name 2>/dev/null || echo "")
    TG_ARN=$(terragrunt output -raw target_group_arn 2>/dev/null || echo "")

    HEALTH_STATUS="PASSED"
    FAILED_CHECKS=()

    # Check 1: Verify VPC exists
    echo ""
    echo "1. Verifying VPC..."
    if [ -n "$VPC_ID" ]; then
        VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].State" --output text 2>/dev/null || echo "")
        if [ "$VPC_STATE" = "available" ]; then
            echo "   ✓ VPC is available: $VPC_ID"
        else
            echo "   ✗ FAILED: VPC state is $VPC_STATE"
            HEALTH_STATUS="FAILED"
            FAILED_CHECKS+=("VPC not available")
        fi
    else
        echo "   ✗ FAILED: VPC ID not available"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("VPC ID missing")
    fi

    # Check 2: EC2 instances running
    echo ""
    echo "2. Verifying EC2 Instances..."
    INSTANCE_IDS="$BASTION_ID $WEB_1_ID $WEB_2_ID"
    RUNNING_COUNT=0

    for INSTANCE_ID in $INSTANCE_IDS; do
        if [ -n "$INSTANCE_ID" ]; then
            STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || echo "")
            NAME=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text 2>/dev/null || echo "unknown")
            
            if [ "$STATE" = "running" ]; then
                echo "   ✓ $NAME ($INSTANCE_ID): running"
                ((RUNNING_COUNT++))
            else
                echo "   ✗ $NAME ($INSTANCE_ID): $STATE"
                HEALTH_STATUS="FAILED"
                FAILED_CHECKS+=("Instance $NAME not running")
            fi
        fi
    done

    if [ "$RUNNING_COUNT" -ge 3 ]; then
        echo "   ✓ All 3 instances are running"
    else
        echo "   ✗ FAILED: Expected 3 running instances, found $RUNNING_COUNT"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("Not all instances running")
    fi

    # Check 3: ALB is active
    echo ""
    echo "3. Verifying Application Load Balancer..."
    if [ -n "$ALB_DNS" ]; then
        ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$ALB_DNS'].LoadBalancerArn | [0]" --output text 2>/dev/null || echo "")
        
        if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
            ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].State.Code" --output text 2>/dev/null || echo "")
            
            if [ "$ALB_STATE" = "active" ]; then
                echo "   ✓ ALB is active: $ALB_DNS"
            else
                echo "   ✗ WARNING: ALB state is $ALB_STATE (may still be provisioning)"
                if [ "$ALB_STATE" != "provisioning" ]; then
                    HEALTH_STATUS="FAILED"
                    FAILED_CHECKS+=("ALB not active")
                fi
            fi
        else
            echo "   ✗ FAILED: Could not find ALB"
            HEALTH_STATUS="FAILED"
            FAILED_CHECKS+=("ALB not found")
        fi
    else
        echo "   ✗ FAILED: ALB DNS not available"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("ALB DNS missing")
    fi

    # Check 4: Target Group Health
    echo ""
    echo "4. Verifying Target Group Health..."
    if [ -n "$TG_ARN" ]; then
        echo "   Waiting up to 2 minutes for targets to become healthy..."
        
        MAX_ATTEMPTS=24
        ATTEMPT=0
        HEALTHY_COUNT=0
        
        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
            TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" 2>/dev/null || echo "")
            
            if [ -n "$TARGET_HEALTH" ]; then
                HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length' 2>/dev/null || echo "0")
                TOTAL_COUNT=$(echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions | length' 2>/dev/null || echo "0")
                
                if [ "$HEALTHY_COUNT" -ge 2 ]; then
                    echo "   ✓ $HEALTHY_COUNT/$TOTAL_COUNT targets are healthy"
                    break
                else
                    STATES=$(echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions[].TargetHealth.State' 2>/dev/null | sort | uniq | tr '\n' ',' | sed 's/,$//')
                    echo "   ⏳ Attempt $((ATTEMPT + 1))/$MAX_ATTEMPTS: $HEALTHY_COUNT/$TOTAL_COUNT healthy (states: $STATES)"
                    sleep 5
                fi
            fi
            
            ((ATTEMPT++))
        done
        
        if [ "$HEALTHY_COUNT" -lt 2 ]; then
            echo "   ✗ FAILED: Only $HEALTHY_COUNT/2 targets are healthy after 2 minutes"
            HEALTH_STATUS="FAILED"
            FAILED_CHECKS+=("Targets not healthy")
        fi
    else
        echo "   ✗ FAILED: Target group ARN not available"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("Target group ARN missing")
    fi

    # Check 5: ALB HTTP Response
    echo ""
    echo "5. Testing ALB HTTP Response..."
    if [ -n "$ALB_DNS" ]; then
        echo "   Testing: http://$ALB_DNS"
        
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ALB_DNS" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "   ✓ ALB returned HTTP $HTTP_CODE"
            
            RESPONSE=$(curl -s --max-time 10 "http://$ALB_DNS" 2>/dev/null || echo "")
            if echo "$RESPONSE" | grep -q "Web Server 1"; then
                echo "   ✓ Response from: Web Server 1"
            elif echo "$RESPONSE" | grep -q "Web Server 2"; then
                echo "   ✓ Response from: Web Server 2"
            fi
        else
            echo "   ✗ FAILED: ALB returned HTTP $HTTP_CODE (expected 200)"
            HEALTH_STATUS="FAILED"
            FAILED_CHECKS+=("ALB HTTP check failed")
        fi
    else
        echo "   ✗ FAILED: ALB DNS not available for testing"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("Cannot test ALB - DNS missing")
    fi

    # Check 6: S3 Bucket
    echo ""
    echo "6. Verifying S3 Bucket..."
    if [ -n "$S3_BUCKET" ]; then
        if aws s3 ls "s3://$S3_BUCKET" > /dev/null 2>&1; then
            echo "   ✓ S3 bucket accessible: $S3_BUCKET"
        else
            echo "   ✗ FAILED: Cannot access S3 bucket: $S3_BUCKET"
            HEALTH_STATUS="FAILED"
            FAILED_CHECKS+=("S3 bucket not accessible")
        fi
    else
        echo "   ✗ FAILED: S3 bucket name not available"
        HEALTH_STATUS="FAILED"
        FAILED_CHECKS+=("S3 bucket name missing")
    fi

    # Check 7: Subnets
    echo ""
    echo "7. Verifying Subnets..."
    if [ -n "$VPC_ID" ]; then
        SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "length(Subnets)" --output text 2>/dev/null || echo "0")
        
        if [ "$SUBNET_COUNT" -ge 4 ]; then
            echo "   ✓ Found $SUBNET_COUNT subnets"
        else
            echo "   ✗ WARNING: Expected 4 subnets, found $SUBNET_COUNT"
        fi
    fi

    # Check 8: NAT Gateway
    echo ""
    echo "8. Verifying NAT Gateway..."
    if [ -n "$VPC_ID" ]; then
        NAT_STATE=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query "NatGateways[0].State" --output text 2>/dev/null || echo "")
        
        if [ "$NAT_STATE" = "available" ]; then
            echo "   ✓ NAT Gateway is available"
        else
            echo "   ✗ WARNING: NAT Gateway not available (state: $NAT_STATE)"
        fi
    fi

    # Return status
    if [ "$HEALTH_STATUS" = "PASSED" ]; then
        return 0
    else
        return 1
    fi
}

# Main execution with retry
echo "Attempt 1 of 2..."
if run_health_checks; then
    echo ""
    echo "=========================================="
    echo "✅ ALL CRITICAL CHECKS PASSED"
    echo "=========================================="
    echo "Environment: ${ENV}"
    echo "Region: ${AWS_DEFAULT_REGION}"
    echo ""
    exit 0
else
    echo ""
    echo "=========================================="
    echo "⚠️  FIRST ATTEMPT FAILED - RETRYING"
    echo "=========================================="
    echo "Waiting 30 seconds before retry..."
    sleep 30
    echo ""
    echo "Attempt 2 of 2..."
    
    if run_health_checks; then
        echo ""
        echo "=========================================="
        echo "✅ HEALTH CHECKS PASSED ON RETRY"
        echo "=========================================="
        echo "Environment: ${ENV}"
        echo "Region: ${AWS_DEFAULT_REGION}"
        echo ""
        exit 0
    else
        echo ""
        echo "=========================================="
        echo "❌ HEALTH CHECKS FAILED TWICE"
        echo "=========================================="
        echo "Infrastructure will be destroyed for investigation"
        echo ""
        exit 1
    fi
fi
