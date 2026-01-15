#!/bin/bash

# Movie Analyst - Stop Resources Script
# Stops EC2 instances and RDS to save costs
# Run at end of work day

set -e

WORKSPACE="${1:-qa}"
REGION="${2:-us-east-1}"

echo "=========================================="
echo "STOPPING RESOURCES - Workspace: $WORKSPACE"
echo "=========================================="

# Set AWS region
export AWS_DEFAULT_REGION=$REGION

# Get instance IDs by tag
echo "🔍 Finding instances..."
BASTION_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-bastion-host" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

BACKEND_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-backend-*" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

FRONTEND_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-frontend-*" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

# Stop EC2 instances
echo ""
echo "⏸️  Stopping EC2 instances..."

if [ "$BASTION_ID" != "None" ]; then
  echo "   - Bastion: $BASTION_ID"
  aws ec2 stop-instances --instance-ids $BASTION_ID > /dev/null
fi

if [ "$BACKEND_IDS" != "" ]; then
  echo "   - Backend: $BACKEND_IDS"
  aws ec2 stop-instances --instance-ids $BACKEND_IDS > /dev/null
fi

if [ "$FRONTEND_IDS" != "" ]; then
  echo "   - Frontend: $FRONTEND_IDS"
  aws ec2 stop-instances --instance-ids $FRONTEND_IDS > /dev/null
fi

# Stop RDS (if exists)
echo ""
echo "🗄️  Stopping RDS instance..."
RDS_ID="${WORKSPACE}-movieanalyst-db"

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_ID \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "none")

if [ "$RDS_STATUS" == "available" ]; then
  echo "   - RDS: $RDS_ID"
  aws rds stop-db-instance --db-instance-identifier $RDS_ID > /dev/null
  echo "   ⚠️  RDS will auto-start after 7 days"
else
  echo "   - RDS already stopped or not found"
fi

# Verify status
echo ""
echo "🔍 Verifying instance states..."
sleep 5  # Wait for state changes to propagate

BASTION_STATE=$(aws ec2 describe-instances \
  --instance-ids $BASTION_ID \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "unknown")

BACKEND_STATES=$(aws ec2 describe-instances \
  --instance-ids $BACKEND_IDS \
  --query 'Reservations[].Instances[].State.Name' \
  --output text 2>/dev/null || echo "unknown")

RDS_STATE=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_ID \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "unknown")

# Summary
echo ""
echo "=========================================="
echo "✅ RESOURCES STOPPED"
echo "=========================================="
echo ""
echo "📊 Current Status:"
echo "   - Bastion: $BASTION_STATE"
echo "   - Backend: $BACKEND_STATES"
echo "   - RDS: $RDS_STATE"
echo ""
echo "💰 Cost Savings:"
echo "   - EC2 instances: ~\$0.02/hour saved"
echo "   - RDS: ~\$0.017/hour saved"
echo ""
echo "💸 Still Running (unavoidable):"
echo "   - NAT Gateway: \$0.045/hour (~\$7.56/week)"
echo "   - ALB: \$0.0225/hour (~\$3.78/week)"
echo "   - EBS volumes: ~\$0.10/GB/month"
echo "   - Elastic IPs: FREE (while attached)"
echo ""
echo "📅 RDS Note: Will auto-restart in 7 days"
echo "=========================================="