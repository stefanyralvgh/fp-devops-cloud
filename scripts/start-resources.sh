#!/bin/bash

# Movie Analyst - Start Resources Script
# Starts EC2 instances and RDS for work
# Run at beginning of work day

set -e

WORKSPACE="${1:-qa}"
REGION="${2:-us-east-1}"

echo "=========================================="
echo "STARTING RESOURCES - Workspace: $WORKSPACE"
echo "=========================================="

# Set AWS region
export AWS_DEFAULT_REGION=$REGION

# Get instance IDs by tag
echo "🔍 Finding instances..."
BASTION_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-bastion-host" \
            "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

BACKEND_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-backend-*" \
            "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

FRONTEND_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${WORKSPACE}-frontend-*" \
            "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

# Start EC2 instances
echo ""
echo "▶️  Starting EC2 instances..."

if [ "$BASTION_ID" != "None" ]; then
  echo "   - Bastion: $BASTION_ID"
  aws ec2 start-instances --instance-ids $BASTION_ID > /dev/null
fi

if [ "$BACKEND_IDS" != "" ]; then
  echo "   - Backend: $BACKEND_IDS"
  aws ec2 start-instances --instance-ids $BACKEND_IDS > /dev/null
fi

if [ "$FRONTEND_IDS" != "" ]; then
  echo "   - Frontend: $FRONTEND_IDS"
  aws ec2 start-instances --instance-ids $FRONTEND_IDS > /dev/null
fi

# Start RDS (if stopped)
echo ""
echo "🗄️  Starting RDS instance..."
RDS_ID="${WORKSPACE}-movieanalyst-db"

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_ID \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "none")

if [ "$RDS_STATUS" == "stopped" ]; then
  echo "   - RDS: $RDS_ID"
  aws rds start-db-instance --db-instance-identifier $RDS_ID > /dev/null
elif [ "$RDS_STATUS" == "available" ]; then
  echo "   - RDS already running"
else
  echo "   - RDS not found or in transition"
fi

# Wait for instances to be running
echo ""
echo "⏳ Waiting for instances to start..."
sleep 10

# Get Bastion public IP
BASTION_IP=$(aws ec2 describe-instances \
  --instance-ids $BASTION_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null || echo "pending")

# Summary
echo ""
echo "=========================================="
echo "✅ RESOURCES STARTED"
echo "=========================================="
echo ""
if [ "$BASTION_IP" != "pending" ]; then
  echo "🔑 Bastion SSH: ssh -i ~/.ssh/movie-analyst-bastion-key ec2-user@$BASTION_IP"
else
  echo "⏳ Bastion IP still pending, wait 30 seconds"
fi
echo ""
echo "💡 Tip: Run 'terraform output' to see all connection info"
echo "=========================================="