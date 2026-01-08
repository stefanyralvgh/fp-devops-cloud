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

## Day 3 - January 8, 2026

**Status:** ✅ Complete | **Branch:** develop

---

### What I Did

#### 1. Created Networking Module Structure

```bash
terraform/modules/networking/
├── main.tf       # All networking resources
├── variables.tf  # Module inputs
└── outputs.tf    # Module outputs (VPC ID, subnet IDs, etc.)
```

#### 2. Implemented Networking Resources

**Resources Created (22 total):**

- 1 VPC (10.0.0.0/16)
- 1 Internet Gateway
- 6 Subnets (2 public, 2 private backend, 2 private database)
- 1 Elastic IP (for NAT)
- 1 NAT Gateway
- 3 Route Tables (public, private, database)
- 3 Routes (public→IGW, private→NAT, database→NAT)
- 6 Route Table Associations

**CIDR Allocation:**

```
VPC:       10.0.0.0/16

Public:    10.0.1.0/24 (AZ-A), 10.0.2.0/24 (AZ-B)
Private:   10.0.11.0/24 (AZ-A), 10.0.12.0/24 (AZ-B)
Database:  10.0.21.0/24 (AZ-A), 10.0.22.0/24 (AZ-B)
```

#### 3. Module Integration

- Called networking module from root `main.tf`
- Added networking variables to root `variables.tf`
- Added networking outputs to root `outputs.tf`
- Configured workspace-aware environment tagging

#### 4. Deployment

```bash
terraform init       # Installed networking module
terraform fmt        # Formatted all .tf files
terraform validate   # Validated configuration
terraform plan       # Reviewed 22 resources to create
terraform apply      # Successfully deployed infrastructure
```

**Result:** All 22 networking resources created successfully in AWS ✅

---

### Key Learnings (Concepts I Struggled With)

#### 1. VPC Hierarchy

**What I learned:**

```
Region (us-east-1)
└── VPC (regional resource)
    └── Availability Zones (us-east-1a, us-east-1b)
        └── Subnets (AZ-specific)
            └── EC2 Instances (subnet-specific)
```

**Mental model:** Region = city, AZ = neighborhood, VPC = your building, Subnets = floors

---

#### 2. CIDR Blocks and IP Addressing

**Confusion:** What do 10.0.0.0/16 and 10.0.1.0/24 actually mean?

**What I learned:**

- VPC CIDR (10.0.0.0/16) = total address space (like building capacity)
- Subnet CIDR (10.0.1.0/24) = address space per floor
- Instance private IP (10.0.1.50) = specific office number

**Why spacing matters (1-2, 11-12, 21-22):**

- Creates logical separation
- Leaves room for future growth
- Example: Can add 10.0.3.0, 10.0.4.0 later for more public subnets

**Formula I now understand:**

- /16 = 65,536 IPs
- /24 = 256 IPs
- Smaller number after / = MORE IPs available

---

#### 3. Public vs Private Subnets

**What makes a subnet public:**

1. Route table with route to Internet Gateway (0.0.0.0/0 → IGW)
2. `map_public_ip_on_launch = true` (auto-assigns public IPs)

**What makes a subnet private:**

1. Route table with route to NAT Gateway (0.0.0.0/0 → NAT)
2. `map_public_ip_on_launch = false` (no public IPs)

**Key insight:** It's not the subnet itself, it's the route table association that determines public/private.

---

#### 4. NAT Gateway - The Hardest Concept

**Initial confusion:** What is NAT Gateway and why does it cost money?

**What I learned:**

**Purpose:** Allows private subnet resources to access internet (outbound only) without being accessible FROM internet (inbound blocked).

**Real-world example:**

```
Backend needs to run: npm install express

Without NAT:
Backend (10.0.11.5) → "I need npmjs.com" → Route table: "No route" → ❌ Fails

With NAT:
Backend (10.0.11.5) → "I need npmjs.com"
  → Route table: "0.0.0.0/0 → NAT Gateway"
  → NAT Gateway: "OK, I'll request it for you"
  → NAT → Internet Gateway → npmjs.com → Download
  → NAT returns package to Backend → ✅ Success
```

**Mental model:** NAT = receptionist who makes calls for employees but doesn't transfer incoming calls from strangers.

**Why it costs money:**

- It's a managed AWS service (they maintain it)
- Hourly: $0.045/hour (~$32/month if left on)
- Data transfer: $0.045/GB

**Cost mitigation:** terraform destroy after each session for this particular project to avoid high costs (~$5/month vs $32/month)

---

#### 5. Route Tables and 0.0.0.0/0

**Initial confusion:** What does `destination_cidr_block = "0.0.0.0/0"` mean?

**What I learned:**

- 0.0.0.0/0 = "everything on the internet" = "any destination outside our VPC"
- It's the default route (like "for everything else, go here")

**Route table as GPS:**

Public Route Table:

```
Destination: 10.0.0.0/16  → Target: local (stay in VPC)
Destination: 0.0.0.0/0    → Target: IGW (go to internet)
```

Translation: "If going to 10.0.x.x, stay inside. For anything else, exit via front door (IGW)."

Private Route Table:

```
Destination: 10.0.0.0/16  → Target: local
Destination: 0.0.0.0/0    → Target: NAT Gateway
```

Translation: "Stay inside for 10.0.x.x. For internet, ask receptionist (NAT) to make the call."

**Key insight:** 0.0.0.0/0 primarily applies to outbound traffic (from inside VPC to internet).

---

#### 6. Terraform count and Resource Creation

**Confusion:** Why `count = length(var.public_subnet_cidrs)`?

**What I learned:**

```hcl
var.public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]  # 2 items

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)  # count = 2
  cidr_block = var.public_subnet_cidrs[count.index]  # [0], [1]
}

Result: 2 subnets created
```

**Why this pattern:** Allows dynamic subnet creation. Change list to 4 CIDRs → automatically creates 4 subnets.

---

#### 7. DNS in VPC

**Question I had:** What exactly is DNS and why enable it in VPC?

**What I learned:**

- DNS = phone book (translates names to IPs)
- `enable_dns_support = true` → EC2 instances can resolve domain names
- `enable_dns_hostnames = true` → EC2 instances get DNS names (not just IPs)

**Example:**

```
Without DNS hostnames:
Access RDS at: my-database.abc123.us-east-1.rds.amazonaws.com ❌ Fails

With DNS hostnames:
Access RDS at: my-database.abc123.us-east-1.rds.amazonaws.com ✅ Works
```

---

#### 8. Tagging Strategy

**What I learned:**

**Required tags (via provider default_tags):**

- Project: movie-analyst
- ManagedBy: terraform
- Environment: qa (dynamic from workspace)

**Optional tags (resource-specific):**

- Type: Public/Private
- Tier: Web/Application/Database

**Why Tier = "Application" not "Backend":**

- "Application" is AWS standard terminology
- "Backend" is informal (works but not standard)
- Tags don't affect functionality (just organization)

---

#### 9. Module Variables (Root vs Module)

**Confusion:** Why define variables in both places?

**What I learned:**

```
Root variables (terraform/variables.tf):
- Entry point for user
- Provides defaults for this specific project

Main.tf passes values:
- Acts as bridge between root and module

Module variables (modules/networking/variables.tf):
- Defines what inputs module accepts
- Makes module reusable in other projects
```

**Why not duplication:**

- Module must be self-contained (someone else could use it standalone)
- Root provides project-specific customization

---

### Challenges and Solutions

#### Challenge 1: Understanding NAT Gateway Purpose

**Problem:** Couldn't understand why private subnets need internet access if they're "private"

**Solution:** Realized "private" means:

- Not accessible FROM internet (inbound blocked) ✅
- Still needs to ACCESS internet (outbound for updates) ✅

**Real need:** Backend runs `npm install` which downloads from npmjs.com

---

#### Challenge 2: NAT Gateway Cost Concern

**Problem:** NAT Gateway costs $32/month, project budget is $0

**Solution:**

- Use single NAT instead of dual ($32 vs $64)
- Destroy infrastructure daily ($5/month vs $32/month)
- Document cost justification for evaluator
- Acceptable risk for QA environment

---

#### Challenge 3: CIDR Block Confusion

**Problem:** Didn't understand what 10.0.1.0/24 means or how to avoid overlap

**Solution:**

- Learned CIDR notation (/16 = 65K IPs, /24 = 256 IPs)
- Used spacing pattern (1-2, 11-12, 21-22) for logical separation
- Verified no overlap with mental calculation

---

#### Challenge 4: Route Table Logic

**Problem:** Confused about when to use IGW vs NAT

**Solution:** Mental model:

- Public subnet → needs two-way internet → IGW
- Private subnet → needs one-way internet → NAT
- Route table association determines subnet type

---

### Commands Used

```bash
# Module creation
mkdir -p terraform/modules/networking
touch terraform/modules/networking/{main,variables,outputs}.tf

# Terraform workflow
terraform init          # Install module
terraform fmt -recursive # Format all files
terraform validate      # Check syntax
terraform plan          # Preview changes (22 to add)
terraform apply         # Deploy (took ~8 minutes)

# Verification
terraform state list    # List all 22 resources
terraform output        # View VPC ID, subnet IDs, NAT IP

# Cost management
terraform destroy       # Clean up to stop charges
```

---

### Files Created/Modified

**Created:**

```
terraform/modules/networking/main.tf       # All 22 networking resources
terraform/modules/networking/variables.tf  # Module inputs
terraform/modules/networking/outputs.tf    # Module outputs
```

**Modified:**

```
terraform/main.tf          # Added module "networking" call
terraform/variables.tf     # Added networking variables
terraform/outputs.tf       # Added networking outputs
docs/decisiones-tecnicas.md # Added Day 3 networking decisions
docs/DAILY_LOG.md          # This document
```

---

### Infrastructure Created

**22 AWS Resources:**

1. VPC (movie-analyst-qa-vpc)
2. Internet Gateway
   3-4. Public subnets (us-east-1a, us-east-1b)
   5-6. Private subnets - backend (us-east-1a, us-east-1b)
   7-8. Private subnets - database (us-east-1a, us-east-1b)
3. Elastic IP (for NAT)
4. NAT Gateway (in us-east-1a public subnet)
5. Public route table
6. Public route (0.0.0.0/0 → IGW)
   13-14. Public RT associations (2 subnets)
7. Private route table
8. Private route (0.0.0.0/0 → NAT)
   17-18. Private RT associations (2 subnets)
9. Database route table
10. Database route (0.0.0.0/0 → NAT)
    21-22. Database RT associations (2 subnets)

**Cost Impact:**

- Started: NAT Gateway charging $0.045/hour
- Duration: ~4 hours of work
- Action: Destroyed at end of day to stop charges

---

### Key Decisions Made

1. **Single NAT Gateway:** Cost optimization ($32→$5/month with destroy strategy)
2. **Three-tier subnets:** Public, Private (backend), Private (database) for security
3. **CIDR spacing:** 1-2, 11-12, 21-22 for logical separation and future growth
4. **Separate route tables:** Three RTs for clear isolation and future flexibility
5. **Two AZs:** Redundancy for HA (RDS requirement)

---

### Next Steps (Day 4)

**Security Groups Module:**

- [ ] Create `modules/security/` structure
- [ ] Define SG for Bastion (SSH from my IP only)
- [ ] Define SG for Frontend (HTTP/HTTPS + SSH from Bastion)
- [ ] Define SG for Backend (traffic from ALB + SSH from Bastion)
- [ ] Define SG for RDS (MySQL from Backend only)
- [ ] Define SG for ALB (HTTP/HTTPS from internet)

**Estimated time:** 2-3 hours

---

### Study Notes for Presentation

**Concepts to remember:**

- Why remote state? (Team collaboration, locking, versioning)
- Why workspaces? (Same code, isolated environments, cost-effective)
- Why lock file versioned? (Provider version consistency)
- State path structure with workspaces

- NAT Gateway = outbound only (unidirectional)
- 0.0.0.0/0 = default route to internet
- Public subnet = has IGW route
- Private subnet = has NAT route
- CIDR spacing = logical organization
- Route table association = what makes subnet public/private

**Cost justification:**

- Single NAT: $32/month vs $64/month (50% savings)
- Daily destroy: $5/month vs $32/month (84% savings)
- Trade-off: No HA across AZs (acceptable for QA)

**Questions evaluator might ask:**

1. "Why single NAT instead of dual?" → Cost optimization, acceptable risk for QA
2. "Why three route tables?" → Logical isolation, future flexibility
3. "Why these CIDR blocks?" → Standard private range, logical spacing
4. "How do private subnets get internet?" → NAT Gateway (outbound only)

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

---
