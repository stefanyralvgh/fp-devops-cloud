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

## Day 5 - January 9, 2026

**Status:** ✅ Complete | **Branch:** develop

### What I Did

#### 1. Security Groups Module Structure

Created security module with comprehensive security controls:

```bash
terraform/modules/security/
├── main.tf       # 5 Security Groups (Bastion, ALB, Frontend, Backend, RDS)
├── variables.tf  # Module inputs (vpc_id, environment, my_ip, vpc_cidr)
└── outputs.tf    # SG IDs for reference by other modules
```

#### 2. Security Groups Created

**5 Security Groups implemented:**

1. **Bastion SG:** SSH access only from my IP (190.158.28.120/32)
2. **ALB SG:** HTTP/HTTPS from internet (0.0.0.0/0)
3. **Frontend SG:** HTTP from ALB, SSH from Bastion
4. **Backend SG:** Port 3000 from ALB, SSH from Bastion
5. **RDS SG:** MySQL (3306) from Backend only

#### 3. Module Integration

- Integrated security module into root `main.tf`
- Referenced networking outputs (vpc_id, vpc_cidr)
- Used workspace variable for environment tagging
- Exposed all SG IDs via outputs for future module consumption

#### 4. Deployment

```bash
terraform init       # Installed security module
terraform fmt        # Formatted all files
terraform validate   # Validated configuration
terraform plan       # Reviewed 5 resources to create
terraform apply      # Successfully deployed all SGs
```

**Result:** All 5 Security Groups created successfully in AWS ✅

---

### Key Learnings (Security Concepts)

#### 1. Security Groups vs Network ACLs

**What I learned:**

- **Security Groups:** Stateful, resource-level, allow-only rules
- **Network ACLs:** Stateless, subnet-level, allow/deny rules
- **This project uses:** Only Security Groups (simpler, sufficient)

**Mental model:** SG = bodyguard for each person (EC2), NACL = checkpoint at building entrance (subnet)

---

#### 2. Stateful Nature of Security Groups

**Initial confusion:** Why no explicit outbound rule for SSH responses?

**What I learned:**

- **Stateful = automatic return traffic**
- Example: SSH connection initiates on port 22 → response automatically allowed back
- Only need to define the initial connection direction
- Egress 0.0.0.0/0 allows instances to initiate outbound connections

**Key insight:** If you allow inbound SSH, responses go out automatically. If you allow outbound HTTPS, responses come in automatically.

---

#### 3. CIDR Blocks vs Security Group References

**Confusion:** When to use `cidr_blocks` vs `security_groups` in rules?

**What I learned:**

| Use Case                 | Use                                           | Example                          |
| ------------------------ | --------------------------------------------- | -------------------------------- |
| **Internet traffic**     | `cidr_blocks = ["0.0.0.0/0"]`                 | ALB accepting HTTP from anywhere |
| **My computer**          | `cidr_blocks = ["190.158.28.120/32"]`         | SSH to Bastion from my IP        |
| **AWS resource traffic** | `security_groups = [aws_security_group.x.id]` | Backend accepting from ALB       |

**Why use security_groups reference:**

- Don't need to know IP addresses of ALB/instances
- Automatically works even if IPs change
- More maintainable (one place to update)
- AWS resolves this internally

**Real example:**

```hcl
# ❌ Bad: What if ALB IP changes?
cidr_blocks = ["10.0.1.50/32"]

# ✅ Good: References SG, works with any IP
security_groups = [aws_security_group.alb.id]
```

---

#### 4. Understanding Port Specifications

**Confusion:** What do `from_port` and `to_port` actually mean?

**What I learned:**

- **from_port / to_port:** Defines the port RANGE on the destination
- **NOT:** client port → server port
- **Port 22 (SSH):** Both from/to = 22 (single port)
- **Port range example:** from_port = 8000, to_port = 8999 (allow any port in range)

**Common pattern:**

```hcl
from_port = 3000
to_port   = 3000
# Means: "Allow access TO port 3000 on the destination"
```

**Why port ranges exist:**

- Some apps use multiple ports
- Example: FTP uses 20-21, passive mode uses 1024-65535
- Our app: Single port (3000) so from = to

---

#### 5. Protocol Field

**Confusion:** Why always `protocol = "tcp"`?

**What I learned:**

**Common protocols:**

- `"tcp"`: HTTP, HTTPS, SSH, MySQL (most application traffic)
- `"udp"`: DNS, video streaming, VoIP
- `"icmp"`: Ping, network diagnostics
- `"-1"`: All protocols (used in egress rules)

**Our security groups:**

- SSH (22): TCP
- HTTP (80): TCP
- HTTPS (443): TCP
- MySQL (3306): TCP
- Node.js (3000): TCP
- Egress (all): -1 (all protocols)

**Why TCP dominates:**

- Reliable connection (handshake, acknowledgments)
- Required for HTTP/HTTPS/SSH/databases
- Industry standard for web applications

---

#### 6. Security Group Scope

**Questions I had:**

- Where does a Security Group "live"?
- Can I use an SG across VPCs?
- Is SG attached to subnet or resource?

**What I learned:**

```
AWS Account
└── Region (us-east-1)
    └── VPC (10.0.0.0/16)
        ├── Security Group 1 ← Lives at VPC level
        ├── Security Group 2
        └── Subnets
            └── EC2 instances ← SG attached here
```

**Key facts:**

- SG belongs to a VPC (can't be used in other VPCs)
- SG is attached to ENI (Elastic Network Interface) of resource
- One resource can have multiple SGs (combined rules)
- SG rules apply regardless of which subnet resource is in

**Mental model:** VPC = building ownership, SG = employee badge (works in any floor)

---

#### 7. Implicit Deny

**Confusion:** Why no explicit "deny" rules?

**What I learned:**

**Security Group logic:**

- Default: Deny everything
- Rules: Add specific allows
- No traffic passes unless explicitly allowed

**Example:**

```hcl
# This SG ONLY allows SSH from my IP
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["190.158.28.120/32"]
}

# Implicit denies:
# ❌ Port 80 from anywhere
# ❌ Port 22 from other IPs
# ❌ Any other port
```

**Why no deny rules:**

- Simpler mental model (whitelist only)
- Less risk of misconfiguration
- Default-deny is more secure
- If you need deny: use Network ACLs instead

---

#### 8. Building Analogy - Final Version

**Confusion:** How do NAT, SGs, ALB, and Bastion all fit together?

**Complete building model:**

| AWS Resource         | Building Analogy            | Function                                 |
| -------------------- | --------------------------- | ---------------------------------------- |
| **VPC**              | The building                | Your private space                       |
| **Subnets**          | Floors                      | Public (lobby) vs Private (offices)      |
| **Route Tables**     | Building directory          | "To go outside, use front door"          |
| **Internet Gateway** | Front door                  | Exit to street (internet)                |
| **NAT Gateway**      | Receptionist with phone     | Makes outbound calls for private offices |
| **Security Groups**  | Badge scanners at each door | Who can enter each specific room         |
| **ALB**              | Reception desk              | Directs visitors to correct office       |
| **Bastion Host**     | Maintenance entrance        | IT staff access point                    |

**Traffic flow example (User → Backend):**

1. User enters building (IGW)
2. Reception desk checks badge (ALB SG: allows HTTP)
3. Receptionist directs to Backend floor (ALB routes)
4. Backend office door scans badge (Backend SG: allows from ALB)
5. Backend needs to download package:
   - Walks to receptionist (NAT)
   - Receptionist makes call (NAT to internet)
   - Receptionist brings package back (NAT to Backend)

**Key insight:** Each component has ONE job:

- IGW: Building entrance/exit
- NAT: Outbound proxy for private resources
- SG: Door access control
- ALB: Traffic distribution
- Bastion: Admin access point

---

### Challenges and Solutions

#### Challenge 1: Understanding Security Group References

**Problem:** Confused about when to use IP vs SG reference in rules

**Solution:**

- **External traffic:** Use CIDR (internet, my IP)
- **Internal AWS traffic:** Use SG reference (ALB → Backend)
- **Why:** SG references work even when IPs change

---

#### Challenge 2: Workspace vs Environment Directory Structure

**Problem:** Had `environments/qa/` and `environments/prod/` directories but also using workspaces

**Decision:** Keep main.tf in root, use workspaces for environment switching

**Justification:**

- DRY principle: Single codebase for both environments
- Workspaces designed for this exact use case
- Less maintenance: Changes apply to both environments
- Simpler for small projects where QA/PROD are nearly identical

**When to use separate directories:**

- Drastically different configurations per environment
- Different module versions per environment
- Separate state management systems

---

#### Challenge 3: Output Strategy

**Problem:** Which outputs to expose from security module?

**Solution:** Export all 5 SG IDs for future module consumption

**Why:**

- Compute module will need: bastion_sg_id, frontend_sg_id, backend_sg_id
- Database module will need: rds_sg_id
- Load balancer module will need: alb_sg_id
- Better to export now than refactor later

---

### Commands Used

```bash
# Module creation
mkdir -p terraform/modules/security
touch terraform/modules/security/{main,variables,outputs}.tf

# Terraform workflow
terraform init          # Install security module
terraform fmt -recursive # Format all files
terraform validate      # Check syntax
terraform plan          # Preview changes (5 to add)
terraform apply         # Deploy (took ~2 minutes)

# Verification
terraform state list    # List all resources
terraform output        # View module outputs
aws ec2 describe-security-groups --query 'SecurityGroups[?contains(GroupName, `qa-`)].GroupName' # Verify in AWS
```

---

### Files Created/Modified

**Created:**

```
terraform/modules/security/main.tf       # 5 Security Groups
terraform/modules/security/variables.tf  # Module inputs
terraform/modules/security/outputs.tf    # Module outputs (5 SG IDs)
```

**Modified:**

```
terraform/main.tf          # Added security module call
terraform/outputs.tf       # Added security outputs (optional)
docs/decisiones-tecnicas.md # (Will update separately)
docs/DAILY_LOG.md          # This document
```

---

### Infrastructure Created

**5 AWS Security Groups:**

1. **qa-bastion-sg**

   - Ingress: SSH (22) from 190.158.28.120/32
   - Egress: All traffic

2. **qa-alb-sg**

   - Ingress: HTTP (80), HTTPS (443) from 0.0.0.0/0
   - Egress: All traffic

3. **qa-frontend-sg**

   - Ingress: HTTP (80) from ALB SG, SSH (22) from Bastion SG
   - Egress: All traffic

4. **qa-backend-sg**

   - Ingress: Port 3000 from ALB SG, SSH (22) from Bastion SG
   - Egress: All traffic

5. **qa-rds-sg**
   - Ingress: MySQL (3306) from Backend SG
   - Egress: All traffic

**Cost Impact:** Security Groups are free (no additional cost)

---

### Key Decisions Made

1. **Stateful Security Groups only:** No Network ACLs (simpler, sufficient)
2. **Security Group references over IPs:** More maintainable for internal traffic
3. **Egress allow-all:** Standard practice (restrictive egress rarely needed)
4. **Single IP for Bastion access:** My public IP only (190.158.28.120/32)
5. **Port 3000 for Backend:** Based on Node.js app configuration
6. **Workspace-based environment:** Keep main.tf in root, not in environment directories

---

### Next Steps (Day 6-7)

**Compute Module - Bastion Host:**

- [ ] Create `modules/compute/` structure
- [ ] Generate SSH key pair (.pem file)
- [ ] Create Bastion Host (t2.micro, public subnet, Elastic IP)
- [ ] Test SSH connection from Windows
- [ ] Install Ansible on Bastion

**Estimated time:** 2-3 hours

---

### Study Notes for Presentation

**Security Group concepts to remember:**

- Stateful = return traffic automatic
- Default deny, explicit allow only
- VPC-scoped, resource-attached
- CIDR for external, SG reference for internal
- Protocol: TCP for most app traffic, -1 for all

**Questions evaluator might ask:**

1. "Why no deny rules in SGs?" → Default deny, whitelist approach more secure
2. "Why reference ALB SG instead of CIDR?" → IPs change, SG reference auto-updates
3. "What's the difference between SG and NACL?" → Stateful vs stateless, resource vs subnet level
4. "Why allow all egress?" → Standard practice, restrictive egress rarely needed, enables updates/patches
5. "How do workspaces relate to security?" → Same SG rules, different names (qa-_ vs prod-_)

**Architecture understanding:**

- Traffic flow: Internet → IGW → ALB → Backend → RDS
- Security layers: SG at each hop (defense in depth)
- Bastion pattern: Jump host for SSH access to private resources
- Least privilege: Only allow minimum necessary access

---
