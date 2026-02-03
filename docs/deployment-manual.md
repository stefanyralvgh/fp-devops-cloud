# Movie Analyst - Deployment Manual

**Project:** Cloud Migration with Terraform & Ansible  
**Environments:** QA, Production  
**Last Updated:** February 2, 2026

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
  - S3 bucket for static assets
  - CloudWatch Dashboard + 5 Alarms

#### 1.6 Capture Terraform Outputs

```bash
terraform output > outputs.txt
```

Save these values (needed later):

- `bastion_public_ip`
- `alb_dns_name`
- `db_endpoint`
- `assets_bucket_name`
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

- **Username:** Your GitHub username
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
db_endpoint=qa-movie-analyst-db.XXXXXX.us-east-1.rds.amazonaws.com  # ← Replace

[frontend:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/movie-analyst-bastion-key
ansible_python_interpreter=/usr/bin/python2
alb_dns_name=qa-movie-analyst-alb-XXXXXX.us-east-1.elb.amazonaws.com  # ← Replace

[all:vars]
environment=qa
```

Save: **Ctrl+O** → **Enter** → **Ctrl+X**

#### 3.3 Commit Changes

```bash
git add inventory/qa.ini
git commit -m "Configure QA inventory with actual IPs"
git push origin develop
```

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

# CRITICAL: Create vault in inventory/group_vars/backend/
mkdir -p inventory/group_vars/backend

# Create encrypted vault file
ansible-vault create inventory/group_vars/backend/vault.yml
```

**Vault password prompt:** Enter the password you chose above.

In the editor, add:

```yaml
---
vault_db_password: "YOUR_DATABASE_PASSWORD_FROM_SECRETS_MANAGER"
```

Save: **Esc** → **:wq** → **Enter**

**IMPORTANT:** The vault file MUST be in `inventory/group_vars/backend/vault.yml` because Ansible prioritizes this location over `group_vars/backend/vault.yml`.

#### 4.3 Verify Vault Location

```bash
# Check that vault is in the correct location
ls -la inventory/group_vars/backend/vault.yml

# Verify you can decrypt it
ansible-vault view inventory/group_vars/backend/vault.yml
```

#### 4.4 Commit Vault File

```bash
git add inventory/group_vars/backend/vault.yml .vault_pass
git commit -m "Add encrypted database credentials"
git push origin develop
```

**Security note:** `.vault_pass` should be in `.gitignore` (verify before pushing).

---

### Step 5: Deploy Application with Ansible

#### 5.1 Test Ansible Connectivity

```bash
# Test connection to all hosts
ansible all -i inventory/qa.ini -m ping
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

#### 5.2 Deploy Backend

```bash
ansible-playbook -i inventory/qa.ini playbooks/backend.yml --ask-vault-pass
```

- **Vault password prompt:** Enter vault password (from Step 4.2)
- **Deployment time:** ~5-7 minutes
- **Expected tasks:**
  - Create user `backend` (NOT `ec2-user`)
  - Install Node.js 16
  - Install PM2 process manager
  - Clone repository
  - Install npm dependencies
  - Configure environment variables (DB connection)
  - Start API server with PM2 as user `backend`

**Success indicators:**

```
PLAY RECAP *********************************************************************
backend-1 : ok=20 changed=7 unreachable=0 failed=0
backend-2 : ok=20 changed=7 unreachable=0 failed=0
```

**CRITICAL:** Verify PM2 is running as user `backend`:

```bash
ansible backend -i inventory/qa.ini -m shell \
  -a "ps aux | grep node" \
  --become
```

Should show: `backend XXXX ... node ...` (NOT `ec2-user`)

#### 5.3 Deploy Frontend

```bash
ansible-playbook -i inventory/qa.ini playbooks/frontend.yml --ask-vault-pass
```

- **Vault password prompt:** Enter vault password
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
Seeds successfully executed
```

**If seed fails:**

- Verify database credentials are correct
- Check database connection: `mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -e "SHOW DATABASES;"`
- Ensure tables exist: `mysql -h $DB_HOST -u $DB_USER -p$DB_PASS movieanalyst -e "SHOW TABLES;"`

---

### Step 8: Verify Backend Application

#### 8.1 Check PM2 Process Status

```bash
sudo -u backend pm2 list
```

**Expected output:**

```
┌─────┬────────────────────┬─────────┬─────────┬──────────┐
│ id  │ name               │ mode    │ status  │ user     │
├─────┼────────────────────┼─────────┼─────────┼──────────┤
│ 0   │ movie-analyst-api  │ fork    │ online  │ backend  │
└─────┴────────────────────┴─────────┴─────────┴──────────┘
```

**CRITICAL:** User column MUST show `backend`, NOT `ec2-user`.

**If status is "stopped" or "errored":**

```bash
# Check logs for errors
sudo -u backend pm2 logs movie-analyst-api --err --lines 30

# Common fix: Delete and restart (NOT just restart)
sudo -u backend pm2 delete movie-analyst-api
sudo -u backend pm2 start /opt/movie-analyst-api/ecosystem.config.js
sudo -u backend pm2 save
```

#### 8.2 Test API Endpoints

```bash
# Health check
curl http://localhost:3000
# Expected: {"service_status":"Up"}

# List movies
curl http://localhost:3000/movies
# Expected: JSON array with movie objects
```

**If API doesn't respond:**

```bash
# Check PM2 logs
sudo -u backend pm2 logs movie-analyst-api --err --lines 30

# Verify environment variables
sudo -u backend pm2 env 0 | grep DB_

# Check ecosystem.config.js
cat /opt/movie-analyst-api/ecosystem.config.js | grep DB_
```

---

### Step 9: Update Reviewer Avatars with S3

#### 9.1 Generate New Avatars

_From your LOCAL machine (NOT from Bastion):_

```bash
# Create temporary directory
mkdir -p /tmp/avatars
cd /tmp/avatars

# Generate 7 unique avatars (smaller size: 64px)
for i in {1..7}; do
  curl "https://api.dicebear.com/7.x/avataaars/svg?seed=reviewer$i&size=64" > reviewer$i.svg
done

# Verify files created
ls -lh
```

#### 9.2 Upload to S3 Bucket

```bash
# Get bucket name from Terraform
cd ~/path/to/terraform
terraform output assets_bucket_name

# Upload avatars
aws s3 cp /tmp/avatars/ s3://qa-movie-analyst-assets/avatars/ --recursive

# Verify upload
aws s3 ls s3://qa-movie-analyst-assets/avatars/
```

#### 9.3 Update Database with S3 URLs

```bash
# Connect to database (from Backend instance or local)
mysql -h qa-movie-analyst-db.c4dgqs6w0zk3.us-east-1.rds.amazonaws.com \
  -u admin -p'YOUR_DB_PASSWORD'
```

```sql
USE movieanalyst;

-- View current URLs
SELECT id, name, avatar FROM reviewers;

-- Update with S3 URLs
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer1.svg' WHERE id = 1;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer2.svg' WHERE id = 2;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer3.svg' WHERE id = 3;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer4.svg' WHERE id = 4;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer5.svg' WHERE id = 5;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer6.svg' WHERE id = 6;
UPDATE reviewers SET avatar = 'https://qa-movie-analyst-assets.s3.amazonaws.com/avatars/reviewer7.svg' WHERE id = 7;

-- Verify update
SELECT id, name, avatar FROM reviewers;

EXIT;
```

#### 9.4 Test Avatar Display

Refresh the application in browser and verify avatars display correctly.

---

### Step 10: Frontend Validation

#### 10.1 Access Application via ALB

**From your local machine browser:**

```
http://qa-movie-analyst-alb-XXXXXX.us-east-1.elb.amazonaws.com
```

**Expected:** Movie Analyst UI loads with movie list.

#### 10.2 Test Application Features

- **Homepage:** Should display movie list
- **Latest Reviews:** Cards with movie reviews
- **Reviewer Avatars:** Should display avatars from S3
- **Authors:** Should show reviewer names and publications
- **Publication Partners:** Partner names with icons

**If frontend doesn't load:**

- **Check ALB target health:**

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw frontend_target_group_arn)
```

- **Check Nginx status (from Frontend instance):**

```bash
ssh ec2-user@10.0.1.XXX   # Frontend IP
sudo systemctl status nginx
curl localhost
```

- **Check browser console:** F12 → Console tab — look for CORS errors, API errors

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

# 4. Configure inventory: inventory/prod.ini
# Update with production IPs and endpoints

# 5. Create production vault: inventory/group_vars/backend/vault.yml
# Use production database password

# 6. Deploy with Ansible
cd ~/fp-devops-cloud/ansible
ansible-playbook -i inventory/prod.ini playbooks/backend.yml --ask-vault-pass
ansible-playbook -i inventory/prod.ini playbooks/frontend.yml --ask-vault-pass

# 7. Follow Steps 6-10 from QA deployment
#    Replace "qa" with "prod" in all configurations
```

---

## Post-Deployment Validation

### Health Check Checklist

**Infrastructure:**

- [ ] All EC2 instances running (`terraform output`)
- [ ] RDS database available
- [ ] ALB health checks passing
- [ ] NAT Gateway operational
- [ ] S3 bucket created and accessible

**Application:**

- [ ] Frontend accessible via ALB DNS
- [ ] Backend API responding (`curl http://localhost:3000`)
- [ ] Database connection successful
- [ ] PM2 processes running as user `backend`
- [ ] Avatars loading from S3

**Monitoring:**

- [ ] CloudWatch dashboard showing metrics
- [ ] CloudWatch alarms in "OK" state
- [ ] No failed deployments in Ansible

### Automated Validation Script

```bash
#!/bin/bash
# Save as: validate-deployment.sh

echo "=== Infrastructure Validation ==="
terraform output bastion_public_ip
terraform output alb_dns_name
terraform output db_endpoint
terraform output assets_bucket_name

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
- Verify IAM permissions (need EC2, RDS, VPC, S3 full access)
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

**Symptom:** Can't connect to MySQL server or `ER_ACCESS_DENIED_ERROR`

**Solutions:**

- Verify security group allows Backend → RDS:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=qa-rds-sg"
```

- Check RDS status: `aws rds describe-db-instances`
- Verify password in vault matches Secrets Manager
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

#### Issue 6: Backend API Not Responding After Configuration Change

**Symptom:** `curl http://localhost:3000/movies` hangs or times out after editing `ecosystem.config.js`

**Root Cause:** PM2 does NOT reload the `ecosystem.config.js` file when using `pm2 restart`. It only reloads when using `pm2 delete` + `pm2 start`.

**CRITICAL SOLUTION:**

```bash
# WRONG: This does NOT reload ecosystem.config.js
sudo -u backend pm2 restart movie-analyst-api  # ❌ DON'T DO THIS

# CORRECT: Delete and re-start to reload ecosystem.config.js
sudo -u backend pm2 delete movie-analyst-api   # ✅ Step 1: Delete
sudo -u backend pm2 list                       # ✅ Step 2: Verify empty
sudo -u backend pm2 start /opt/movie-analyst-api/ecosystem.config.js  # ✅ Step 3: Start fresh
sudo -u backend pm2 save                       # ✅ Step 4: Save config

# Verify environment variables loaded correctly
sudo -u backend pm2 env 0 | grep DB_HOST
# Should show the correct database endpoint

# Test API
curl http://localhost:3000/movies
```

**IMPORTANT:** If you manually edited `ecosystem.config.js` to fix database credentials or endpoints, you MUST use this delete + start sequence. Using `pm2 restart` will keep using old cached environment variables.

**Repeat for all backend instances:**

```bash
# Backend-2
ssh ec2-user@[backend-2-ip]
sudo -u backend pm2 delete movie-analyst-api
sudo -u backend pm2 start /opt/movie-analyst-api/ecosystem.config.js
sudo -u backend pm2 save
curl http://localhost:3000/movies
```

#### Issue 7: Ansible Vault Has Multiple Files with Different Passwords

**Symptom:** Backend instances have wrong database endpoint (e.g., QA endpoint in production)

**Root Cause:** Ansible prioritizes variables in this order:

1. `inventory/group_vars/backend/vault.yml` (HIGHEST priority)
2. `group_vars/backend/vault.yml` (lower priority)

If you have both files with different values, the one in `inventory/` wins.

**Solution:**

```bash
# Find all vault files
cd ~/fp-devops-cloud/ansible
find . -name "vault.yml" -o -name "*vault*"

# Check which vault is being used
ansible-vault view inventory/group_vars/backend/vault.yml
ansible-vault view group_vars/backend/vault.yml  # If exists

# Update the CORRECT vault (the one in inventory/)
ansible-vault edit inventory/group_vars/backend/vault.yml

# Verify the password is correct
ansible-vault view inventory/group_vars/backend/vault.yml | grep vault_db_password

# Delete duplicate vaults to avoid confusion
rm group_vars/backend/vault.yml  # If exists

# Force regeneration of ecosystem.config.js
ansible backend -i inventory/qa.ini -m file \
  -a "path=/opt/movie-analyst-api/ecosystem.config.js state=absent" \
  --become

# Re-run Ansible to apply correct password
ansible-playbook -i inventory/qa.ini playbooks/backend.yml --ask-vault-pass

# Verify password in ecosystem.config.js
ansible backend -i inventory/qa.ini -m shell \
  -a "grep 'DB_PASS' /opt/movie-analyst-api/ecosystem.config.js" \
  --become

# CRITICAL: Delete and restart PM2 (not just restart)
ansible backend -i inventory/qa.ini -m shell \
  -a "sudo -u backend pm2 delete movie-analyst-api && sudo -u backend pm2 start /opt/movie-analyst-api/ecosystem.config.js && sudo -u backend pm2 save" \
  --become
```

#### Issue 8: PM2 Running as Wrong User (ec2-user instead of backend)

**Symptom:** Application works but runs as `ec2-user` instead of `backend`

**Root Cause:** Ansible role created user with `system: yes` which creates a restricted system user without proper home directory.

**Solution:**

```bash
# Check current user running PM2
ps aux | grep node
# Should show: backend XXXX ... node ...
# NOT: ec2-user XXXX ... node ...

# If running as ec2-user, fix it:

# 1. Stop all PM2 processes
sudo -u ec2-user pm2 delete all
sudo -u ec2-user pm2 kill

# 2. Recreate backend user correctly
sudo userdel -r backend 2>/dev/null || true
sudo useradd -m -s /bin/bash backend  # Note: NOT -system
sudo chmod 755 /home/backend
sudo usermod -aG wheel backend

# 3. Verify user was created correctly
groups backend  # Should show: backend wheel
ls -la /home/ | grep backend  # Should show: drwxr-xr-x

# 4. Re-run Ansible to deploy as correct user
ansible-playbook -i inventory/qa.ini playbooks/backend.yml --ask-vault-pass

# 5. Verify PM2 is running as backend
sudo -u backend pm2 list
ps aux | grep node  # Should show "backend" as user
```

**IMPORTANT:** Update your Ansible role to prevent this:

**File:** `ansible/roles/backend/tasks/application.yml`

```yaml
- name: Create backend user
  user:
    name: "{{ app_user }}"
    comment: "Backend application user"
    shell: /bin/bash
    create_home: yes
    system: no # ← CRITICAL: Must be "no", not "yes"
  become: yes
```

#### Issue 9: S3 Bucket Access Denied When Uploading Avatars

**Symptom:** `AccessDenied` error when running `aws s3 cp` from Bastion

**Root Cause:** Bastion IAM role doesn't have S3 permissions by default.

**Solution:**

Upload from your LOCAL machine instead of Bastion:

```bash
# From your local machine (NOT from Bastion)
cd /tmp/avatars
aws s3 cp . s3://qa-movie-analyst-assets/avatars/ --recursive

# Verify upload
aws s3 ls s3://qa-movie-analyst-assets/avatars/
```

**Alternative:** Add S3 permissions to Bastion role in Terraform (optional):

**File:** `terraform/modules/security/main.tf`

```hcl
resource "aws_iam_role_policy" "bastion_s3" {
  name = "s3-assets-access"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.environment}-movie-analyst-assets",
          "arn:aws:s3:::${var.environment}-movie-analyst-assets/*"
        ]
      }
    ]
  })
}
```

---

## Destroy Infrastructure

### Graceful Shutdown (Recommended)

```bash
# 1. Stop application processes (from Bastion)
ansible all -i inventory/qa.ini -m shell -a "sudo -u backend pm2 stop all" --become

# 2. Backup database (if needed)
# [Manually export from RDS Console or use mysqldump]

# 3. Empty S3 bucket (REQUIRED before destroy)
aws s3 rm s3://qa-movie-analyst-assets --recursive

# 4. Destroy Terraform resources
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
aws s3 ls | grep movie-analyst

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
# Empty S3 bucket first
aws s3 rm s3://qa-movie-analyst-assets --recursive

# Destroy infrastructure
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
  - `docs/technical-decisions.md` - Architecture decisions and rationale
  - `docs/DAILY_LOGS.md` - Daily development logs
  - `docs/architecture.png` - Visual architecture diagram

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
terraform workspace select qa     # Switch workspace
terraform output                  # Show all outputs
terraform state list              # List all resources
terraform plan -out=plan.tfplan   # Save plan
terraform apply plan.tfplan       # Apply saved plan
terraform taint aws_instance.backend  # Mark for recreation
```

**Ansible:**

```bash
ansible all -m ping -i inventory/qa.ini          # Test connectivity
ansible-playbook --syntax-check FILE             # Validate syntax
ansible-playbook --check FILE                    # Dry run
ansible-playbook --list-tasks FILE               # Show tasks
ansible-vault edit FILE                          # Edit encrypted file
ansible-vault view FILE                          # View encrypted file
ansible backend -m shell -a "COMMAND" --become   # Run command on backends
```

**PM2:**

```bash
sudo -u backend pm2 list              # List all processes
sudo -u backend pm2 logs              # View logs (all processes)
sudo -u backend pm2 logs APP_NAME     # View specific app logs
sudo -u backend pm2 logs --err        # View only errors
sudo -u backend pm2 env 0             # View environment variables
sudo -u backend pm2 delete APP_NAME   # Delete app from PM2
sudo -u backend pm2 start FILE        # Start app from config file
sudo -u backend pm2 save              # Save PM2 process list
sudo -u backend pm2 startup           # Configure auto-start on boot
```

**AWS CLI:**

```bash
aws ec2 describe-instances            # List EC2 instances
aws rds describe-db-instances         # List RDS instances
aws elbv2 describe-load-balancers     # List ALBs
aws secretsmanager list-secrets       # List secrets
aws s3 ls                             # List S3 buckets
aws s3 ls s3://BUCKET_NAME/           # List bucket contents
```

### Quick Reference Table

| Component | Access Method            | Default Credentials                    | User Context |
| --------- | ------------------------ | -------------------------------------- | ------------ |
| Bastion   | SSH via public IP        | Key: movie-analyst-bastion-key         | ec2-user     |
| Frontend  | Browser via ALB DNS      | N/A (public)                           | frontend     |
| Backend   | SSH via Bastion jump     | Key: movie-analyst-bastion-key         | backend      |
| RDS       | MySQL client via Backend | User: admin, Password: Secrets Manager | N/A          |
| ALB       | Browser (HTTP only)      | N/A (public)                           | N/A          |
| S3        | AWS CLI or Console       | IAM credentials                        | N/A          |

### PM2 vs System User Context

**CRITICAL:** Always use the correct user when managing PM2:

```bash
# ✅ CORRECT
sudo -u backend pm2 list
sudo -u backend pm2 logs movie-analyst-api
sudo -u backend pm2 restart movie-analyst-api

# ❌ WRONG (will use ec2-user's PM2, not backend's)
pm2 list
pm2 logs movie-analyst-api
sudo pm2 restart movie-analyst-api
```

**Why this matters:**

- Each system user has their own PM2 daemon
- `backend` user has proper permissions for application files
- Using wrong user context leads to permission errors and confusion
- `ec2-user` is for admin tasks, `backend` is for running the application

---

**Document Version:** 2.0  
**Last Updated:** February 2, 2026  
**Validated On:** QA and Production environments
