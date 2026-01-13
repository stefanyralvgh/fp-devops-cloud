# Technical Decisions - DevOps Final Project

**Project:** Cloud Migration with Terraform & Ansible  
**Cloud Provider:** AWS  
**Environments:** QA, Production  
**Last Updated:** January 13, 2026

---

## Infrastructure as Code

### Decision: Terraform as Primary IaC Tool

**Context:**  
The client requires infrastructure automation and has expressed confidence in Terraform expertise. The migration must support two environments (QA and Production) with reusable, maintainable code.

**Decision:**  
Use Terraform for all infrastructure provisioning, with modular architecture and workspace separation for environments.

**Justification:**

- Industry-standard IaC tool with strong AWS support
- Declarative approach ensures infrastructure consistency
- State management enables team collaboration
- Modules enable code reusability across client's other projects
- Well-documented and widely adopted (easier to maintain/transfer knowledge)

---

## State Management

### Decision: Remote State with S3 + DynamoDB

**Context:**  
Multiple team members need to collaborate on infrastructure changes. State file conflicts could corrupt infrastructure or cause data loss.

**Decision:**  
Store Terraform state remotely in S3 with DynamoDB-based locking mechanism.

**Implementation:**

- **S3 Bucket:** `terraform-state-[project]-[random]`
  - Versioning: Enabled (recovery from accidental changes)
  - Encryption: AES256 (data security at rest)
  - Public Access: Blocked (security best practice)
- **DynamoDB Table:** `terraform-state-lock`
  - Partition Key: `LockID` (String)
  - Purpose: Prevent concurrent state modifications
  - Billing Mode: `PAY_PER_REQUEST`

---

## Terraform Configuration

**Workspace Strategy:**

- Created workspaces: `qa`, `prod`
- Each workspace maintains independent state file in S3
- State path pattern: `env:/{workspace}/terraform.tfstate`
- Default workspace not used (using explicit qa/prod only)

**Validation:**

```bash
terraform init
terraform workspace list
terraform validate
```

### Decision: AWS Provider Configuration

**Implementation:**

- Provider version: ~> 5.0 (latest stable)
- Region: us-east-1 (consistent with free tier optimization)
- Default tags applied to all resources:
  - Project: movie-analyst-migration
  - ManagedBy: terraform
  - Environment: [workspace name]

**Justification:**

- Version constraint (~> 5.0) allows minor updates, prevents breaking changes
- Default tags ensure consistent resource labeling
- Environment tag dynamically reflects workspace (qa/prod)
- Simplifies cost tracking and resource management

### Decision: Variable Structure

**Implementation:**

- Core variables defined: region, project_name, environment, vpc_cidr
- Common tags map for consistent labeling
- Defaults provided for rapid development
- Can be overridden via tfvars for prod

## Networking Architecture

### VPC Design

**Decision:** Custom VPC with multi-tier subnet architecture

**Context:**  
The application requires clear separation between public-facing components (frontend), application logic (backend), and data storage (database). AWS best practices recommend network segmentation for security and scalability.

**Implementation:**

#### VPC Configuration

```
CIDR: 10.0.0.0/16 (65,536 IP addresses)
Region: us-east-1
Availability Zones: us-east-1a, us-east-1b
DNS Hostnames: Enabled
DNS Support: Enabled
```

**Why this CIDR block:**

- 10.x.x.x is a private IP range (RFC 1918)
- /16 provides ample space for future growth
- Allows for logical subnet segmentation (1-10 public, 11-20 backend, 21-30 database)

---

### Subnet Strategy

**Decision:** Three-tier subnet architecture across two availability zones

#### Public Subnets (Web Tier)

```
Purpose: Frontend instances, Bastion Host, NAT Gateway
Subnet 1: 10.0.1.0/24 (us-east-1a) - 256 IPs
Subnet 2: 10.0.2.0/24 (us-east-1b) - 256 IPs
Internet Access: Direct via Internet Gateway
Auto-assign Public IP: Enabled
```

**Justification:**

- Users must access frontend directly from internet
- Bastion host requires public IP for SSH access
- NAT Gateway requires public subnet placement
- Two subnets provide redundancy across AZs

#### Private Subnets (Application Tier)

```
Purpose: Backend API instances
Subnet 1: 10.0.11.0/24 (us-east-1a) - 256 IPs
Subnet 2: 10.0.12.0/24 (us-east-1b) - 256 IPs
Internet Access: Outbound only via NAT Gateway
Auto-assign Public IP: Disabled
```

**Justification:**

- Backend should not be directly accessible from internet (security)
- Still needs internet access for dependency downloads (npm install)
- Two subnets enable load balancing across AZs
- Number gap (1-2 vs 11-12) provides clear logical separation

#### Database Subnets (Data Tier)

```
Purpose: RDS MySQL instances
Subnet 1: 10.0.21.0/24 (us-east-1a) - 256 IPs
Subnet 2: 10.0.22.0/24 (us-east-1b) - 256 IPs
Internet Access: Outbound only via NAT Gateway (for patches)
Auto-assign Public IP: Disabled
```

**Justification:**

- Database must never be internet-accessible
- RDS requires 2+ subnets in different AZs (AWS requirement)
- Separate route table provides additional isolation layer
- Internet access needed for automated patching only

---

### Internet Gateway

**Decision:** Single Internet Gateway for entire VPC

**Implementation:**

```
Attached to: VPC
Used by: Public subnets only (via route table)
Bidirectional: Yes (inbound + outbound traffic)
```

**Justification:**

- One IGW per VPC is standard AWS pattern
- Provides internet connectivity for public subnet resources
- No additional cost (included with VPC)
- Required for:
  - Users accessing frontend
  - SSH access to bastion host
  - NAT Gateway public endpoint

---

### NAT Gateway

**Decision:** Single NAT Gateway in us-east-1a (cost optimization)

**Context:**  
Private subnets require outbound internet access for:

- Backend: npm install, OS updates, API calls
- Database: RDS automated patching, Aurora updates

**Alternatives Considered:**

| Option                  | Cost        | Availability | Complexity | Selected |
| ----------------------- | ----------- | ------------ | ---------- | -------- |
| **Single NAT Gateway**  | ~$32/month  | Single AZ    | Low        | ✅ Yes   |
| Dual NAT Gateway (HA)   | ~$64/month  | Multi-AZ     | Low        | ❌ No    |
| NAT Instance (t2.micro) | ~$0/month\* | Manual HA    | High       | ❌ No    |
| No NAT (public subnets) | $0          | N/A          | Low        | ❌ No    |

\*Free tier eligible but requires manual configuration and management

NAT Gateway vs NAT Instance: Detailed Comparison
NAT Gateway (Selected)
Direct Costs:
Hourly rate: $0.045/hour
Data transfer: $0.045/GB

Project duration (3 months):

- 100 hours × $0.045 = $4.50/month
- Data transfer: ~$1/month
- Total: $16.50 for entire project
  Team Time Costs:
  Setup: 5 minutes (included in Terraform module)
  Maintenance: 0 hours/month (AWS-managed service)
  Troubleshooting: 0 hours (99.99% SLA)

Total: 0 hours = $0
Benefits:

✅ AWS-managed (zero operational overhead)
✅ Auto-scaling (handles traffic spikes automatically)
✅ High reliability (99.99% SLA)
✅ High performance (up to 45 Gbps)
✅ Automatic security patching
✅ CloudWatch metrics included
✅ No single instance failure point

Total Cost: $16.50

NAT Instance (Rejected)
Direct Costs:
EC2 Instance: $0/month (t2.micro free tier eligible)
Elastic IP: $0 (while attached)
Data transfer: $0.09/GB (2x NAT Gateway rate)

Project duration (3 months):

- Instance: $0
- Data transfer: ~$6
- Total: $6
  Team Time Costs:
  Initial Setup:
- Launch and configure EC2 instance: 1 hour
- Configure IP forwarding (sysctl): 30 min
- Configure iptables NAT rules: 1 hour
- Security hardening: 1 hour
- Testing and validation: 2 hours
- Documentation: 30 min
  Subtotal: 6 hours @ $50/hour = $300

Monthly Maintenance (× 3 months):

- Monitor instance health: 30 min/week × 4 = 2 hours
- Apply security patches: 1 hour/month
- Investigate performance issues: 1 hour/month
  Subtotal: 4 hours/month × 3 months @ $50/hour = $600

Emergency Response (estimated):

- Instance failure recovery: 2 hours × $50 = $100

Total team time: 20 hours = $1,000
Drawbacks:

❌ Single point of failure (instance can crash)
❌ Limited performance (t2.micro = 2.5 Gbps burst only)
❌ Manual security patching required
❌ Requires monitoring and alerting setup
❌ Requires disaster recovery runbook
❌ No auto-scaling (manual intervention needed)
❌ Higher data transfer costs (2x rate)
❌ Security risk (SSH-accessible instance)

Total Cost: $1,006

**Decision Rationale:**

- **Cost:** $32/month for single NAT vs $64 for dual = 50% savings
- **Acceptable Risk:** QA environment; temporary AZ failure is tolerable
- **Mitigation:** Can manually fail over if needed (recreate NAT in other AZ)
- **Performance:** AWS-managed, auto-scaling, highly reliable
- **Simplicity:** No manual maintenance vs NAT instance

**Cost Mitigation Strategy:**

```bash
# Daily workflow to minimize cost:
terraform apply   # When starting work
terraform destroy # When finished for the day

Estimated monthly cost:
- 20 days × 5 hours = 100 hours
- 100 hours × $0.045/hour = $4.50
- Plus data transfer: ~$0.50
- Total: ~$5/month instead of $32/month
```

**Trade-off Accepted:**

- No high availability across AZs
- If us-east-1a fails: private subnets lose internet temporarily
- For production: would recommend dual NAT Gateways

---

### Route Tables

**Decision:** Three separate route tables for logical isolation

#### Public Route Table

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          igw-xxxxx (Internet Gateway)

Associated Subnets:
- public-subnet-1 (10.0.1.0/24)
- public-subnet-2 (10.0.2.0/24)
```

**Translation:** "For internet traffic (0.0.0.0/0), go directly through Internet Gateway"

**Why:** Public subnets need bidirectional internet access

---

#### Private Route Table (Application)

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          nat-xxxxx (NAT Gateway)

Associated Subnets:
- private-subnet-1 (10.0.11.0/24)
- private-subnet-2 (10.0.12.0/24)
```

**Translation:** "For internet traffic (0.0.0.0/0), route through NAT Gateway (outbound only)"

**Why:** Backend needs to download dependencies but shouldn't accept inbound internet connections

---

#### Database Route Table

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          nat-xxxxx (NAT Gateway)

Associated Subnets:
- database-subnet-1 (10.0.21.0/24)
- database-subnet-2 (10.0.22.0/24)
```

**Translation:** Same as private RT, but separate for additional isolation

**Why Separate RT for Database:**

- Logical separation (easy to identify database subnet traffic)
- Future flexibility (can modify DB routing without affecting backend)
- Compliance/audit (some regulations require separate network controls for data tier)
- Best practice (defense in depth)

---

### Key Networking Concepts (Study Notes)

#### Understanding 0.0.0.0/0

**What it means:** "All IP addresses" or "the entire internet"
**Mental model:** "For any destination outside our building (VPC)"
**Applies to:** Outbound traffic from inside VPC to internet
**Does NOT mean:** Inbound traffic is automatically allowed

#### Public vs Private Subnets

**Public Subnet = has route to Internet Gateway**

- Can send traffic to internet ✅
- Can receive traffic from internet ✅
- Instances get public IPs automatically
- Example: Frontend, Bastion

**Private Subnet = no direct route to Internet Gateway**

- Can send traffic to internet via NAT ✅
- CANNOT receive traffic from internet ❌
- Instances do NOT get public IPs
- Example: Backend, Database

**The key difference:** Not the subnet itself, but the route table association

#### NAT Gateway vs Internet Gateway

| Feature        | Internet Gateway  | NAT Gateway        |
| -------------- | ----------------- | ------------------ |
| **Direction**  | Bidirectional (↔) | Unidirectional (→) |
| **Public IPs** | Required          | Uses Elastic IP    |
| **Use Case**   | Public subnets    | Private subnets    |
| **Inbound**    | Allowed           | Blocked            |
| **Outbound**   | Allowed           | Allowed            |
| **Cost**       | Free              | ~$0.045/hour       |

**Mental Model:**

- IGW = Front door (people can enter and exit)
- NAT = Receptionist desk (employees can make calls out, but strangers can't call in)

---

## Cost Optimization

### Free Tier Utilization

**Resources Within Free Tier:**

- VPC, Subnets, Route Tables: Free (always)
- Internet Gateway: Free (always)
- Elastic IP (attached): Free (when in use)
- S3 state storage: <5GB limit
- DynamoDB operations: <1M/month limit

**Resources With Cost:**

#### NAT Gateway (Primary Cost)

```
Hourly rate: $0.045/hour
Data transfer: $0.045/GB (after first 1GB/month)

Scenarios:
- Left running 24/7: $32.40/month
- Daily work (5h/day, 20 days): $4.50/month
- Per session: $0.18 (4-hour work session)
```

**Mitigation Strategy:**

```bash
# Start of work session
terraform workspace select qa
terraform apply

# End Work Session
terraform destroy
```

## Security Architecture

### Decision: Security Groups as Primary Network Security Control

**Context:**  
AWS provides two network security mechanisms: Security Groups (stateful, resource-level) and Network ACLs (stateless, subnet-level). The application requires protection at multiple layers while maintaining simplicity and manageability.

**Decision:**  
Use Security Groups exclusively for network security. Do not implement Network ACLs.

**Implementation:**

Created 5 Security Groups with defense-in-depth strategy:

#### 1. Bastion Security Group

```hcl
Purpose: SSH access point for infrastructure management
Ingress: SSH (22) from administrator IP only (190.158.28.120/32)
Egress: All traffic (enables package installation, updates)
```

**Justification:**

- Single controlled entry point for SSH access
- IP whitelist prevents unauthorized access attempts
- Reduces attack surface (only one public SSH endpoint)
- Standard bastion host pattern

---

#### 2. Application Load Balancer Security Group

```hcl
Purpose: Accept HTTP/HTTPS traffic from internet
Ingress: HTTP (80) and HTTPS (443) from 0.0.0.0/0
Egress: All traffic (enables communication with backend)
```

**Justification:**

- Public-facing entry point for application
- Standard web ports (80, 443)
- HTTPS included for future SSL implementation
- No SSH access (not needed for managed service)

---

#### 3. Frontend Security Group

```hcl
Purpose: Web server instances
Ingress:
  - HTTP (80) from ALB Security Group
  - SSH (22) from Bastion Security Group
Egress: All traffic
```

**Justification:**

- Only ALB can send traffic to frontend (prevents direct internet access)
- SSH only from Bastion (least privilege access)
- Uses Security Group reference instead of CIDR (automatic IP resolution)

---

#### 4. Backend Security Group

```hcl
Purpose: Node.js API instances
Ingress:
  - Port 3000 from ALB Security Group
  - SSH (22) from Bastion Security Group
Egress: All traffic
```

**Port 3000 Justification:**

- Node.js application listens on port 3000 (configured in server.js)
- `app.listen(process.env.PORT || 3000)`
- Standard Node.js development port

**Security considerations:**

- Backend never directly exposed to internet
- Only ALB can communicate with application port
- SSH restricted to Bastion only
- Egress allows npm package downloads, OS updates

---

#### 5. RDS Security Group

```hcl
Purpose: MySQL database
Ingress: MySQL (3306) from Backend Security Group only
Egress: All traffic
```

**Justification:**

- Strictest security: Only backend instances can access database
- No SSH (RDS is managed service)
- No direct access from frontend, Bastion, or internet
- Egress allows AWS management traffic (patches, backups)

---

### Decision: Security Group References Over CIDR Blocks

**Context:**  
Security Group rules can specify allowed sources using either CIDR blocks (IP ranges) or references to other Security Groups.

**Decision:**  
Use Security Group references for all internal AWS resource communication. Use CIDR blocks only for external traffic (internet, administrator IP).

**Implementation Examples:**

```hcl
# ✅ Internal traffic: Use SG reference
ingress {
  description     = "Node.js app from ALB"
  from_port       = 3000
  to_port         = 3000
  protocol        = "tcp"
  security_groups = [aws_security_group.alb.id]
}

# ✅ External traffic: Use CIDR
ingress {
  description = "SSH from administrator"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["190.158.28.120/32"]
}
```

**Justification:**

- **Maintainability:** IPs change (especially for ALB, EC2), SG references auto-update
- **Clarity:** Makes traffic flow explicit (Backend accepts from ALB, not random IPs)
- **AWS best practice:** Recommended pattern in AWS documentation
- **No IP management:** Don't need to track and update specific IPs

**Trade-off:**

- Slightly more complex Terraform dependencies
- But: Worth it for long-term maintainability

---

### Decision: Stateful Security Groups (No Network ACLs)

**Context:**  
AWS offers two layers of network security:

- Security Groups: Stateful, allow-only, resource-level
- Network ACLs: Stateless, allow/deny, subnet-level

**Alternatives Considered:**

| Option                   | Complexity | Use Case                | Selected |
| ------------------------ | ---------- | ----------------------- | -------- |
| **Security Groups only** | Low        | Most applications       | ✅ Yes   |
| SGs + NACLs              | High       | Compliance requirements | ❌ No    |
| NACLs only               | Medium     | Legacy patterns         | ❌ No    |

**Decision:**  
Use Security Groups exclusively. Do not implement Network ACLs.

**Justification:**

**Stateful behavior:**

- Automatic return traffic (if you allow inbound SSH, responses automatically allowed)
- Simpler rule set (half the rules needed vs stateless)
- Less error-prone (no need to manage bidirectional rules)

**Example:**

```
Stateful SG:
- Allow inbound SSH (22) → Outbound responses automatic ✅

Stateless NACL would require:
- Allow inbound SSH (22)
- Allow outbound ephemeral ports (1024-65535) ← Extra complexity
```

**Why not Network ACLs:**

- SGs provide sufficient security for this application
- NACLs add complexity without security benefit
- Harder to troubleshoot (must check both SG and NACL)
- NACLs support deny rules, but default-deny SGs achieve same goal
- No compliance requirement for subnet-level controls

**When NACLs are needed:**

- Regulatory compliance (explicit deny rules required)
- DDoS protection (deny specific IP ranges)
- Defense in depth for highly sensitive data
- Not applicable to this project

---

### Decision: Egress Allow-All Policy

**Context:**  
Security Groups can restrict outbound traffic from resources. The default is allow-all egress.

**Decision:**  
Allow all outbound traffic (0.0.0.0/0 on all protocols) for all Security Groups.

**Implementation:**

```hcl
egress {
  description = "Allow all outbound traffic"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```

**Justification:**

**Operational requirements:**

- Package managers (npm, yum) need to reach external repositories
- OS updates require access to update servers
- Application may need to call external APIs
- RDS needs to communicate with AWS services (backups, patches)

**Security considerations:**

- Risk of data exfiltration exists BUT:
- Restrictive egress is operationally expensive
- Difficult to maintain (constantly updating allow lists)
- Application-layer controls (IAM, encryption) more effective
- Standard practice for most organizations

**Why restrictive egress is rare:**

- Requires exhaustive list of all external dependencies
- Breaks whenever dependencies change or add CDNs
- Maintenance burden outweighs security benefit
- Better addressed with:
  - VPC Flow Logs (monitor unexpected traffic)
  - AWS GuardDuty (detect anomalies)
  - CloudWatch alarms (alert on unusual patterns)

**When to restrict egress:**

- PCI DSS compliance (card data environment)
- HIPAA requirements (healthcare data)
- Zero-trust architecture
- Not applicable to this project

---

### Decision: Workspace-Based Environment Isolation

**Context:**  
Security Groups must be tagged with environment (QA, Production). Two approaches exist:

1. Separate code in `environments/qa/` and `environments/prod/`
2. Single codebase with Terraform workspaces

**Decision:**  
Use Terraform workspaces with single codebase in root directory.

**Implementation:**

```hcl
# main.tf (root)
module "security" {
  source      = "./modules/security"
  environment = terraform.workspace  # "qa" or "prod"
  # ... other variables
}
```

**Result:**

```bash
terraform workspace select qa   → Creates qa-bastion-sg, qa-alb-sg, etc.
terraform workspace select prod → Creates prod-bastion-sg, prod-alb-sg, etc.
```

**Justification:**

- **DRY principle:** Single codebase, no duplication
- **Consistency:** QA and Prod use identical security rules
- **Simplicity:** One place to update security policies
- **Less drift:** No risk of QA/Prod configurations diverging
- **Terraform native:** Workspaces designed for this use case

**Trade-offs accepted:**

- Risk of applying changes to wrong workspace (mitigated with careful workflow)
- Less flexibility for radically different configurations
- Acceptable for this project (QA and Prod are nearly identical)

**Alternative approach (when to use):**

- Separate directories when environments have fundamentally different:
  - Network architectures
  - Security policies
  - Compliance requirements
  - Module versions

---

### Security Best Practices Implemented

**Defense in Depth:**

- Multiple security layers (SG at each resource level)
- No single point of failure in security model
- ALB → Frontend/Backend → RDS (each protected)

**Least Privilege:**

- Bastion: Only SSH, only from admin IP
- Frontend: Only HTTP from ALB, SSH from Bastion
- Backend: Only app port from ALB, SSH from Bastion
- RDS: Only MySQL from Backend

**Network Segmentation:**

- Public subnet: ALB, Bastion only
- Private subnet: Backend (no internet inbound)
- Database subnet: RDS (no internet access)
- Security Groups enforce segmentation

**Auditability:**

- All rules have descriptive names
- Tags identify environment and management
- VPC Flow Logs can be enabled for monitoring

**Industry Standards:**

- Bastion host pattern (standard for SSH access)
- ALB as single entry point (standard web architecture)
- Database isolation (standard data protection)

---

### Cost Optimization

**Security Groups:**

- No cost (AWS doesn't charge for Security Groups)
- No performance impact
- Can create up to 2,500 SGs per VPC (far exceeds our needs)

**Rules per Security Group:**

- Maximum 60 inbound + 60 outbound rules
- Our SGs use 1-2 inbound rules each (well below limit)

---

## Compute Architecture - Bastion Host

### Decision: Bastion Host for SSH Access

**Context:**  
Backend and database instances will be deployed in private subnets without public IP addresses. Direct SSH access from the internet is impossible and would be a security anti-pattern even if possible.

**Decision:**  
Implement a Bastion Host (jump server) in a public subnet as the single, hardened entry point for SSH access to private infrastructure.

**Implementation:**

```hcl
Resource: aws_instance.bastion
AMI: Amazon Linux 2 (latest via data source)
Instance Type: t2.micro (free tier)
Subnet: First public subnet (us-east-1a)
Security Group: bastion-sg (SSH from admin IP only)
Elastic IP: Yes (persistent public address)
```

**Justification:**

**Security benefits:**

- **Reduced attack surface:** One SSH endpoint vs multiple exposed instances
- **Centralized access control:** Single point to implement security policies
- **Audit trail:** All SSH access funnels through one location
- **Easier hardening:** Only one host requires extensive security configuration

**Operational benefits:**

- **Simplified access:** Single IP to whitelist in corporate firewalls
- **Cost-effective:** Minimal additional cost (one t2.micro instance)
- **Standard pattern:** Industry-recognized best practice

**Alternative approaches considered:**

| Approach                            | Cost            | Complexity | Security  | Selected |
| ----------------------------------- | --------------- | ---------- | --------- | -------- |
| **Bastion Host**                    | ~$0 (free tier) | Low        | High      | ✅ Yes   |
| AWS Systems Manager Session Manager | $0              | Medium     | Very High | ❌ No    |
| VPN (Site-to-Site)                  | ~$36/month      | High       | High      | ❌ No    |
| VPN (Client VPN)                    | ~$72/month      | Medium     | High      | ❌ No    |
| Public IPs on all instances         | $0              | Low        | Very Low  | ❌ No    |

**Why not Systems Manager Session Manager:**

- Requires IAM setup and additional configuration
- Less familiar to evaluators (Bastion is standard)
- Harder to demonstrate in presentation
- Overkill for learning project
- Valid for production, but Bastion simpler for education

**Why not VPN:**

- Significant cost (~$36-72/month)
- Complex setup (customer gateway, VPN gateway)
- Overkill for project scope
- Bastion achieves same access goal at lower cost

**Trade-offs accepted:**

- Single point of failure (mitigated by quick recreation time)
- No high availability (acceptable for QA environment)
- Manual SSH vs automated Session Manager (acceptable for learning)

---

### Decision: Elastic IP for Bastion

**Context:**  
EC2 instances receive random public IPs that change on stop/start cycles. For a Bastion Host that serves as a consistent access point, IP address changes would break firewall rules, SSH configurations, and documentation.

**Decision:**  
Assign an Elastic IP to the Bastion Host for persistent public addressing.

**Implementation:**

```hcl
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
}
```

**Justification:**

**Benefits:**

- **Persistence:** IP survives instance stop/start/restart
- **Consistency:** Same IP for entire project lifecycle
- **Whitelisting:** Can configure firewall rules once
- **Documentation:** SSH commands don't need updating
- **Disaster recovery:** Can reassign to new instance if needed

**Cost analysis:**

- Free while attached to running instance
- $0.005/hour (~$3.60/month) if unattached
- **Mitigation:** Always attach before stopping billing (or destroy instance)

**Alternative considered:**

- Use instance public IP → Free but changes frequently
- **Rejected because:** Operational overhead of tracking IP changes outweighs minimal risk of EIP cost

---

### Decision: Amazon Linux 2 as Base Operating System

**Context:**  
Multiple Linux distributions are available for EC2 instances (Amazon Linux, Ubuntu, RHEL, CentOS). The choice affects package availability, support, and operational costs.

**Decision:**  
Use Amazon Linux 2 for all EC2 instances (Bastion, Backend, Frontend).

**Implementation:**

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

**Justification:**

**Amazon Linux 2 advantages:**

- **AWS-optimized:** Tuned for EC2 performance
- **Free:** No licensing costs (vs RHEL)
- **AWS integration:** Pre-installed AWS CLI, CloudWatch agent
- **Long-term support:** Updates until June 2025 (Amazon Linux 2023 available after)
- **amazon-linux-extras:** Simplified package management (Ansible, Docker, etc.)
- **Security:** Regular security patches from AWS
- **Documentation:** Extensive AWS documentation and tutorials

**Comparison with alternatives:**

| Distribution       | Cost      | AWS Integration | Package Availability | Learning Curve |
| ------------------ | --------- | --------------- | -------------------- | -------------- | ----------- |
| **Amazon Linux 2** | Free      | Excellent       | Good                 | Low            | ✅ Selected |
| Ubuntu 20.04/22.04 | Free      | Good            | Excellent            | Low            |
| RHEL 8             | ~$0.09/hr | Good            | Excellent            | Medium         |
| CentOS Stream      | Free      | Good            | Good                 | Medium         |

**Why not Ubuntu:**

- Amazon Linux 2 is the AWS "native" choice
- Better for demonstrating AWS expertise
- `amazon-linux-extras` simplifies Ansible installation
- Valid alternative, but AL2 more aligned with project goals

---

### Decision: AMI Discovery via Data Source

**Context:**  
Amazon Machine Image (AMI) IDs are region-specific and AWS updates them monthly with security patches. Hardcoding an AMI ID would create maintenance burden and region portability issues.

**Decision:**  
Use Terraform data source to dynamically discover the latest Amazon Linux 2 AMI at apply time.

**Implementation:**

```hcl
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "bastion" {
  ami = data.aws_ami.amazon_linux_2.id
  # ...
}
```

**Justification:**

**Benefits:**

- **Always latest:** Automatically uses newest AMI with security patches
- **Region-agnostic:** Same code works in any AWS region
- **No manual updates:** Don't need to track AMI releases
- **Security:** Reduces window of exposure to known vulnerabilities

**How it works:**

1. Terraform queries AWS API for AMIs
2. Filters by: owner (amazon), name pattern, virtualization type
3. Sorts by creation date
4. Returns most recent AMI ID
5. Uses that ID for instance creation

**Alternative (hardcoded AMI):**

```hcl
# ❌ Bad practice
ami = "ami-0c55b159cbfafe1f0"  # Fixed AMI, will become outdated
```

**Problems with hardcoding:**

- AMI might not exist in other regions
- AMI might be deprecated
- Missing security patches
- Code becomes region-specific

---

### Decision: User Data for Initial Configuration

**Context:**  
EC2 instances require baseline configuration (updates, timezone, tools) before they're ready for use. This can be done manually via SSH or automated via User Data scripts.

**Decision:**  
Use User Data scripts for repeatable, automated initial configuration.

**Implementation:**

```hcl
user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y git wget curl vim
  timedatectl set-timezone America/Bogota
  echo "Movie Analyst Bastion Host" > /etc/motd
EOF
```

**Justification:**

**Benefits:**

- **Automation:** No manual SSH configuration needed
- **Repeatability:** Recreating instance yields identical result
- **Infrastructure as Code:** Configuration defined in Terraform
- **Faster deployment:** Configuration happens during boot

**Limitations understood:**

- Executes only on first boot (not on restart)
- Limited to 16KB
- Errors don't prevent instance creation
- No built-in logging (must check `/var/log/cloud-init-output.log`)

**When to use User Data vs Configuration Management:**

| Approach                | Use Case                                                          |
| ----------------------- | ----------------------------------------------------------------- |
| **User Data**           | Simple package installation, system settings, one-time setup      |
| **Ansible/Chef/Puppet** | Complex configuration, application deployment, ongoing management |

**For this project:**

- User Data: Basic system setup (Bastion)
- Ansible: Application deployment (Frontend, Backend)
- Clean separation of concerns

---

### Decision: SSH Key Management Strategy

**Context:**  
EC2 instances require SSH key pairs for authentication. Keys can be generated by AWS or provided by users. Key management affects security and operational flexibility.

**Decision:**  
Generate SSH keys locally, store public key in Terraform, upload to AWS via `aws_key_pair` resource.

**Implementation:**

```bash
# Local key generation
ssh-keygen -t rsa -b 4096 -f movie-analyst-bastion-key
```

```hcl
# Terraform key pair resource
resource "aws_key_pair" "bastion" {
  key_name   = "${terraform.workspace}-bastion-key"
  public_key = file("${path.module}/keys/movie-analyst-bastion-key.pub")
}
```

**Security measures:**

```gitignore
# .gitignore
keys/
*.pem
```

**Justification:**

**Benefits of local generation:**

- **Control:** You manage the private key lifecycle
- **Backup:** Can regenerate public key from private key
- **Rotation:** Easy to create new keys and update Terraform
- **Portability:** Same key can be used across projects

**Benefits of AWS generation:**

- **Convenience:** AWS generates and provides .pem download
- **No local storage:** Key created directly in AWS

**Why local generation chosen:**

- More control and flexibility
- Standard DevOps practice
- Easier key rotation
- Can use same key across multiple environments if desired

**Alternative approaches:**

| Method               | Control | Backup    | Rotation | Selected    |
| -------------------- | ------- | --------- | -------- | ----------- |
| **Local generation** | High    | Easy      | Easy     | ✅ Yes      |
| AWS-generated        | Low     | Hard      | Hard     | ❌ No       |
| AWS Secrets Manager  | Medium  | Automatic | Medium   | ❌ Overkill |

---

### Decision: Instance Storage and Monitoring

**Context:**  
EC2 instances require root volume configuration. Options include volume type, size, encryption, and deletion policy. Monitoring can be basic (5-minute intervals) or detailed (1-minute intervals).

**Decision:**  
Use encrypted GP3 volumes with delete-on-termination enabled. Enable detailed monitoring.

**Implementation:**

```hcl
root_block_device {
  volume_type           = "gp3"
  volume_size           = 8
  delete_on_termination = true
  encrypted             = true
}

monitoring = true
```

**Justification:**

**Volume type (GP3):**

- Latest generation general-purpose SSD
- Better price/performance than GP2
- 3000 IOPS baseline (vs 100-16000 for GP2)
- Free tier eligible (30GB/month total across all volumes)

**Volume size (8GB):**

- Amazon Linux 2 requires ~2GB
- Leaves headroom for logs, packages, temporary files
- Within free tier limit
- Cost: $0.08/GB-month × 8GB = $0.64/month (if over free tier)

**Encryption (enabled):**

- Security best practice
- No performance penalty
- No additional cost
- Protects data at rest
- Required by many compliance frameworks

**Delete on termination (true):**

- Prevents orphaned volumes
- Reduces costs (no forgotten volumes accruing charges)
- Appropriate for ephemeral infrastructure
- **Trade-off:** Cannot preserve data if instance terminated (acceptable for Bastion)

**Detailed monitoring (enabled):**

- 1-minute metric intervals (vs 5-minute basic)
- Better troubleshooting capabilities
- Cost: $2.10/month per instance
- **For free tier:** First 10 metrics free, additional $0.30 per metric
- Worth it for learning (can see real-time performance)

---

### Cost Optimization Decisions

**Bastion Host monthly cost breakdown:**

| Resource              | Cost                   | Free Tier                 | Actual Cost  |
| --------------------- | ---------------------- | ------------------------- | ------------ |
| EC2 t2.micro          | $0.0116/hr (~$8.50/mo) | 750 hrs/mo                | $0           |
| EBS GP3 8GB           | $0.08/GB-mo            | 30GB/mo                   | $0           |
| Elastic IP (attached) | $0/hr                  | Always free when attached | $0           |
| Data Transfer Out     | $0.09/GB               | 100GB/mo                  | $0           |
| Detailed Monitoring   | $2.10/mo               | 10 metrics free           | $0           |
| **Total**             |                        |                           | **$0/month** |

**Cost mitigation strategies:**

1. Use t2.micro (free tier eligible)
2. Keep instance running (EIP free when attached)
3. Delete instance when not in use (save EC2 charges)
4. Use stop vs terminate (preserve EBS, still incur small charge)

**Production considerations:**

- High Availability: Auto Scaling Group (ASG) with min=1, max=1
- Multi-AZ: Bastion in each AZ (~$16/month)
- Reserved Instance: ~40% savings if running 24/7

---

---

## Day 7 - Backend Compute Infrastructure

### Decision: Backend EC2 Instances in Private Subnets

**Date:** January 11, 2026  
**Status:** ✅ Implemented  
**Workspace:** qa

---

#### Context

The Node.js backend API requires compute resources to run the application layer. The backend needs to:

- Accept traffic from the Application Load Balancer
- Communicate with RDS MySQL database
- Download dependencies from npm registry (internet access)
- NOT be directly accessible from the internet (security)

---

#### Decision

Deploy backend instances in **private subnets** across multiple Availability Zones with the following configuration:

**Instance Specifications:**

```
Instance Type: t3.micro (free tier eligible)
AMI: Amazon Linux 2 (latest, via data source)
Count: 2 instances (one per AZ)
Subnets: private-subnet-1 (us-east-1a), private-subnet-2 (us-east-1b)
Security Group: backend-sg (port 3000 from ALB, SSH from Bastion)
IAM Role: backend-role (SSM + CloudWatch permissions)
```

**Storage Configuration:**

```
Volume Type: GP3 (latest generation SSD)
Volume Size: 8GB
Encryption: Enabled
Delete on Termination: True
```

**Monitoring:**

```
Detailed Monitoring: Disabled (QA), Enabled (Production)
Rationale: Cost optimization for QA ($2.10/instance/month savings)
```

---

#### Implementation Details

##### User Data Script

Automated initial configuration:

```bash
#!/bin/bash
yum update -y                          # Security patches
yum groupinstall -y "Development Tools" # GCC, make, etc. for npm packages
yum install -y git wget curl vim       # Development tools
timedatectl set-timezone America/Bogota # Timezone alignment
mkdir -p /opt/movie-analyst            # Application directory
```

**Why Development Tools:**

- Some npm packages (e.g., bcrypt, node-sass) require native compilation
- Without Development Tools, `npm install` would fail on native dependencies

##### IAM Role Design

**Policies attached:**

1. **AmazonSSMManagedInstanceCore**

   - Enables AWS Systems Manager Session Manager
   - Alternative to SSH for troubleshooting
   - No need for open SSH ports in security group

2. **CloudWatchAgentServerPolicy**
   - Allows instance to send metrics/logs to CloudWatch
   - Enables application-level monitoring (beyond basic EC2 metrics)
   - Required for custom application metrics

**Why IAM role vs hardcoded credentials:**

- Security: No credentials stored on instance
- Automatic credential rotation
- Least privilege: Role can be modified without touching instances
- AWS best practice

##### Network Placement Strategy

**Distribution across AZs:**

```
Backend-1: private-subnet-1 (10.0.11.0/24, us-east-1a)
Backend-2: private-subnet-2 (10.0.12.0/24, us-east-1b)
```

**Why multi-AZ:**

- High availability: If one AZ fails, other continues serving traffic
- ALB can distribute load across both instances
- RDS Multi-AZ requires backend in both AZs for optimal latency

**Why modulo operator `count.index % length(subnets)`:**

- If we had 3 instances and 2 subnets:
  - Instance 0: 0 % 2 = 0 → subnet[0]
  - Instance 1: 1 % 2 = 1 → subnet[1]
  - Instance 2: 2 % 2 = 0 → subnet[0] (wraps around)
- Ensures even distribution even if instance count != subnet count

---

#### Validation Results

##### Internet Access Test (via NAT Gateway)

**Test performed:**

```bash
# SSH to Bastion
ssh -i ~/.ssh/movie-analyst-bastion-key ec2-user@54.144.192.77

# SSH to Backend from Bastion
ssh ec2-user@10.0.11.25  # Backend-1 private IP

# Test outbound connectivity
ping -c 3 google.com          # ✅ Success
curl -I https://registry.npmjs.org  # ✅ Success (HTTP 200)
```

**Result:** Backend instances successfully reach internet via NAT Gateway

**Why this matters:**

- Confirms NAT Gateway routing is correct
- Validates `npm install` will work during deployment
- Ensures `yum update` can fetch packages

##### SSH Access Test (Jump Host Pattern)

**Test performed:**

```bash
# Two-hop SSH (local → bastion → backend)
ssh -J ec2-user@54.144.192.77 ec2-user@10.0.11.25

# Alternative: ProxyJump flag
ssh -o ProxyJump=ec2-user@54.144.192.77 ec2-user@10.0.11.25
```

**Result:** ✅ Successfully connected to backend via Bastion

**Security validation:**

- Direct SSH from internet to backend: ❌ Blocked (as intended)
- SSH from Bastion to backend: ✅ Allowed (security group rule working)

##### User Data Execution

**Verification:**

```bash
# Check cloud-init logs
sudo tail -f /var/log/cloud-init-output.log

# Verify timezone
timedatectl
# Expected: America/Bogota

# Verify application directory
ls -la /opt/movie-analyst
# Expected: Directory exists

# Verify banner
cat /etc/motd
# Expected: Custom Movie Analyst banner
```

**Result:** All User Data tasks executed successfully

---

#### Alternative Approaches Considered

##### Auto Scaling Group (ASG)

**Not selected for this project:**

- Adds complexity (launch templates, scaling policies)
- Overkill for fixed workload (movie database queries)
- Would increase costs (ALB health checks, CloudWatch metrics)

**When to use ASG:**

- Variable traffic patterns
- Need automatic scaling based on CPU/memory
- Production environments requiring auto-recovery

##### Spot Instances

**Not selected:**

- Risk of interruption (AWS can reclaim with 2-min notice)
- Not acceptable for application tier
- Savings: ~60% vs On-Demand, but risk too high

**When to use Spot:**

- Batch processing (can tolerate interruptions)
- Stateless workers
- Non-critical environments

##### Larger Instance Types (t3.small, t3.medium)

**Not selected for QA:**

- t3.micro sufficient for development workload
- Cost optimization: $0 (free tier) vs $12-24/month
- Can scale up in production if needed

**When to use larger instances:**

- High CPU workload (complex calculations)
- Memory-intensive applications (large in-memory caches)
- Production environments with strict SLAs

---

#### Cost Analysis

**Backend infrastructure monthly cost (QA workspace):**

| Resource          | Cost                       | Free Tier  | Actual Cost  |
| ----------------- | -------------------------- | ---------- | ------------ |
| 2x EC2 t3.micro   | $0.0104/hr × 2 = ~$15/mo   | 750 hrs/mo | $0           |
| 2x EBS GP3 8GB    | $0.08/GB-mo × 16GB = $1.28 | 30GB/mo    | $0           |
| Data Transfer Out | $0.09/GB                   | 100GB/mo   | $0           |
| Basic Monitoring  | Free                       | Free       | $0           |
| **Total**         |                            |            | **$0/month** |

**Production considerations:**

- Detailed monitoring: +$2.10/instance/month = $4.20
- Larger instances (t3.small): ~$12/month per instance
- Reserved Instances: 40% savings if running 24/7

---

#### Security Considerations

**Network isolation:**

- ✅ No direct internet access (inbound)
- ✅ Outbound via NAT Gateway only
- ✅ Only ALB can send traffic to port 3000
- ✅ SSH only from Bastion

**Data protection:**

- ✅ EBS volumes encrypted at rest (AWS-managed keys)
- ✅ IAM roles instead of hardcoded credentials
- ✅ Security groups implement least privilege

**Potential improvements for production:**

- Use Customer Managed Keys (CMK) for encryption
- Enable VPC Flow Logs for traffic analysis
- Implement AWS GuardDuty for threat detection
- Add CloudWatch Logs for application logging

---

#### Trade-offs Accepted

**No Auto Scaling:**

- **Benefit:** Simpler architecture, easier to understand
- **Cost:** Manual intervention if traffic spikes
- **Mitigation:** Can add ASG later if needed

**Basic Monitoring in QA:**

- **Benefit:** Saves $4.20/month
- **Cost:** 5-minute metric intervals vs 1-minute
- **Mitigation:** Enabled in production where needed

**Single NAT Gateway:**

- **Benefit:** Saves $32/month vs dual NAT
- **Cost:** If us-east-1a fails, backend loses internet
- **Mitigation:** Acceptable for QA; prod would use dual NAT

---

#### Key Learnings

**Concepts mastered:**

- **IAM Instance Profiles:** How to grant EC2 permissions without credentials
- **User Data execution:** Runs once on first boot as root
- **Multi-AZ distribution:** Using modulo operator for even placement
- **Jump host pattern:** Two-hop SSH via Bastion
- **NAT Gateway validation:** Testing outbound connectivity

**Common pitfalls avoided:**

- Including `sudo` in User Data (already runs as root)
- Using `yum install nodejs` (installs old Node 10, not Node 18)
- Forgetting Development Tools (npm native dependencies fail)
- Not testing internet access before assuming NAT works

---

# Day 8 - Frontend Compute Infrastructure

## Decision: Frontend EC2 Instances in Public Subnets

**Date:** January 13, 2026  
**Status:** Implemented  
**Workspace:** qa

---

## Context

The Movie Analyst platform requires a presentation layer to serve the user interface. The frontend must:

- Serve static assets (HTML, CSS, JavaScript, images)
- Make API calls to the backend via an Application Load Balancer
- Download dependencies and updates from the internet
- Be highly available across multiple Availability Zones

Two architectural approaches were considered:

1. Static hosting (S3 + CloudFront)
2. Dynamic web server (EC2 + Nginx)

---

## Decision

Deploy frontend EC2 instances running Nginx in **public subnets**, distributed across multiple Availability Zones, with traffic routed through an Application Load Balancer.

### Instance Specifications

- Instance Type: t3.micro (free tier eligible)
- AMI: Amazon Linux 2 (latest)
- Count: 2 (one per AZ)
- Subnets:
  - public-subnet-1 (us-east-1a)
  - public-subnet-2 (us-east-1b)
- Security Group: frontend-sg
- IAM Role: frontend-role (SSM + CloudWatch)
- Public IPs: Auto-assigned
- Web Server: Nginx (via amazon-linux-extras)

### Storage

- Volume Type: gp3
- Size: 8 GB
- Encryption: Enabled
- Delete on Termination: True

---

## Justification

### Why EC2 over S3 + CloudFront

| Aspect      | S3 + CloudFront | EC2 + Nginx         |
| ----------- | --------------- | ------------------- |
| Cost        | ~$5/month       | $0 (free tier)      |
| Flexibility | Static only     | Dynamic capable     |
| Learning    | Limited         | Full infra exposure |
| Complexity  | Low             | Medium              |
| Performance | Global CDN      | Regional            |

Primary reasons:

- Educational value
- Free tier availability
- Flexibility for future SSR or proxying
- Consistency with backend compute model

Trade-off accepted: Regional availability instead of global CDN.

---

## Why Public Subnets

Frontend instances require outbound internet access for:

- Package updates
- Dependency installation
- CDN downloads
- Time synchronization

### Alternatives Considered

- Private subnet + NAT Gateway (rejected due to cost)
- VPC Endpoints (rejected due to complexity)

Decision: Public subnet with strict security groups.

---

## Implementation Details

### Nginx Installation

Incorrect approach:

```bash
yum install -y nginx
```

Correct approach:

```bash
amazon-linux-extras install nginx1 -y
systemctl enable nginx
systemctl start nginx
```

Reason: Nginx is provided via Amazon Linux Extras on AL2.

---

### Custom Hostnames

Purpose: Easier troubleshooting and clearer logs.

```bash
hostnamectl set-hostname frontend-${count.index + 1}-${var.environment}
echo "127.0.0.1 frontend-${count.index + 1}-${var.environment}" >> /etc/hosts
```

---

### Security Group Design

- HTTP: Only from ALB security group
- SSH: Only from Bastion security group

Key principle: Frontend must not be directly exposed to the internet.

Traffic flow:

User → ALB → Frontend → Backend

---

## Monitoring Strategy

- QA: Basic monitoring (5-minute intervals)
- Prod: Detailed monitoring (1-minute intervals)

Decision based on cost vs observability needs.

---

## User Data Logging

Enable full logging to avoid silent failures:

```bash
#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
```

Benefits:

- Debuggable boot process
- Persistent logs
- Faster issue resolution

---

## Cost Analysis (QA)

- EC2 t3.micro (2): $0
- EBS gp3 (8 GB x2): $0
- Monitoring: $0
- Total: $0/month

---

## Security Considerations

- Least-privilege security groups
- Encrypted EBS volumes
- IAM roles instead of credentials
- No direct internet access to backend or database

---

## Key Learnings

- Public subnet does not imply public access
- amazon-linux-extras is mandatory for modern packages
- User Data logging is critical
- Security group references are safer than CIDRs
- Custom hostnames improve operability

---

## Dependencies

Depends on:

- VPC and networking
- Bastion host
- Frontend security group

Required by:

- Application Load Balancer
- Configuration management
- End-to-end application flow
