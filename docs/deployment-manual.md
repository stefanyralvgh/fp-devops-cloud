# Movie Analyst - Deployment Manual

**Project:** Cloud Migration with Terraform & Ansible  
**Environments:** QA, Production  
**Last Updated:** January 29, 2026

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [QA Environment Deployment](#qa-environment-deployment)
4. [Production Environment Deployment](#production-environment-deployment)
5. [Post-Deployment Validation](#post-deployment-validation)
6. [Troubleshooting](#troubleshooting)
7. [Destroy Infrastructure](#destroy-infrastructure)
8. [Cost Management](#cost-management)
9. [Support and Documentation](#support-and-documentation)
10. [Appendix](#appendix)

---

## Prerequisites

### Required Tools

| Tool       | Version | Installation                                   |
| ---------- | ------- | ---------------------------------------------- |
| Terraform  | >= 1.0  | [Download](https://www.terraform.io/downloads) |
| AWS CLI    | >= 2.0  | [Download](https://aws.amazon.com/cli/)        |
| Git        | >= 2.0  | [Download](https://git-scm.com/)               |
| SSH Client | Any     | Windows: Git Bash, macOS/Linux: Built-in       |

### AWS Account Setup

- AWS Account with administrator access
- AWS CLI configured:

```bash
aws configure
# AWS Access Key ID: [your-access-key]
# AWS Secret Access Key: [your-secret-key]
# Default region: us-east-1
# Default output format: json
```

- Verify AWS credentials:

```bash
aws sts get-caller-identity
```

### SSH Key Pair

- **Location:** `~/.ssh/movie-analyst-bastion-key`
- **Generate (if not exists):**

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/movie-analyst-bastion-key -C "bastion@movie-analyst"
chmod 400 ~/.ssh/movie-analyst-bastion-key
```

- **Important:** Copy the public key to `terraform/keys/`:

```bash
mkdir -p terraform/keys
cp ~/.ssh/movie-analyst-bastion-key.pub terraform/keys/
```

### GitHub Access

- **Repository:** `https://github.com/stefanyralvgh/fp-devops-cloud.git`
- **Personal Access Token:** Required for Bastion git operations
- **Generate token:** GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token
- **Required scopes:** `repo` (full control of private repositories)

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                        Internet                             │
                    └──────────────────┬──────────────────────────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │      Application Load Balancer      │
                    │              (Public)                │
                    └────────────┬─────────────┬───────────┘
                                 │             │
              ┌──────────────────▼──┐    ┌─────▼──────────────────┐
              │     Frontend-1      │    │      Frontend-2         │
              │      (Public)       │    │       (Public)          │
              └────────────────────┘    └─────────────────────────┘
                                 │             │
              ┌──────────────────▼──┐    ┌─────▼──────────────────┐
              │     Backend-1       │    │      Backend-2          │
              │     (Private)       │    │      (Private)          │
              └──────────┬─────────┘    └──────────┬──────────────┘
                         │                          │
                         └──────────────┬───────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │        RDS MySQL            │
                         │        (Private)            │
                         └─────────────────────────────┘

                    ┌─────────────────┐
                    │  Bastion Host   │
                    │ (Jump Server)   │
                    └─────────────────┘
```

**Components:**

| Component    | Description                                           |
| ------------ | ----------------------------------------------------- |
| **ALB**      | Routes API traffic to backend instances               |
| **Frontend** | Express server (port 3030) behind Nginx reverse proxy |
| **Backend**  | Node.js API (port 3000, PM2 process manager)          |
| **RDS**      | MySQL 8.0 database                                    |
| **Bastion**  | SSH jump host for infrastructure access               |

---

## QA Environment Deployment

### Step 1: Infrastructure Provisioning

#### 1.1 Initialize Terraform Backend

_First-time setup only:_

```bash
# Create S3 bucket for Terraform state (manual, one-time)
aws s3 mb s3://terraform-state-cloud-auto-epam-stef --region us-east-1
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

#### 1.2 Clone Repository

```bash
git clone https://github.com/stefanyralvgh/fp-devops-cloud.git
cd fp-devops-cloud
git checkout develop
cd terraform
```

#### 1.3 Initialize Terraform

```bash
terraform init
```

**Expected output:** `Terraform has been successfully initialized!`

#### 1.4 Select QA Workspace

```bash
# Create workspace (first time only)
terraform workspace new qa

# Or select existing workspace
terraform workspace select qa

# Verify current workspace
terraform workspace show
# Output: qa
```

#### 1.5 Deploy Infrastructure

```bash
# Review planned changes
terraform plan

# Apply configuration
terraform apply
```

- **Confirmation required:** Type `yes` when prompted.
- **Deployment time:** ~15-20 minutes
- **Resources created:**
  - VPC with 6 subnets (2 public, 2 private, 2 database)
  - Internet Gateway + NAT Gateway
  - 5 Security Groups
  - 5 EC2 instances (1 Bastion, 2 Frontend, 2 Backend)
  - RDS MySQL instance
  - Application Load Balancer
  - CloudWatch Dashboard + 5 Alarms

#### 1.6 Capture Terraform Outputs

```bash
terraform output > outputs.txt
```

Save these values (needed later):

- `bastion_public_ip`
- `alb_dns_name`
- `db_endpoint`
- Backend private IPs
- Frontend private IPs

---

### Step 2: SSH Configuration

#### 2.1 Configure SSH Agent (Windows - Git Bash)

```bash
# Start SSH agent
eval $(ssh-agent -s)

# Add SSH key
ssh-add ~/.ssh/movie-analyst-bastion-key

# Verify key loaded
ssh-add -l
```

#### 2.2 Test Bastion Connection

```bash
# Get Bastion IP from Terraform output
BASTION_IP=$(terraform output -raw bastion_public_ip)

# Connect to Bastion
ssh -A ec2-user@$BASTION_IP
```

**Expected prompt:**

```
=====================================
Movie Analyst Bastion Host
Environment: qa
=====================================
[ec2-user@bastion-qa ~]$
```

**If connection fails:**

- Verify security group allows SSH from your IP (should be auto-configured)
- Check SSH key permissions: `ls -la ~/.ssh/movie-analyst-bastion-key` (should be `-r--------`)
- Verify Bastion instance is running: `aws ec2 describe-instances`

---

### Step 3: Configure Ansible on Bastion

#### 3.1 Clone Repository on Bastion

```bash
# From Bastion terminal
git clone https://github.com/stefanyralvgh/fp-devops-cloud.git
cd fp-devops-cloud
git checkout develop
cd ansible
```

**Authentication:**

- **Username:** stefanyralvgh (or your GitHub username)
- **Password:** [GitHub Personal Access Token]

**Troubleshooting:**

```bash
# If authentication fails
git config --global credential.helper store
git pull  # Re-enter credentials (will be saved)
```

#### 3.2 Update Ansible Inventory

**File:** `ansible/inventory/qa.ini`

```bash
# Get values from Terraform outputs (from your local machine)
terraform output backend_private_ips
terraform output frontend_private_ips
terraform output db_endpoint
terraform output alb_dns_name
```

Edit inventory:

```bash
nano inventory/qa.ini
```

Update with actual values:

```ini
[backend]
backend-1 ansible_host=10.0.11.XXX   # ← Replace with actual IP
backend-2 ansible_host=10.0.12.XXX   # ← Replace with actual IP

[frontend]
frontend-1 ansible_host=10.0.1.XXX   # ← Replace with actual IP
frontend-2 ansible_host=10.0.2.XXX   # ← Replace with actual IP

[backend:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/movie-analyst-bastion-key
ansible_python_interpreter=/usr/bin/python2
environment=qa
db_endpoint=qa-movie-analyst-db.XXXXXX.us-east-1.rds.amazonaws.com   # ← Replace

[frontend:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/movie-analyst-bastion-key
ansible_python_interpreter=/usr/bin/python2
alb_dns_name=qa-movie-analyst-alb-XXXXXX.us-east-1.elb.amazonaws.com   # ← Replace
```

Save: **Ctrl+O** → **Enter** → **Ctrl+X**

#### 3.3 Update Frontend ALB Configuration

**File:** `ansible/roles/frontend/defaults/main.yml`

```bash
nano roles/frontend/defaults/main.yml
```

Update line:

```yaml
backend_alb_dns: "qa-movie-analyst-alb-XXXXXX.us-east-1.elb.amazonaws.com" # ← Replace
```

Save and exit.

#### 3.4 Commit and Push Changes

```bash
git add inventory/qa.ini roles/frontend/defaults/main.yml
git commit -m "Update QA inventory with actual IPs"
git push origin develop
```

Enter GitHub credentials when prompted.

---

### Step 4: Configure Database Password (Ansible Vault)

#### 4.1 Retrieve Database Password from AWS Secrets Manager

_From your local machine:_

```bash
# Get secret ARN
terraform output -raw db_master_secret_arn

# Retrieve password
aws secretsmanager get-secret-value \
  --secret-id [SECRET_ARN_FROM_ABOVE] \
  --query SecretString \
  --output text | jq -r '.password'
```

Save this password — you'll need it in the next step.

#### 4.2 Create Ansible Vault File

_From Bastion:_

```bash
cd ~/fp-devops-cloud/ansible

# Create vault password file (choose a strong password)
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass

# Create encrypted vault file
ansible-vault create group_vars/backend/vault.yml
```

**Vault password prompt:** Enter the password you chose above.

In the editor, add:

```yaml
---
vault_db_password: "YOUR_DATABASE_PASSWORD_FROM_SECRETS_MANAGER"
```

Save: **Esc** → **:wq** → **Enter**

#### 4.3 Commit Vault File

```bash
git add group_vars/backend/vault.yml .vault_pass
git commit -m "Add encrypted database credentials"
git push origin develop
```

**Security note:** `.vault_pass` should be in `.gitignore` (verify before pushing).

---

### Step 5: Deploy Application with Ansible

#### 5.1 Test Ansible Connectivity

```bash
# Test connection to all hosts
ansible all -m ping
```

**Expected output:**

```
backend-1  | SUCCESS => { "ping": "pong" }
backend-2  | SUCCESS => { "ping": "pong" }
frontend-1 | SUCCESS => { "ping": "pong" }
frontend-2 | SUCCESS => { "ping": "pong" }
```

**If any host fails:**

- Verify IP addresses in inventory
- Check SSH key is loaded: `ssh-add -l`
- Manually test SSH: `ssh ec2-user@10.0.11.XXX`

#### 5.2 Deploy Frontend

```bash
ansible-playbook playbooks/frontend.yml --ask-vault-pass
```

- **Vault password prompt:** Enter vault password (from Step 4.2)
- **Deployment time:** ~5-7 minutes
- **Expected tasks:**
  - Install Node.js 16
  - Install PM2 process manager
  - Install Nginx
  - Clone repository
  - Install npm dependencies
  - Configure Nginx reverse proxy
  - Start application with PM2

**Success indicators:**

```
PLAY RECAP *********************************************************************
frontend-1 : ok=25 changed=8 unreachable=0 failed=0
frontend-2 : ok=25 changed=8 unreachable=0 failed=0
```

#### 5.3 Deploy Backend

```bash
ansible-playbook playbooks/backend.yml --ask-vault-pass
```

- **Vault password prompt:** Enter vault password
- **Deployment time:** ~5-7 minutes
- **Expected tasks:**
  - Install Node.js 16
  - Install PM2 process manager
  - Clone repository
  - Install npm dependencies
  - Configure environment variables (DB connection)
  - Start API server with PM2

**Success indicators:**

```
PLAY RECAP *********************************************************************
backend-1 : ok=20 changed=7 unreachable=0 failed=0
backend-2 : ok=20 changed=7 unreachable=0 failed=0
```

---

### Step 6: Database Schema Creation

#### 6.1 Connect to Backend Instance

```bash
# From Bastion
ssh ec2-user@10.0.11.XXX   # Backend-1 IP from inventory
```

#### 6.2 Connect to MySQL Database

```bash
# Get DB endpoint from inventory
mysql -h qa-movie-analyst-db.XXXXXX.us-east-1.rds.amazonaws.com -u admin -p
```

**Password prompt:** Enter database password (from Secrets Manager).

**Expected prompt:** `mysql>`

#### 6.3 Create Database Tables

```sql
USE movieanalyst;

CREATE TABLE publications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  avatar VARCHAR(255) NOT NULL
);

CREATE TABLE reviewers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  publication VARCHAR(255) NOT NULL,
  avatar VARCHAR(500) NOT NULL
);

CREATE TABLE movies (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  release_year VARCHAR(4) NOT NULL,
  score INT NOT NULL,
  reviewer VARCHAR(255) NOT NULL,
  publication VARCHAR(255) NOT NULL
);

-- Verify tables created
SHOW TABLES;

EXIT;
```

**Expected output:**

```
+------------------------+
| Tables_in_movieanalyst |
+------------------------+
| movies                 |
| publications           |
| reviewers              |
+------------------------+
```

---

### Step 7: Seed Database with Sample Data

#### 7.1 Configure Environment Variables

_From Backend instance:_

```bash
cd /opt/devops-rampup/movie-analyst-api

# Export database credentials
export DB_HOST=qa-movie-analyst-db.XXXXXX.us-east-1.rds.amazonaws.com   # ← Replace
export DB_USER=admin
export DB_PASS='YOUR_DATABASE_PASSWORD'   # ← Replace with actual password
export DB_NAME=movieanalyst
export DB_PORT=3306
```

#### 7.2 Run Seed Script

```bash
node seeds.js
```

**Expected output:**

```
✓ Database connection successful
✓ Publications seeded (3 rows)
✓ Reviewers seeded (7 rows)
✓ Movies seeded (12 rows)
✓ Seed completed successfully
```

**If seed fails:**

- Verify database credentials are correct
- Check database connection: `mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -e "SHOW DATABASES;"`
- Ensure tables exist: `mysql -h $DB_HOST -u $DB_USER -p$DB_PASS movieanalyst -e "SHOW TABLES;"`

---

### Step 8: Verify Backend Application

#### 8.1 Check PM2 Process Status

```bash
sudo -u ec2-user pm2 list
```

**Expected output:**

```
┌─────┬────────────────────┬─────────┬─────────┬──────────┐
│ id  │ name               │ mode    │ status  │ restart  │
├─────┼────────────────────┼─────────┼─────────┼──────────┤
│ 0   │ movie-analyst-api  │ fork    │ online  │ 0        │
└─────┴────────────────────┴─────────┴─────────┴──────────┘
```

**If status is "stopped":**

```bash
sudo -u ec2-user pm2 restart movie-analyst-api
sudo -u ec2-user pm2 logs   # Check for errors
```

#### 8.2 Test API Endpoints

```bash
# Health check
curl http://localhost:3000
# Expected: {"status":"ok"}

# List movies
curl http://localhost:3000/movies
# Expected: JSON array with movie objects
```

**If API doesn't respond:**

```bash
# Check PM2 logs
sudo -u ec2-user pm2 logs movie-analyst-api

# Check application logs
sudo cat /home/ec2-user/.pm2/logs/movie-analyst-api-error.log
```

---

### Step 9: Update Reviewer Avatars (Optional)

#### 9.1 Generate New Avatars

```bash
# Create temporary directory
mkdir -p /tmp/avatars
cd /tmp/avatars

# Generate 7 unique avatars
for i in {1..7}; do
  curl "https://api.dicebear.com/7.x/avataaars/svg?seed=reviewer$i&size=64" > reviewer$i.svg
done

# Verify files created
ls -lh
```

#### 9.2 Upload to S3 Bucket

_Note: This step assumes S3 bucket exists. If not created yet, skip this section._

```bash
# Upload avatars
aws s3 cp . s3://qa-movie-analyst-assets/avatars/ --recursive

# Verify upload
aws s3 ls s3://qa-movie-analyst-assets/avatars/
```

---

### Step 10: Frontend Validation

#### 10.1 Access Application

**From your local machine browser:**

```
http://[ALB_DNS_NAME]
```

Get ALB DNS:

```bash
terraform output alb_dns_name
# Example: qa-movie-analyst-alb-123456789.us-east-1.elb.amazonaws.com
```

**Expected:** Movie Analyst UI loads with movie list.

#### 10.2 Test Application Features

- **Homepage:** Should display list of movies
- **Movie details:** Click on a movie to view details
- **Reviewer info:** Should show reviewer name and publication
- **Images:** Reviewer avatars should load

**If frontend doesn't load:**

- **Check ALB health:**

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw backend_target_group_arn)
```

Expected: Targets should be "healthy"

- **Check Nginx status (from Frontend instance):**

```bash
ssh ec2-user@10.0.1.XXX   # Frontend IP
sudo systemctl status nginx
curl localhost
```

- **Check browser console:** F12 → Console tab — look for CORS errors, API errors, network failures

---

## Production Environment Deployment

_Note: Production deployment follows the same steps as QA with workspace-specific differences._

### Key Differences: QA vs Production

| Aspect              | QA            | Production       |
| ------------------- | ------------- | ---------------- |
| Workspace           | qa            | prod             |
| RDS Multi-AZ        | Disabled      | Enabled          |
| Backup Retention    | 1 day         | 7 days           |
| Deletion Protection | Disabled      | Enabled          |
| Monitoring Interval | Basic (5 min) | Enhanced (1 min) |
| Estimated Cost      | ~$30/month    | ~$50/month       |

### Production Deployment Steps

```bash
# 1. Select production workspace
cd terraform
terraform workspace select prod
# Or create: terraform workspace new prod

# 2. Review production plan
terraform plan

# 3. Deploy infrastructure
terraform apply

# 4. Follow Steps 2-10 from QA deployment
#    Replace "qa" with "prod" in all configurations

# 5. Update inventory file: inventory/prod.ini

# 6. Update vault: group_vars/prod/vault.yml

# 7. Deploy with Ansible
```

---

## Post-Deployment Validation

### Health Check Checklist

**Infrastructure:**

- All EC2 instances running (`terraform output`)
- RDS database available
- ALB health checks passing
- NAT Gateway operational

**Application:**

- Frontend accessible via ALB DNS
- Backend API responding (`curl http://localhost:3000`)
- Database connection successful
- PM2 processes running

**Monitoring:**

- CloudWatch dashboard showing metrics
- CloudWatch alarms in "OK" state
- No failed deployments in Ansible

### Automated Validation Script

```bash
#!/bin/bash
# Save as: validate-deployment.sh

echo "=== Infrastructure Validation ==="
terraform output bastion_public_ip
terraform output alb_dns_name
terraform output db_endpoint

echo "=== ALB Health Check ==="
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw backend_target_group_arn) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

echo "=== CloudWatch Alarms ==="
aws cloudwatch describe-alarms \
  --alarm-name-prefix qa- \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table

echo "=== Application Test ==="
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -s "http://$ALB_DNS" | grep -q "Movie Analyst" && echo "✓ Frontend OK" || echo "✗ Frontend Failed"
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Terraform Apply Fails

**Symptom:** Error creating [resource]

**Solutions:**

- Check AWS credentials: `aws sts get-caller-identity`
- Verify IAM permissions (need EC2, RDS, VPC full access)
- Check region: Must be us-east-1
- Review terraform.tfstate for conflicts

#### Issue 2: Cannot SSH to Bastion

**Symptom:** Connection timed out or Permission denied

**Solutions:**

- Verify your IP in security group:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=qa-bastion-sg" \
  --query 'SecurityGroups[0].IpPermissions'
```

- Check SSH key permissions: `chmod 400 ~/.ssh/movie-analyst-bastion-key`
- Verify Bastion is running: `aws ec2 describe-instances`

#### Issue 3: Ansible Playbook Fails

**Symptom:** UNREACHABLE or FAILED status

**Solutions:**

- Test manual SSH: `ssh ec2-user@10.0.11.XXX`
- Verify inventory IPs match Terraform outputs
- Check SSH agent: `ssh-add -l`
- Review Ansible logs: `ansible-playbook -vvv ...`

#### Issue 4: Database Connection Fails

**Symptom:** Can't connect to MySQL server

**Solutions:**

- Verify security group allows Backend → RDS:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=qa-rds-sg"
```

- Check RDS status: `aws rds describe-db-instances`
- Verify password: Retrieve from Secrets Manager
- Test from Backend instance: `mysql -h [endpoint] -u admin -p`

#### Issue 5: Frontend Not Loading

**Symptom:** Blank page or "Cannot connect"

**Solutions:**

- Check ALB target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn [TG_ARN]
```

- Check Nginx on Frontend:

```bash
ssh ec2-user@[frontend-ip]
sudo systemctl status nginx
curl localhost
```

- Check browser console (F12) for errors
- Verify ALB security group allows HTTP from 0.0.0.0/0

---

## Destroy Infrastructure

### Graceful Shutdown (Recommended)

```bash
# 1. Stop application processes (from Bastion)
ansible all -m shell -a "sudo -u ec2-user pm2 stop all"

# 2. Backup database (if needed)
# [Manually export from RDS Console]

# 3. Destroy Terraform resources
cd terraform
terraform workspace select qa
terraform destroy
```

- **Confirmation required:** Type `yes`
- **Destruction time:** ~10-15 minutes

### Force Destroy (Emergency)

```bash
# Skip application shutdown
terraform destroy -auto-approve
```

**Warning:** May leave orphaned resources.

### Post-Destroy Cleanup

```bash
# Verify no resources remain
aws ec2 describe-instances --filters "Name=tag:Project,Values=movie-analyst"
aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `movie-analyst`)]'

# Clean local state (optional)
rm -rf .terraform
rm terraform.tfstate*
```

---

## Cost Management

### Daily Cost Estimates

| Environment | Running 24/7 | Stopped Overnight (16h/day) |
| ----------- | ------------ | --------------------------- |
| QA          | ~$30/month   | ~$15/month                  |
| Production  | ~$50/month   | N/A (always on)             |

### Cost Optimization Strategies

**For QA Environment:**

- **Stop instances overnight:**

```bash
# Stop all EC2 instances
aws ec2 stop-instances --instance-ids \
  $(aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=qa" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)
```

- **Destroy when not in use:**

```bash
terraform destroy
# Rebuild when needed: terraform apply
```

- **Use workspaces efficiently:**
  - Deploy QA only when actively developing
  - Production runs continuously

---

## Support and Documentation

- **Project Repository:** https://github.com/stefanyralvgh/fp-devops-cloud
- **Documentation:**
  - Technical Decisions
  - Daily Development Logs
  - Architecture Diagram

**Key Files:**

- Terraform configurations: `terraform/`
- Ansible playbooks: `ansible/playbooks/`
- Ansible roles: `ansible/roles/`

---

## Appendix

### Useful Commands

**Terraform:**

```bash
terraform workspace list          # List workspaces
terraform workspace select qa    # Switch workspace
terraform output                 # Show all outputs
terraform state list             # List all resources
terraform plan -out=plan.tfplan  # Save plan
terraform apply plan.tfplan       # Apply saved plan
```

**Ansible:**

```bash
ansible all -m ping                    # Test connectivity
ansible-playbook --syntax-check FILE   # Validate syntax
ansible-playbook --check FILE          # Dry run
ansible-playbook --list-tasks FILE     # Show tasks
ansible-vault edit FILE                # Edit encrypted file
```

**AWS CLI:**

```bash
aws ec2 describe-instances        # List EC2 instances
aws rds describe-db-instances     # List RDS instances
aws elbv2 describe-load-balancers # List ALBs
aws secretsmanager list-secrets   # List secrets
```

### Quick Reference Table

| Component | Access Method            | Default Credentials                    |
| --------- | ------------------------ | -------------------------------------- |
| Bastion   | SSH via public IP        | Key: movie-analyst-bastion-key         |
| Frontend  | Browser via ALB DNS      | N/A (public)                           |
| Backend   | SSH via Bastion jump     | Key: movie-analyst-bastion-key         |
| RDS       | MySQL client via Backend | User: admin, Password: Secrets Manager |
| ALB       | Browser (HTTP only)      | N/A (public)                           |
