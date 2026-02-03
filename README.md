# Movie Analyst - Cloud Migration Project

A production-ready cloud infrastructure for the Movie Analyst web application, deployed on AWS using Infrastructure as Code (Terraform) and Configuration Management (Ansible).

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.11+-red)](https://www.ansible.com/)
[![Node.js](https://img.shields.io/badge/Node.js-16-green)](https://nodejs.org/)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Infrastructure Components](#infrastructure-components)
- [Deployment Environments](#deployment-environments)
- [Key Features](#key-features)
- [Cost Optimization](#cost-optimization)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

This project demonstrates a complete cloud migration of the Movie Analyst application to AWS, following industry best practices for:

- **Infrastructure as Code (IaC)** with Terraform
- **Configuration Management** with Ansible
- **Multi-environment deployment** (QA and Production)
- **High Availability** architecture across multiple Availability Zones
- **Security** with defense-in-depth approach
- **Cost optimization** strategies for AWS Free Tier

**What is Movie Analyst?**

A web application that displays movie reviews from multiple publications, featuring:

- Movie catalog with scores and reviews
- Reviewer profiles with avatars
- Publication partners showcase
- RESTful API backend
- Responsive frontend interface

---

## 🏗️ Architecture

### High-Level Architecture

```
                    Internet
                       │
                ┌──────▼──────┐
                │     ALB     │ (Application Load Balancer)
                └──────┬──────┘
                       │
        ┌──────────────┼──────────────┐
        │                              │
   ┌────▼────┐                   ┌────▼────┐
   │Frontend │                   │Frontend │
   │  (Nginx)│                   │  (Nginx)│
   └─────────┘                   └─────────┘
        │                              │
        │      ┌──────────────┐        │
        └──────►     ALB      ◄────────┘
               │ (path-based) │
               └──────┬───────┘
                      │
        ┌─────────────┼─────────────┐
        │                            │
   ┌────▼────┐                 ┌────▼────┐
   │Backend-1│                 │Backend-2│
   │(Node.js)│                 │(Node.js)│
   └────┬────┘                 └────┬────┘
        │                            │
        └────────────┬───────────────┘
                     │
              ┌──────▼──────┐
              │ RDS MySQL   │
              │  (Private)  │
              └─────────────┘

       ┌─────────────┐
       │   Bastion   │ (SSH Jump Host)
       │    Host     │
       └─────────────┘
```

### Network Architecture

- **VPC:** 10.0.0.0/16 (65,536 IP addresses)
- **Public Subnets:** 2 (10.0.1.0/24, 10.0.2.0/24) - ALB, Frontend, Bastion
- **Private Subnets:** 2 (10.0.11.0/24, 10.0.12.0/24) - Backend instances
- **Database Subnets:** 2 (10.0.21.0/24, 10.0.22.0/24) - RDS MySQL
- **Availability Zones:** us-east-1a, us-east-1b (High Availability)

---

## 🛠️ Tech Stack

### Infrastructure

| Component                    | Technology    | Version |
| ---------------------------- | ------------- | ------- |
| **IaC**                      | Terraform     | >= 1.0  |
| **Configuration Management** | Ansible       | 2.11+   |
| **Cloud Provider**           | AWS           | N/A     |
| **State Backend**            | S3 + DynamoDB | N/A     |

### Application

| Component           | Technology        | Version |
| ------------------- | ----------------- | ------- |
| **Backend**         | Node.js + Express | 16 LTS  |
| **Frontend**        | Node.js + Express | 16 LTS  |
| **Database**        | MySQL             | 8.0     |
| **Process Manager** | PM2               | Latest  |
| **Web Server**      | Nginx             | 1.28    |
| **Static Assets**   | S3                | N/A     |

### AWS Services

- **Compute:** EC2 (t3.micro)
- **Database:** RDS MySQL (db.t3.micro)
- **Load Balancing:** Application Load Balancer
- **Storage:** S3 (static assets), EBS (instance storage)
- **Networking:** VPC, NAT Gateway, Internet Gateway
- **Security:** Security Groups, IAM Roles, Secrets Manager
- **Monitoring:** CloudWatch Dashboards, Alarms
- **DNS:** Route 53 (optional)

---

## 📦 Prerequisites

### Required Software

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Git](https://git-scm.com/)
- SSH Client (OpenSSH, Git Bash for Windows)

### AWS Account Requirements

- AWS Account with administrator access
- AWS CLI configured with credentials
- Programmatic access enabled (Access Key ID + Secret Access Key)
- Region: `us-east-1` (recommended for Free Tier optimization)

### Local Setup

```bash
# Verify installations
terraform --version
aws --version
git --version
ssh -V

# Configure AWS credentials
aws configure
```

---

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/stefanyralvgh/fp-devops-cloud.git
cd fp-devops-cloud
```

### 2. Initialize Terraform Backend (First-time only)

```bash
# Create S3 bucket for state
aws s3 mb s3://terraform-state-cloud-auto-epam-stef --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket terraform-state-cloud-auto-epam-stef \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 3. Generate SSH Key Pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/movie-analyst-bastion-key
chmod 400 ~/.ssh/movie-analyst-bastion-key

# Copy public key to Terraform keys directory
mkdir -p terraform/keys
cp ~/.ssh/movie-analyst-bastion-key.pub terraform/keys/
```

### 4. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Create and select QA workspace
terraform workspace new qa
terraform workspace select qa

# Review plan
terraform plan

# Apply configuration
terraform apply
```

**Deployment time:** ~15-20 minutes

### 5. Configure Ansible (from Bastion Host)

```bash
# SSH to Bastion
BASTION_IP=$(terraform output -raw bastion_public_ip)
ssh -A ec2-user@$BASTION_IP

# Clone repository on Bastion
git clone https://github.com/stefanyralvgh/fp-devops-cloud.git
cd fp-devops-cloud/ansible

# Update inventory with actual IPs (see docs/deployment-manual.md)
nano inventory/qa.ini

# Create Ansible Vault for database password
ansible-vault create inventory/group_vars/backend/vault.yml
```

### 6. Deploy Application

```bash
# Deploy backend
ansible-playbook -i inventory/qa.ini playbooks/backend.yml --ask-vault-pass

# Deploy frontend
ansible-playbook -i inventory/qa.ini playbooks/frontend.yml --ask-vault-pass
```

### 7. Access Application

```bash
# Get ALB DNS name
terraform output alb_dns_name

# Open in browser
http://<ALB_DNS_NAME>
```

---

## 📁 Project Structure

```
fp-devops-cloud/
├── terraform/                    # Infrastructure as Code
│   ├── modules/
│   │   ├── networking/          # VPC, subnets, routing
│   │   ├── security/            # Security groups
│   │   ├── compute/             # EC2 instances, IAM roles
│   │   ├── database/            # RDS MySQL
│   │   ├── loadbalancer/        # Application Load Balancer
│   │   └── s3/                  # S3 bucket for assets
│   ├── main.tf                  # Root module
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── providers.tf             # Provider configuration
│   ├── backend.tf               # Remote state configuration
│   └── key_pair.tf              # SSH key pair resource
│
├── ansible/                     # Configuration Management
│   ├── inventory/
│   │   ├── qa.ini              # QA environment hosts
│   │   ├── prod.ini            # Production environment hosts
│   │   └── group_vars/
│   │       └── backend/
│   │           └── vault.yml   # Encrypted database credentials
│   ├── playbooks/
│   │   ├── common.yml          # Baseline system configuration
│   │   ├── backend.yml         # Backend deployment
│   │   └── frontend.yml        # Frontend deployment
│   └── roles/
│       ├── common/             # Base system setup (all hosts)
│       ├── backend/            # Node.js API deployment
│       └── frontend/           # Nginx + frontend deployment
│
├── docs/
│   ├── DAILY_LOGS.md           # Daily development logs
│   ├── technical-decisions.md  # Architecture decisions
│   └── deployment-manual.md    # Detailed deployment guide
│
└── README.md                    # This file
```

---

## 🔧 Infrastructure Components

### Networking (VPC Module)

- **VPC:** Custom VPC with DNS support
- **Internet Gateway:** Public internet access
- **NAT Gateway:** Outbound internet for private subnets
- **Route Tables:** Separate for public, private, and database tiers
- **Subnets:** 6 subnets across 2 AZs (high availability)

### Security (Security Module)

- **Bastion SG:** SSH from administrator IP only
- **ALB SG:** HTTP/HTTPS from internet
- **Frontend SG:** HTTP from ALB, SSH from Bastion
- **Backend SG:** Port 3000 from ALB, SSH from Bastion
- **RDS SG:** MySQL port 3306 from Backend only

### Compute (Compute Module)

- **Bastion Host:** t3.micro in public subnet (SSH jump server)
- **Frontend Instances:** 2x t3.micro in public subnets (Nginx + Node.js)
- **Backend Instances:** 2x t3.micro in private subnets (Node.js API + PM2)
- **IAM Roles:** Least-privilege access to AWS services

### Database (Database Module)

- **RDS MySQL 8.0:** db.t3.micro instance
- **Storage:** 20GB GP3, encrypted, auto-scaling up to 100GB
- **Multi-AZ:** Enabled in Production only (QA uses Single-AZ)
- **Backups:** 1 day retention (QA), 7 days (Production)
- **Password Management:** AWS Secrets Manager

### Load Balancer (ALB Module)

- **Application Load Balancer:** Internet-facing, cross-zone enabled
- **Target Groups:** Separate for frontend (port 80) and backend (port 3000)
- **Health Checks:** `/` for frontend, `/health` for backend
- **Path-based Routing:** `/api/*` → Backend, `/*` → Frontend

### Storage (S3 Module)

- **Static Assets Bucket:** Reviewer avatars, logos
- **CORS Configuration:** Allows frontend domain
- **Versioning:** Enabled
- **Public Read Access:** For avatar images

---

## 🌍 Deployment Environments

### QA Environment

**Purpose:** Development, testing, staging

**Configuration:**

- Single NAT Gateway (cost optimization)
- RDS Single-AZ (acceptable downtime)
- 1-day backup retention
- Basic CloudWatch monitoring (5-minute intervals)
- Deletion protection disabled (frequent teardown)

**Estimated Cost:** ~$15-30/month (with stop/start strategy)

### Production Environment

**Purpose:** Live application serving real users

**Configuration:**

- Dual NAT Gateways (high availability)
- RDS Multi-AZ (automatic failover)
- 7-day backup retention
- Enhanced CloudWatch monitoring (1-minute intervals)
- Deletion protection enabled
- Read replica (optional)

**Estimated Cost:** ~$50/month

### Switching Environments

```bash
# Switch to QA
terraform workspace select qa
terraform apply

# Switch to Production
terraform workspace select prod
terraform apply
```

---

## ✨ Key Features

### Infrastructure as Code

- **Modular Terraform Design:** Reusable modules for networking, security, compute
- **Workspace Isolation:** Separate state for QA and Production
- **Remote State Management:** S3 backend with DynamoDB locking
- **Idempotent Deployments:** Safe to run multiple times

### Configuration Management

- **Role-Based Ansible:** Separate roles for common, backend, frontend
- **Vault Encryption:** Secure database credentials
- **Idempotent Playbooks:** Safe to re-run
- **Tag-Based Execution:** Run specific tasks only

### High Availability

- **Multi-AZ Deployment:** Resources distributed across 2 availability zones
- **Auto-Healing:** PM2 restarts failed processes
- **Load Balancing:** Traffic distributed across healthy instances
- **Database Failover:** RDS Multi-AZ (Production)

### Security

- **Defense in Depth:** Multiple security layers (SGs, IAM, encryption)
- **Least Privilege:** IAM roles with minimum required permissions
- **Encrypted Storage:** RDS and EBS volumes
- **Secrets Management:** AWS Secrets Manager for database passwords
- **SSH Bastion:** Single hardened entry point for infrastructure access

### Monitoring & Observability

- **CloudWatch Dashboard:** Real-time metrics for all components
- **CloudWatch Alarms:** Automated alerts for:
  - High CPU utilization (>80%)
  - Database connections (>80 for QA, >160 for Prod)
  - ALB unhealthy targets
  - RDS storage space (<20%)
- **Application Logs:** PM2 logs + CloudWatch Logs integration

---

## 💰 Cost Optimization

### Strategies Implemented

1. **AWS Free Tier Maximization**

   - t3.micro instances (750 hours/month free)
   - RDS db.t3.micro (750 hours/month free)
   - 30GB EBS storage (free tier limit)
   - 100GB data transfer out (free tier limit)

2. **Resource Right-Sizing**

   - Single NAT Gateway in QA (vs. dual in Production)
   - Single-AZ RDS in QA (vs. Multi-AZ in Production)
   - No read replicas in QA

3. **Stop/Start Strategy (QA)**

   ```bash
   # Stop instances when not in use
   aws ec2 stop-instances --instance-ids $(terraform output -json backend_instance_ids | jq -r '.[]')

   # Start when needed
   aws ec2 start-instances --instance-ids $(terraform output -json backend_instance_ids | jq -r '.[]')
   ```

4. **Destroy/Recreate (QA)**

   ```bash
   # Destroy infrastructure when not needed
   terraform destroy

   # Recreate when needed (~20 minutes)
   terraform apply
   ```

### Cost Breakdown (Monthly)

| Component         | QA (24/7)      | QA (16h/day) | Production |
| ----------------- | -------------- | ------------ | ---------- |
| EC2 (5x t3.micro) | $0 (free tier) | $0           | $0         |
| RDS (db.t3.micro) | $0 (free tier) | $0           | $0         |
| NAT Gateway       | $32            | $7           | $64        |
| ALB               | $16            | $16          | $16        |
| EBS (40GB)        | $0 (free tier) | $0           | $0         |
| S3 (1GB)          | $0.02          | $0.02        | $0.05      |
| **Total**         | **~$48**       | **~$23**     | **~$80**   |

**Note:** Free tier benefits last for 12 months from AWS account creation.

---

## 📚 Documentation

### Available Documentation

- **[Deployment Manual](docs/deployment-manual.md):** Step-by-step deployment guide
- **[Technical Decisions](docs/technical-decisions.md):** Architecture decisions and rationale
- **[Daily Logs](docs/DAILY_LOGS.md):** Development progress and learnings

### Architecture Diagrams

All diagrams are available in the `docs/` directory and include:

- Network topology
- Security group flow
- Application architecture
- Data flow diagram

---

## 🔍 Troubleshooting

### Common Issues

#### Cannot SSH to Bastion

```bash
# Verify security group allows your IP
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=qa-bastion-sg"

# Check SSH key permissions
chmod 400 ~/.ssh/movie-analyst-bastion-key

# Test connection with verbose output
ssh -vvv -i ~/.ssh/movie-analyst-bastion-key ec2-user@$BASTION_IP
```

#### Application Not Responding

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw backend_target_group_arn)

# Check PM2 process status (from Backend instance)
sudo -u backend pm2 list
sudo -u backend pm2 logs movie-analyst-api --err
```

#### Database Connection Failed

```bash
# Verify RDS is available
aws rds describe-db-instances \
  --db-instance-identifier qa-movie-analyst-db

# Test connection from Backend
mysql -h $(terraform output -raw db_endpoint) -u admin -p
```

### Getting Help

1. Check [Deployment Manual](docs/deployment-manual.md) for detailed troubleshooting
2. Review [Daily Logs](docs/DAILY_LOGS.md) for known issues and solutions
3. Open an issue in the GitHub repository

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## 👤 Author

- GitHub: [@stefanyralvgh](https://github.com/stefanyralvgh)
- Project: DevOps Final Project - EPAM

---

**Last Updated:** February 2, 2026  
**Project Version:** 1.0.0  
**Terraform Version:** 1.0+  
**Ansible Version:** 2.11+
