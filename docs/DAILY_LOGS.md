# Daily Development Log

## Day 1 - January 6, 2026

**Status:** ✅ Complete

### What I Did

- Set up development environment (Git, AWS CLI, Terraform, VS Code)
- Configured AWS credentials
- Created project structure (terraform/, ansible/, docs/)
- Manually created S3 bucket and DynamoDB table for Terraform backend (AWS CLI)
- Initialized Git repository with develop branch

### Key Decisions

- Use S3 + DynamoDB for remote state (enables team collaboration)
- Work on `develop` branch, merge to `main` when complete

---

## Day 2 - January 7, 2026

**Status:** ✅ Complete | **Branch:** develop

### What I Did

#### 1. Terraform Configuration Files

Created core Terraform files:

- `providers.tf`: AWS provider ~> 5.0 with default tags
- `backend.tf`: S3 backend with DynamoDB locking
- `variables.tf`: Core variables (region, project, vpc_cidr)
- `outputs.tf`: Workspace and region outputs
- `main.tf`: Placeholder for future modules

#### 2. Workspaces

```bash
terraform workspace new qa
terraform workspace new prod
terraform workspace select qa  # Default working environment
```

**Strategy:** qa for development, prod for final deployment

#### 3. Backend Validation

- Ran `terraform init` → Successfully connected to S3 backend
- Created test `null_resource` to force state creation
- Verified state files in S3: `env:/qa/terraform.tfstate` and `env:/prod/terraform.tfstate`
- Confirmed workspace isolation (separate states)
- Destroyed test resources after validation

#### 4. Git Workflow Fix

- **Issue:** `.terraform.lock.hcl` was in `.gitignore`
- **Fix:** Removed from `.gitignore`, added to git
- **Why:** Lock file ensures provider version consistency (like package-lock.json)

### Key Learnings

**State Path Structure:**

```
Configured key: movie-analyst/terraform.tfstate
Workspace prefix: env:/{workspace}/
Actual path: env:/qa/movie-analyst/terraform.tfstate
```

Terraform combines workspace prefix with configured key automatically.

**Provider Lock File:**
Must be versioned to ensure team uses same provider versions. Contains checksums for security.

**Backend Validation:**
State file only created after first `terraform apply`, not during `terraform init`.

### Challenges

1. **State path confusion:** Expected state at one path, found at another
   - Solution: Learned how workspace prefixing works
2. **Lock file versioning:** Initially ignored lock file
   - Solution: Researched best practices, corrected .gitignore

### Files Created

```
terraform/providers.tf
terraform/backend.tf
terraform/variables.tf
terraform/outputs.tf
terraform/main.tf
terraform/.terraform.lock.hcl
```

### Next Steps

- Day 3-4: Networking module (VPC, subnets, IGW, NAT, route tables)
- Day 5: Security groups module
- Define CIDR blocks for public/private subnets

---

## Day 3 - [Date]

**Time:** X hours | **Status:** In Progress

[To be filled...]

---

## Notes for Studying

### Commands I Use Often

```bash
# Workspace management
terraform workspace list
terraform workspace select qa
terraform workspace show

# Validation
terraform init
terraform validate
terraform plan
terraform apply
terraform destroy

# State management
terraform state list
terraform state show <resource>

# S3 backend verification
aws s3 ls s3://<bucket>/ --recursive
```

### What to Remember for Presentation

**Day 1-2 Focus:**

- Why remote state? (Team collaboration, locking, versioning)
- Why workspaces? (Same code, isolated environments, cost-effective)
- Why lock file versioned? (Provider version consistency)
- State path structure with workspaces

**Cost Considerations:**

- Most services in free tier
- NAT Gateway is only significant cost (~$32/month)
- Strategy: Destroy when not working to minimize cost

---
