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

## Day 6 - January 10, 2026

**Status:** ✅ Complete | **Branch:** develop

### What I Did

#### 1. SSH Key Pair Generation

**Created RSA key pair for Bastion access:**

```bash
ssh-keygen -t rsa -b 4096 -f movie-analyst-bastion-key -C "bastion@movie-analyst"
```

**Files generated:**

- `movie-analyst-bastion-key` (private key - stored locally, not in git)
- `movie-analyst-bastion-key.pub` (public key - uploaded to AWS)

**Security measures:**

- Added `keys/` directory to `.gitignore`
- Set restrictive permissions on private key (400)
- Only public key stored in Terraform code

---

#### 2. Compute Module Structure

Created compute module for EC2 instance management:

```bash
terraform/modules/compute/
├── main.tf       # Bastion instance, EIP, AMI data source
├── variables.tf  # Module inputs
└── outputs.tf    # Bastion IPs and connection info
```

---

#### 3. Bastion Host Configuration

**Instance specifications:**

- **AMI:** Amazon Linux 2 (latest, auto-discovered via data source)
- **Instance type:** t2.micro (free tier eligible)
- **Subnet:** First public subnet (us-east-1a)
- **Security Group:** bastion-sg (SSH from my IP only)
- **Storage:** 8GB GP3 encrypted root volume
- **Monitoring:** Enabled (CloudWatch basic monitoring)

**Key features implemented:**

**User Data script:**

```bash
#!/bin/bash
yum update -y
yum install -y git wget curl vim
timedatectl set-timezone America/Bogota
# Custom MOTD banner
```

**Elastic IP assignment:**

- Persistent public IP: `54.144.192.77`
- Survives instance stop/start cycles
- Enables consistent firewall whitelisting

---

#### 4. AWS Key Pair Resource

Created Terraform resource to manage SSH key in AWS:

```hcl
resource "aws_key_pair" "bastion" {
  key_name   = "${terraform.workspace}-bastion-key"
  public_key = file("${path.module}/keys/movie-analyst-bastion-key.pub")
}
```

**Why separate resource:**

- Reusable across multiple instances
- Centralized key management
- Easy rotation (update file, apply)

---

#### 5. Module Integration

**Updated root main.tf:**

- Called compute module with required parameters
- Passed networking outputs (VPC ID, subnet IDs)
- Passed security outputs (bastion SG ID)
- Referenced key pair resource

**Added helpful outputs:**

```hcl
output "bastion_ssh_command" {
  value = "ssh -i keys/movie-analyst-bastion-key ec2-user@${module.compute.bastion_public_ip}"
}
```

---

#### 6. Deployment

```bash
terraform init       # Installed compute module
terraform validate   # Validated configuration
terraform plan       # Reviewed 3 new resources
terraform apply      # Created key pair, instance, EIP
```

**Resources created:**

1. `aws_key_pair.bastion` (qa-bastion-key)
2. `aws_instance.bastion` (qa-bastion-host)
3. `aws_eip.bastion` (54.144.192.77)

---

#### 7. SSH Connection from Windows

**Challenge encountered:** Windows file permissions too permissive for SSH

**Error:**

```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions for 'C:\Users\Stefany\.ssh\movie-analyst-bastion-key' are too open.
bad permissions
```

**Solution:** Used Git Bash instead of PowerShell

```bash
# Git Bash handles Linux-style permissions correctly
chmod 400 ~/.ssh/movie-analyst-bastion-key
ssh -i ~/.ssh/movie-analyst-bastion-key ec2-user@54.144.192.77
```

**Connection successful:**

```
   =====================================
   Movie Analyst Bastion Host
   Environment: qa
   =====================================
[ec2-user@ip-10-0-1-25 ~]$
```

**Hostname explanation:**

- `ec2-user`: Default user for Amazon Linux 2
- `ip-10-0-1-25`: Hostname based on private IP (10.0.1.25)
- Standard AWS behavior, no custom hostname needed

---

#### 8. Ansible Installation on Bastion

**Installed Ansible using Amazon Linux Extras repository:**

```bash
sudo amazon-linux-extras install ansible2 -y
```

**Verification:**

```bash
ansible --version
# ansible 2.9.23
# config file = /etc/ansible/ansible.cfg
# python version = 2.7.18
```

**Additional tools installed:**

```bash
# Python 3 and pip
sudo yum install python3-pip -y

# Boto3 (AWS SDK for Python - needed for Ansible AWS modules)
pip3 install boto3 --user

# AWS CLI configuration (for Ansible dynamic inventory)
aws configure
# Configured with same credentials as local machine
```

---

### Key Learnings (Bastion & SSH Concepts)

#### 1. Bastion Host Pattern

**What I learned:**

**Purpose:** Single, hardened entry point for SSH access to private infrastructure

**Why needed:**

- Backend instances are in private subnets (no public IPs)
- Direct SSH from internet would be security risk
- Bastion acts as "jump server" or "jump box"

**Security benefits:**

- Reduces attack surface (one SSH endpoint vs many)
- Centralized access logging
- Easier to audit (who accessed what, when)
- Can implement additional controls (MFA, session recording)

**Mental model (building analogy):**

- **Without Bastion:** Every office has external door (security nightmare)
- **With Bastion:** One secure maintenance entrance, guard verifies ID, escorts to office

---

#### 2. Elastic IP vs Regular Public IP

**Confusion:** Why do we need Elastic IP when instance already gets public IP?

**What I learned:**

| Regular Public IP       | Elastic IP                 |
| ----------------------- | -------------------------- |
| Random, AWS-assigned    | Fixed, you choose          |
| Changes on stop/start   | Persists across stop/start |
| Free                    | Free while attached        |
| Released on termination | Persists until you delete  |

**Real-world scenario:**

```
Day 1: Create Bastion → Gets IP 54.144.192.77
Day 2: Stop instance to save money
Day 3: Start instance → Gets NEW IP 52.201.45.123
Problem: Firewall rules, SSH configs, scripts all broken

With Elastic IP:
Day 1: Create Bastion + EIP → 54.144.192.77
Day 2: Stop instance
Day 3: Start instance → SAME IP 54.144.192.77
Solution: Everything still works
```

**Cost consideration:**

- Elastic IP is FREE while attached to running instance
- Costs $0.005/hour (~$3.60/month) if NOT attached
- **Takeaway:** Always delete unused Elastic IPs

---

#### 3. AMI Data Source

**Confusion:** Why not hardcode AMI ID like `ami-0c55b159cbfafe1f0`?

**What I learned:**

**Problem with hardcoded AMI IDs:**

- AMI IDs differ by region (us-east-1 vs us-west-2)
- AWS updates AMIs monthly (security patches)
- Hardcoded ID might not exist in 6 months

**Data source solution:**

```hcl
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

**What this does:**

- Queries AWS API for latest Amazon Linux 2 AMI
- Always uses most recent version (security patches included)
- Works in any region automatically
- Pattern: `amzn2-ami-hvm-*` = "Amazon Linux 2, HVM virtualization, any version, x86_64, GP2 storage"

**Mental model:** Like using `apt-get install nginx` (latest version) vs downloading `nginx-1.18.0.deb` (hardcoded version)

---

#### 4. User Data Script

**What I learned:**

**Execution:**

- Runs ONCE on first boot only
- Runs as root (no need for sudo)
- Executes before instance is fully operational

**Common uses:**

- Install packages
- Configure services
- Set hostname, timezone
- Pull application code
- Join domain/cluster

**Important limitations:**

- Runs only on FIRST boot (not on restart)
- Limited to 16KB size
- No easy way to see execution logs (must SSH and check `/var/log/cloud-init-output.log`)
- Errors don't fail instance creation (instance starts even if script fails)

**For this project:**

```bash
# Update system (security patches)
yum update -y

# Install dev tools
yum install -y git wget curl vim

# Set timezone
timedatectl set-timezone America/Bogota

# Custom login banner (MOTD = Message of the Day)
echo "Movie Analyst Bastion Host" > /etc/motd
```

**Alternative (for complex setup):** Use Configuration Management (Ansible, Chef, Puppet) after instance creation

---

#### 5. SSH Key Management

**Confusion:** How do SSH keys actually work?

**What I learned:**

**Key pair generation:**

```
ssh-keygen creates:
1. Private key (movie-analyst-bastion-key)
   - Keep secret
   - Never share
   - Never commit to git

2. Public key (movie-analyst-bastion-key.pub)
   - Can share freely
   - Upload to AWS
   - Copy to servers
```

**Authentication flow:**

```
1. AWS stores public key on Bastion
2. You connect with private key
3. Bastion says: "Prove you have the private key"
4. Your SSH client signs a challenge with private key
5. Bastion verifies signature with public key
6. If valid → Access granted
```

**Mental model:**

- Public key = padlock (you can give to anyone)
- Private key = unique key that opens that padlock
- Server has padlock, only you have key

**Security best practices:**

- Private key permissions: 400 (read-only for owner)
- Never email private keys
- Use different keys for different environments
- Rotate keys periodically (every 90 days in production)

---

#### 6. Windows SSH Permissions Issue

**Problem encountered:**

Windows NTFS permissions don't map cleanly to Unix permissions (400, 600, etc.)

**SSH requirement:**

- Private key must be readable ONLY by owner
- No other users, no groups, no "Everyone"

**Why PowerShell struggled:**

- Windows has complex permission inheritance
- Multiple security principals (User, SYSTEM, Administrators)
- `icacls` commands didn't fully clean permissions

**Solution that worked:**

- Git Bash includes MinGW (minimal Unix environment)
- `chmod 400` works correctly in Git Bash
- Translates to appropriate Windows ACLs automatically

**Alternative solutions:**

1. **WSL (Windows Subsystem for Linux):** Full Linux environment
2. **PuTTY:** GUI client with its own key format (.ppk)
3. **ssh-keygen from PowerShell:** Creates key with correct permissions from start

**Lesson learned:** For DevOps work on Windows, Git Bash or WSL is essential

---

#### 7. EC2 Instance Naming

**Confusion:** Hostname is `ip-10-0-1-25` instead of "bastion-qa"

**What I learned:**

**AWS hostname behavior:**

- Default hostname = `ip-{private-ip-with-dashes}`
- Example: Private IP 10.0.1.25 → Hostname `ip-10-0-1-25`
- This is standard AWS behavior

**Tag vs Hostname:**

- **Name tag:** `qa-bastion-host` (shows in AWS Console)
- **OS hostname:** `ip-10-0-1-25` (shows in terminal)
- These are different things

**Do I need custom hostname?**

- **No, for this project:** Default is fine
- **Yes, for production:** Helps identify servers in logs

**How to customize (if wanted):**

```bash
sudo hostnamectl set-hostname bastion-qa.movie-analyst.local
```

**But:** Not necessary for learning project

---

### Challenges and Solutions

#### Challenge 1: SSH Private Key Permissions on Windows

**Problem:**

```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions too open
```

**Root cause:**

- Windows NTFS permissions don't map to Unix 400/600
- PowerShell `icacls` left extra principals with access
- SSH client (OpenSSH) enforces strict permission checks

**Attempted solutions:**

1. PowerShell `icacls` commands → Failed (permissions still too open)
2. Manual permission removal → Failed (inheritance issues)

**Working solution:**

- Used Git Bash (includes MinGW Unix environment)
- `chmod 400` works correctly in Git Bash
- Properly restricts file to owner-only read access

**Lesson learned:** Git Bash essential for SSH operations on Windows

---

#### Challenge 2: Understanding Bastion Purpose

**Initial confusion:** Why not just put backend instances in public subnets?

**What I learned:**

**Security implications:**

| Public Subnet                 | Private Subnet + Bastion    |
| ----------------------------- | --------------------------- |
| Every instance exposed        | Only Bastion exposed        |
| Attack surface = N instances  | Attack surface = 1 instance |
| Each instance needs hardening | Harden one Bastion          |
| Hard to audit access          | Centralized access point    |

**Real-world analogy:**

- **Public subnets for all:** Every employee has office with street entrance (chaos)
- **Private + Bastion:** One secured entrance, guard escorts visitors (organized)

**When Bastion NOT needed:**

- VPN connection to VPC
- AWS Systems Manager Session Manager (AWS-managed SSH)
- Small, low-security environments

**For this project:** Bastion is industry best practice

---

#### Challenge 3: First Time Using Data Sources

**Confusion:** What's the difference between `resource` and `data`?

**What I learned:**

```hcl
# RESOURCE: Terraform CREATES this
resource "aws_instance" "bastion" {
  ami = data.aws_ami.amazon_linux_2.id
  # Terraform creates the instance
}

# DATA SOURCE: Terraform QUERIES this (already exists)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  # Terraform just looks up the AMI ID
}
```

**Use cases for data sources:**

- Lookup existing VPCs
- Find latest AMI
- Get current AWS region
- Reference resources created outside Terraform

**Mental model:**

- Resource = Write operation (CREATE)
- Data source = Read operation (QUERY)

---

### Commands Used

```bash
# SSH key generation
ssh-keygen -t rsa -b 4096 -f ~/.ssh/movie-analyst-bastion-key -C "bastion@movie-analyst"

# Key permissions (Git Bash)
chmod 400 ~/.ssh/movie-analyst-bastion-key

# Terraform workflow
terraform init
terraform fmt -recursive
terraform validate
terraform plan       # Should show 3 new resources
terraform apply

# SSH connection
ssh -i ~/.ssh/movie-analyst-bastion-key ec2-user@54.144.192.77

# Ansible installation (on Bastion)
sudo amazon-linux-extras install ansible2 -y
ansible --version

# Additional tools (on Bastion)
sudo yum install python3-pip -y
pip3 install boto3 --user
aws configure
```

---

### Files Created/Modified

**Created:**

```
~/.ssh/movie-analyst-bastion-key      # Private key (local only)
~/.ssh/movie-analyst-bastion-key.pub  # Public key
terraform/keys/movie-analyst-bastion-key.pub  # Copy for Terraform
terraform/modules/compute/main.tf
terraform/modules/compute/variables.tf
terraform/modules/compute/outputs.tf
terraform/key_pair.tf                 # Key pair resource
```

**Modified:**

```
terraform/.gitignore              # Added keys/, *.pem
terraform/main.tf                 # Added compute module call
terraform/outputs.tf              # Added bastion outputs
```

---

### Infrastructure Created

**AWS Resources (3 new):**

1. **SSH Key Pair:** `qa-bastion-key`

   - Public key stored in AWS
   - Used for EC2 instance authentication

2. **EC2 Instance:** `qa-bastion-host`

   - AMI: Amazon Linux 2 (ami-xxxxxxxxx, auto-discovered)
   - Type: t2.micro
   - Subnet: qa-public-subnet-1 (10.0.1.0/24, us-east-1a)
   - Private IP: 10.0.1.25
   - Security Group: qa-bastion-sg
   - Root volume: 8GB GP3, encrypted
   - Monitoring: Enabled

3. **Elastic IP:** `qa-bastion-eip`
   - Public IP: 54.144.192.77
   - Associated with: qa-bastion-host
   - Persists across instance stop/start

**Software installed on Bastion:**

- Ansible 2.9.23
- Python 3 + pip
- Boto3 (AWS SDK)
- AWS CLI (configured)
- Git, wget, curl, vim

**Cost impact:**

- EC2 t2.micro: Free tier (750 hours/month)
- Elastic IP (attached): Free
- EBS 8GB: Free tier (30GB/month limit)
- Data transfer: Free tier (15GB/month)
- **Current additional cost: $0/month** (within free tier)

---

### Key Decisions Made

1. **Amazon Linux 2 over Ubuntu:** AWS-optimized, includes amazon-linux-extras, free licensing
2. **Elastic IP:** Persistent address for whitelisting and consistency
3. **t2.micro:** Free tier eligible, sufficient for jump host
4. **Single Bastion:** One per environment (not HA) - cost optimization
5. **Data source for AMI:** Always use latest, region-agnostic
6. **User data for basic setup:** Automated initial configuration
7. **Git Bash for SSH:** Windows permission handling issues

---

### Next Steps (Day 7)

**Backend EC2 Instances:**

- [ ] Create backend instances in private subnets
- [ ] Configure in both AZs (us-east-1a, us-east-1b)
- [ ] Verify internet access via NAT Gateway
- [ ] Test SSH access via Bastion (jump host)
- [ ] User data for Node.js app preparation

**Estimated time:** 2-3 hours

---

### Study Notes for Presentation

**Bastion concepts to remember:**

- Jump host pattern for private subnet access
- Elastic IP for persistent addressing
- Data sources vs resources in Terraform
- User data execution (first boot only)
- SSH key pair management and security

**Questions evaluator might ask:**

1. **"Why Bastion instead of VPN?"**
   → Simpler for small projects, no additional AWS costs, standard pattern, easier to demonstrate

2. **"What if Bastion goes down?"**
   → For QA: Acceptable risk, can recreate quickly. For Prod: Would implement HA (Auto Scaling Group with capacity 1, multi-AZ)

3. **"Why Elastic IP?"**
   → Persistent address survives stop/start, easier for firewall rules, no need to update configurations

4. **"How do you access backend from Bastion?"**
   → SSH tunneling/jump: `ssh -J bastion backend` or two-hop SSH

5. **"Why not hardcode AMI ID?"**
   → AMI IDs differ by region, AWS updates monthly, data source always gets latest

**Architecture understanding:**

- Bastion = only public SSH endpoint
- Private instances = SSH only from Bastion
- Defense in depth: SG + Network isolation
- Least privilege: Bastion can't access database directly

## Day 7 - January 11, 2026

**Status:** ✅ Complete | **Branch:** develop

### What I Did

#### 1. Backend Instances Configuration

Extended compute module to support backend application servers in private subnets:

```bash
terraform/modules/compute/
├── main.tf       # Added backend instances with IAM profile
├── variables.tf  # Added backend-specific variables
└── outputs.tf    # Added backend IPs and SSH commands
```

**Backend specifications:**

- **Count:** 2 instances
- **AMI:** Amazon Linux 2 (latest, shared data source with Bastion)
- **Instance type:** t2.micro (free tier eligible)
- **Subnets:** Private subnets (10.0.11.0/24, 10.0.12.0/24)
- **Distribution:** Round-robin across availability zones
- **Security Group:** backend-sg (port 3000 from ALB, SSH from Bastion)
- **Storage:** 8GB GP3 encrypted root volume
- **Monitoring:** Enabled (detailed CloudWatch metrics)

---

#### 2. IAM Role and Instance Profile

Created IAM infrastructure for backend instances to interact with AWS services:

**New file:** `terraform/iam.tf`

**Resources created:**

1. **IAM Role** (`qa-backend-role`): Allows EC2 to assume the role
2. **CloudWatch Policy:** Write logs and metrics
3. **SSM Parameter Store Policy:** Read application secrets
4. **Instance Profile:** Attaches role to EC2 instances

**Why this matters:**

- Backend can write application logs to CloudWatch
- Can read database credentials from Parameter Store (secure)
- No hardcoded credentials needed
- Follows AWS security best practices

---

#### 3. Multi-AZ Distribution Logic

Implemented automatic distribution of instances across availability zones:

```hcl
subnet_id = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
```

**How it works:**

- `count.index` = 0, 1, 2, 3...
- `%` = modulo operator (remainder of division)
- With 2 subnets:
  - Instance 0: 0 % 2 = 0 → subnet[0] (us-east-1a)
  - Instance 1: 1 % 2 = 1 → subnet[1] (us-east-1b)
  - Instance 2: 2 % 2 = 0 → subnet[0] (us-east-1a)

**Result:** Automatic high availability across AZs

---

#### 4. User Data for Backend Setup

Configured automated initial setup via user data:

```bash
#!/bin/bash
yum update -y
yum groupinstall -y "Development Tools"
yum install -y git wget curl vim
timedatectl set-timezone America/Bogota
mkdir -p /opt/movie-analyst
```

**Why Development Tools:**

- Node.js native modules require gcc, make, python
- Needed for compiling npm packages with C++ bindings
- Examples: bcrypt, node-sass, sqlite3

---

#### 5. SSH Jump Host Configuration

Configured SSH access through Bastion using ProxyJump:

```hcl
output "backend_ssh_commands" {
  value = [
    for ip in module.compute.backend_private_ips :
    "ssh -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${ip}"
  ]
}
```

**Access pattern:**

```bash
# Single command to jump through Bastion
ssh -J ec2-user@54.144.192.77 ec2-user@10.0.11.5

# Alternative: SSH Agent Forwarding
ssh -A ec2-user@54.144.192.77
ssh ec2-user@10.0.11.5
```

---

#### 6. Deployment and Verification

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan       # Reviewed 7 new resources
terraform apply      # Created IAM + 2 backend instances
```

**Resources created:**

1. `aws_iam_role.backend`
2. `aws_iam_role_policy.backend_cloudwatch`
3. `aws_iam_role_policy.backend_ssm`
4. `aws_iam_instance_profile.backend`
5. `aws_instance.backend[0]` (us-east-1a)
6. `aws_instance.backend[1]` (us-east-1b)

---

#### 7. NAT Gateway Verification

**Tested outbound internet connectivity from private subnets:**

Connected to backend instance via Bastion:

```bash
# DNS resolution test
nslookup google.com
# ✅ Success: 8.8.8.8 resolved

# HTTP connectivity test
curl -I https://www.google.com
# ✅ Success: HTTP 200 OK

# Verify public IP (should be NAT Gateway IP, not instance IP)
curl https://ifconfig.me
# ✅ Returns NAT Gateway Elastic IP (not backend private IP)
```

**Confirmation:** NAT Gateway correctly provides outbound internet access to private subnet instances

---

#### 8. IAM Role Verification

**Tested IAM instance profile from backend:**

```bash
# Check IAM metadata
curl http://169.254.169.254/latest/meta-data/iam/info
# ✅ Shows instance profile ARN

# Verify AWS API access
aws sts get-caller-identity
# ✅ Shows assumed role ARN: arn:aws:sts::...:assumed-role/qa-backend-role/i-xxx
```

**Confirmation:** Backend instances can authenticate to AWS services without credentials

---

### Key Learnings (Backend & Private Subnet Concepts)

#### 1. Private Subnets and Internet Access

**Initial confusion:** If instances are in private subnets with no public IPs, how do they access the internet?

**What I learned:**

**The NAT Gateway flow:**

```
Backend (10.0.11.5) wants npm install
  ↓
Route Table: "0.0.0.0/0 → NAT Gateway"
  ↓
NAT Gateway (in public subnet)
  ↓
Internet Gateway
  ↓
Internet (npmjs.com)
  ↓
Response follows same path back
```

**Key insight:** NAT is UNIDIRECTIONAL

- ✅ Outbound: Backend → Internet (initiated by backend)
- ❌ Inbound: Internet → Backend (blocked, no public IP)

**Mental model (building analogy):**

- Backend = Employee in office without windows
- NAT Gateway = Receptionist who makes calls for employees
- Employee can ask receptionist to call outside
- Outside callers CANNOT reach employee directly

---

#### 2. Count vs For_Each in Terraform

**Question:** Why use `count` instead of `for_each` for creating multiple instances?

**What I learned:**

**Count is appropriate when:**

- Number of resources is fixed (2 backends for QA, 2 for PROD)
- Resources are homogeneous (all identical configuration)
- Not frequently adding/removing resources

**For_each would be better when:**

- Dynamic list of resources that changes frequently
- Need to identify resources by name instead of index
- Resources have unique configurations

**For this project:** Count is simpler and appropriate because:

- Fixed architecture (always 2 backends)
- Identical configuration for all backends
- Not scaling dynamically (would use Auto Scaling Group for that)

**Code pattern:**

```hcl
resource "aws_instance" "backend" {
  count = 2  # Creates backend[0] and backend[1]

  # Distribute across subnets
  subnet_id = var.private_subnet_ids[count.index % 2]
}
```

---

#### 3. IAM Roles vs IAM Users

**Confusion:** What's the difference between IAM Role and IAM User?

**What I learned:**

| IAM User                            | IAM Role                              |
| ----------------------------------- | ------------------------------------- |
| Permanent identity                  | Temporary identity                    |
| Long-term credentials (access keys) | Short-term credentials (auto-rotated) |
| For humans                          | For services (EC2, Lambda, etc.)      |
| You manage credentials              | AWS manages credentials               |

**Real-world scenario WITHOUT IAM Role:**

```bash
# Bad practice: Hardcoded credentials
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

**Problems:**

- Credentials in code/environment variables
- If compromised, attacker has permanent access
- Must manually rotate
- Risk of committing to git

**Real-world scenario WITH IAM Role:**

```bash
# Good practice: Instance profile
aws logs put-log-events

# Credentials automatically provided by AWS:
# - Auto-rotated every 6 hours
# - Never appear in code
# - Tied to instance (can't be extracted)
# - Automatically expire when instance terminates
```

---

#### 4. Instance Profile vs IAM Role

**Confusion:** What's the difference? Why do we need both?

**What I learned:**

**IAM Role:**

- Defines WHAT permissions you have
- Contains policies (actions allowed)
- Abstract concept

**Instance Profile:**

- HOW EC2 instances use a role
- Container that holds a role
- Physical attachment mechanism

**Analogy:**

- **IAM Role** = Your job title and responsibilities (Software Engineer)
- **Instance Profile** = Your employee badge that gives you access
- **IAM Policies** = Specific permissions (access building, use laptop, etc.)

**In Terraform:**

```hcl
# Create the role (what permissions)
resource "aws_iam_role" "backend" {
  # ... policies attached here
}

# Create the profile (how EC2 uses it)
resource "aws_iam_instance_profile" "backend" {
  role = aws_iam_role.backend.name
}

# Attach to instance
resource "aws_instance" "backend" {
  iam_instance_profile = aws_iam_instance_profile.backend.name
}
```

---

#### 5. User Data Execution and Limitations

**What I learned:**

**User Data characteristics:**

- Executes ONCE on first boot only
- Runs as root user (no sudo needed)
- Executes BEFORE instance is "ready"
- Limited to 16KB size
- Errors don't prevent instance from starting

**Execution order:**

```
1. Instance boots
2. User data script runs
3. Instance becomes "running" (ready for SSH)
4. You can connect
```

**How to check if user data ran:**

```bash
# SSH to instance
ssh ec2-user@10.0.11.5

# Check user data logs
sudo cat /var/log/cloud-init-output.log

# Check if packages installed
which git
# Should show: /usr/bin/git
```

**User Data vs Ansible:**

| Use Case                     | Tool      |
| ---------------------------- | --------- |
| Basic system setup           | User Data |
| Install base packages        | User Data |
| System configuration         | User Data |
| Application deployment       | Ansible   |
| Configuration management     | Ansible   |
| Complex multi-step processes | Ansible   |

**For this project:**

- User Data: Install system tools, create directories
- Ansible (Days 11-14): Deploy Node.js app, configure services

---

#### 6. SSH Jump Host (ProxyJump)

**Confusion:** How to SSH to instances in private subnets?

**What I learned:**

**Traditional method (two steps):**

```bash
# Step 1: SSH to Bastion
ssh ec2-user@54.144.192.77

# Step 2: From Bastion, SSH to Backend
ssh ec2-user@10.0.11.5
```

**Modern method (one command):**

```bash
# ProxyJump (-J flag)
ssh -J ec2-user@54.144.192.77 ec2-user@10.0.11.5
```

**How it works:**

1. SSH client connects to Bastion (54.144.192.77)
2. From Bastion, connects to Backend (10.0.11.5)
3. Creates encrypted tunnel through Bastion
4. You interact directly with Backend

**SSH Agent Forwarding:**

```bash
# Add key to agent
ssh-add ~/.ssh/movie-analyst-bastion-key

# Connect with forwarding (-A flag)
ssh -A ec2-user@54.144.192.77

# Now inside Bastion, can SSH to Backend without copying key
ssh ec2-user@10.0.11.5
```

**Security consideration:**

- ProxyJump: More secure (key never leaves local machine)
- Copying key to Bastion: Less secure (key on Bastion is attack vector)

---

#### 7. CloudWatch Detailed Monitoring

**Question:** What's the difference between basic and detailed monitoring?

**What I learned:**

| Basic Monitoring      | Detailed Monitoring       |
| --------------------- | ------------------------- |
| Free                  | $2.10/instance/month      |
| 5-minute intervals    | 1-minute intervals        |
| Standard metrics only | Standard + custom metrics |

**Standard metrics (both):**

- CPU utilization
- Network in/out
- Disk read/write

**Why detailed matters:**

- Faster incident detection (1 min vs 5 min)
- More granular troubleshooting
- Better for production systems

**For this project:**

```hcl
monitoring = true  # Enabled for learning purposes
```

**In production:** Always enable for critical instances

---

#### 8. Development Tools Package Group

**Question:** Why install "Development Tools"?

**What I learned:**

**What gets installed:**

```bash
yum groupinstall -y "Development Tools"
```

Installs:

- gcc (C compiler)
- g++ (C++ compiler)
- make (build automation)
- python (for node-gyp)
- git
- autoconf, automake

**Why needed for Node.js:**

- Many npm packages have native (C/C++) components
- Examples: bcrypt, node-sass, sqlite3, sharp
- These need to be compiled during `npm install`
- Without gcc/make, `npm install` fails

**Production consideration:**

- For production: Use pre-built binaries or Alpine packages
- Or build in Docker with multi-stage builds
- Reduces attack surface (don't need compiler in production)

**For this project:**

- Acceptable for learning environment
- Will use Ansible to deploy app (needs compilation)

---

### Challenges and Solutions

#### Challenge 1: Understanding Private Subnet Internet Access

**Problem:** Initially confused about how private subnets access internet without public IPs

**Solution:**

- NAT Gateway provides outbound-only internet access
- Route table directs 0.0.0.0/0 traffic to NAT
- NAT translates private IP to its public Elastic IP
- Response traffic automatically routed back

**Verification method:**

```bash
# On backend instance
curl https://ifconfig.me

# Returns NAT Gateway's public IP, not instance's private IP
# Confirms traffic is routed through NAT
```

---

#### Challenge 2: SSH Key Management for Jump Host

**Problem:** How to SSH from Bastion to Backend without exposing private key?

**Solutions evaluated:**

| Method               | Security | Complexity | Selected    |
| -------------------- | -------- | ---------- | ----------- |
| Copy key to Bastion  | Low      | Low        | ❌ No       |
| SSH Agent Forwarding | High     | Medium     | ✅ Yes      |
| AWS Systems Manager  | Highest  | High       | ❌ Overkill |

**Implementation:**

```bash
# Add key to local SSH agent
ssh-add ~/.ssh/movie-analyst-bastion-key

# Connect with agent forwarding
ssh -A ec2-user@54.144.192.77

# Can now SSH to backend without key on Bastion
```

---

#### Challenge 3: IAM Role Creation Order

**Problem:** Initially tried to reference IAM instance profile before creating it

**What I learned:**

**Correct order in Terraform:**

1. Create IAM role (`aws_iam_role.backend`)
2. Attach policies (`aws_iam_role_policy.*`)
3. Create instance profile (`aws_iam_instance_profile.backend`)
4. Reference in EC2 instance (`iam_instance_profile = ...`)

**Terraform handles dependencies automatically** via references

---

#### Challenge 4: Module Structure - Single vs Multiple Modules

**Initial approach:** Tried to call compute module twice (bastion + backend)

**Problem:**

```hcl
module "compute" { }  # First call
module "compute" { }  # Second call - ERROR: duplicate
```

**Solution:** Single module handles both bastion and backend

**Why this works better:**

- Shared resources (AMI data source, key pair)
- Single source of truth
- Easier dependency management
- Cleaner code

---

### Commands Used

```bash
# Module updates
cd terraform/modules/compute
# Updated variables.tf, main.tf, outputs.tf

# IAM creation
cd ~/proyecto-final-devops/terraform
touch iam.tf
# Created IAM role, policies, instance profile

# Terraform workflow
terraform fmt -recursive
terraform validate
terraform plan       # Review 7 new resources
terraform apply      # Create IAM + backend instances

# SSH verification
terraform output backend_ssh_commands
ssh -A -i ~/.ssh/movie-analyst-bastion-key ec2-user@$(terraform output -raw bastion_public_ip)
ssh ec2-user@10.0.11.5

# NAT Gateway verification (on backend)
nslookup google.com
curl -I https://www.google.com
curl https://ifconfig.me

# IAM verification (on backend)
curl http://169.254.169.254/latest/meta-data/iam/info
aws sts get-caller-identity
```

---

### Files Created/Modified

**Created:**

```
terraform/iam.tf                      # IAM role, policies, instance profile
```

**Modified:**

```
terraform/main.tf                     # Added backend configuration to compute module
terraform/outputs.tf                  # Added backend outputs
terraform/modules/compute/main.tf     # Added backend instances
terraform/modules/compute/variables.tf # Added backend variables
terraform/modules/compute/outputs.tf   # Added backend outputs
```

---

### Infrastructure Created

**AWS Resources (7 new):**

1. **IAM Role:** `qa-backend-role`

   - Allows EC2 service to assume role
   - Trust policy for ec2.amazonaws.com

2. **IAM Policy:** CloudWatch Logs

   - PutMetricData, CreateLogGroup, CreateLogStream, PutLogEvents
   - Allows backend to write application logs

3. **IAM Policy:** SSM Parameter Store

   - GetParameter, GetParameters, GetParametersByPath
   - Allows reading secrets (DB credentials, API keys)

4. **IAM Instance Profile:** `qa-backend-profile`

   - Attaches role to EC2 instances

5. **EC2 Instance:** `qa-backend-1`

   - Type: t2.micro
   - Subnet: qa-private-subnet-1 (10.0.11.0/24, us-east-1a)
   - Private IP: 10.0.11.x
   - Security Group: qa-backend-sg
   - IAM Profile: qa-backend-profile

6. **EC2 Instance:** `qa-backend-2`
   - Type: t2.micro
   - Subnet: qa-private-subnet-2 (10.0.12.0/24, us-east-1b)
   - Private IP: 10.0.12.x
   - Security Group: qa-backend-sg
   - IAM Profile: qa-backend-profile

**Total infrastructure now:**

- Networking: 22 resources
- Security: 5 resources
- Compute: 3 resources (Bastion)
- IAM: 4 resources
- Compute Backend: 2 resources
- **Total: 36 resources**

**Cost impact:**

- IAM resources: Free (always)
- EC2 t2.micro (2 instances): Free tier (750 hours/month shared)
- EBS volumes (16GB total): Free tier (30GB limit)
- **Additional cost: $0/month** (within free tier)

---

### Key Decisions Made

1. **Count over For_Each:** Simpler for fixed number of identical instances
2. **Round-robin AZ distribution:** Automatic HA without complex logic
3. **IAM Instance Profile:** Security best practice, no hardcoded credentials
4. **SSH Agent Forwarding:** Secure key management for jump host access
5. **Development Tools in user data:** Necessary for npm native module compilation
6. **Single compute module:** Handles both bastion and backend (simpler)
7. **Detailed monitoring enabled:** Worth the learning value

---

### Next Steps (Day 8)

**Frontend EC2 Instances:**

- [ ] Create frontend instances in public subnets
- [ ] Configure in both AZs (us-east-1a, us-east-1b)
- [ ] Verify HTTP access
- [ ] Test SSH access via Bastion
- [ ] User data for web server preparation

**Estimated time:** 2 hours

---

### Study Notes for Presentation

**Backend concepts to remember:**

- Private subnets = no public IPs, NAT for outbound only
- Count creates indexed resources: backend[0], backend[1]
- IAM role = what permissions, Instance profile = how EC2 uses it
- SSH ProxyJump = one command to access private instance
- User data = first boot only, Ansible = ongoing configuration

**Questions evaluator might ask:**

1. **"How do private instances access the internet?"**
   → NAT Gateway in public subnet provides outbound-only access via route table

2. **"Why use IAM role instead of access keys?"**
   → Auto-rotated temporary credentials, no hardcoding, better security, AWS manages lifecycle

3. **"What if one AZ fails?"**
   → Second backend instance in different AZ continues serving traffic (HA)

4. **"How do you deploy application to private instances?"**
   → SSH through Bastion, or use Systems Manager Session Manager, or Ansible from Bastion

5. **"Why Development Tools in user data?"**
   → Node.js native modules need C++ compiler for npm install, required for packages like bcrypt

**Architecture understanding:**

- Internet → IGW → ALB (public) → Backend (private) → RDS (private)
- SSH: Local → Bastion (public) → Backend (private)
- Backend → NAT → IGW → Internet (outbound only)
- IAM role enables AWS API access without credentials
