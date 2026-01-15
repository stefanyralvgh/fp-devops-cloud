# Technical Decisions - DevOps Final Project

**Project:** Cloud Migration with Terraform & Ansible  
**Cloud Provider:** AWS  
**Environments:** QA, Production  
**Last Updated:** January 14, 2026

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

### Decision: NAT Gateway for Private Subnets

**Context**  
Backend and database instances are deployed in private subnets. Even though they must not be reachable from the internet, they still require outbound internet access for:

- OS security updates
- Package installation (e.g., npm, yum)
- AWS-managed services operations (RDS patching)

**Decision**  
Use a single **AWS NAT Gateway** in one public subnet to provide outbound-only internet access for all private subnets.

---

### Alternatives Considered

| Option              | Monthly Cost (Approx.) | Operational Effort | Reliability        | Selected |
| ------------------- | ---------------------- | ------------------ | ------------------ | -------- |
| **NAT Gateway**     | ~$32/month             | Very Low           | High (AWS-managed) | ✅ Yes   |
| NAT Instance (EC2)  | ~$0 (free tier)        | High               | Low–Medium         | ❌ No    |
| Public Subnets Only | $0                     | Low                | High               | ❌ No    |

---

### Cost Overview

**NAT Gateway (selected):**

- $0.045/hour → ~$32/month if left running
- Data transfer costs are minimal for this academic project
- In practice, cost can be reduced by destroying infrastructure when not in use

**Why cost is acceptable:**

- This project prioritizes **best practices and realistic architecture**
- Cost is documented and justified, not ignored
- For production, this cost is expected and standard

---

### Why NAT Gateway Instead of NAT Instance (Free Tier)

Although a NAT instance (t3.micro) could technically work at near-zero cost, it was intentionally rejected:

**NAT Gateway advantages:**

- Fully managed by AWS (no patching, no maintenance)
- No SSH access or instance hardening required
- Scales automatically with traffic
- Higher reliability and predictable behavior
- Simpler Terraform code and lower operational risk

**NAT Instance drawbacks:**

- Single point of failure
- Manual configuration (IP forwarding, iptables)
- Requires monitoring, patching, and recovery procedures
- Easier to misconfigure and less aligned with AWS best practices

**Conclusion:**  
For a project simulating a real production environment, **operational simplicity and correctness outweigh free-tier savings**.

---

### Trade-offs Accepted

- Single NAT Gateway (no Multi-AZ high availability)
- Temporary internet loss for private subnets if the AZ fails

**Mitigation:**  
This is acceptable for a QA / academic environment.  
In a real production setup, a NAT Gateway per AZ would be recommended.

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

## Cost Optimization

## Route Tables

**Decision:** Three separate route tables for logical isolation

### Public Route Table

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          igw-xxxxx (Internet Gateway)

Associated Subnets:
- public-subnet-1 (10.0.1.0/24)
- public-subnet-2 (10.0.2.0/24)
```

**Translation:** "For internet traffic (0.0.0.0/0), go directly through Internet Gateway"

**Why:** Public subnets require full inbound and outbound internet access.

---

### Private Route Table (Application)

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          nat-xxxxx (NAT Gateway)

Associated Subnets:
- private-subnet-1 (10.0.11.0/24)
- private-subnet-2 (10.0.12.0/24)
```

**Translation:** "For internet traffic (0.0.0.0/0), route through NAT Gateway (outbound only)"

**Why:** Backend services must access the internet (package downloads, updates, external APIs) without being publicly reachable.

---

### Database Route Table

```
Destination         Target
10.0.0.0/16        local (VPC internal)
0.0.0.0/0          nat-xxxxx (NAT Gateway)

Associated Subnets:
- database-subnet-1 (10.0.21.0/24)
- database-subnet-2 (10.0.22.0/24)
```

**Translation:** Same routing behavior as private application subnets, but isolated at the routing level.

**Why Separate Route Table for Database:**

- Clear logical separation of the data tier
- Independent control of routing rules if requirements change
- Easier auditing and troubleshooting
- Aligns with defense-in-depth and compliance-oriented designs

---

## Cost Considerations

This architecture intentionally balances **security, realism, and cost awareness**.

### Paid Networking Component: NAT Gateway

The **NAT Gateway** is the only networking resource in this setup that generates a predictable cost.

**Why it exists:**

- Allows private subnets to access the internet securely
- Prevents inbound internet access to backend and database layers
- Required for production-grade private architectures

**Pricing model:**

```
Hourly charge:        ~$0.045 per hour
Data processing:     ~$0.045 per GB (after first 1 GB/month)
```

**Typical cost scenarios (QA environment):**

- Running continuously (24/7): ~ $32.40 / month
- Daily development usage (5h/day, 20 days): ~ $4.50 / month
- Single 4-hour work session: ~ $0.18

---

### Cost Mitigation Strategy

To avoid unnecessary charges during development, infrastructure lifecycle is tightly controlled.

This approach is specific to this academic project, where the goal is learning AWS networking and Terraform without incurring ongoing costs.

In a real production environment, infrastructure would remain permanently provisioned. The AWS Free Tier is only a temporary benefit (first 12 months) and is not considered a long-term cost strategy.

For a small real-world environment, the primary fixed networking cost would typically be the NAT Gateway, which is an expected and acceptable operational expense. Other core networking components (VPC, subnets, route tables, Internet Gateway) do not incur charges.

The daily `terraform apply` / `terraform destroy` workflow is therefore used here purely as a cost-optimization mechanism for an academic setup, not as a recommended production practice.

```bash
# Start of work session
terraform workspace select qa
terraform apply

# End of work session
terraform destroy
```

This approach ensures:

- NAT Gateway costs are incurred only during active work
- Architecture remains production-realistic
- No idle infrastructure generates hidden costs

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

**Justification:**

- Backend instances are not publicly accessible; traffic is only allowed from the Application Load Balancer
- Enforces a clear separation between presentation and application layers
- SSH access is restricted to the Bastion host for controlled administrative access
- Security Group references are used instead of CIDR blocks, ensuring dynamic and resilient networking as infrastructure changes
- Aligns with least-privilege and defense-in-depth security principles

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
.pub
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

1. Use t3.micro (free tier eligible)
2. Keep instance running (EIP free when attached)
3. Delete instance when not in use (save EC2 charges)
4. Use stop vs terminate (preserve EBS, still incur small charge)

**Production considerations:**

- High Availability: Auto Scaling Group (ASG) with min=1, max=1
- Multi-AZ: Bastion in each AZ (~$16/month)
- Reserved Instance: ~40% savings if running 24/7

## Compute Architecture - Backend Instances

### Decision: Backend Instances in Private Subnets

**Context:**  
The Node.js backend API handles business logic and database queries. It should not be directly accessible from the internet but needs outbound internet access for package installation and external API calls.

**Decision:**  
Deploy backend instances in private subnets with no public IP addresses, using NAT Gateway for outbound internet access.

**Implementation:**

```hcl
Resource: aws_instance.backend (count = 2)
AMI: Amazon Linux 2 (shared data source with Bastion)
Instance Type: t2.micro (free tier)
Subnets: Private subnets (round-robin across AZs)
Security Group: backend-sg (port 3000 from ALB, SSH from Bastion)
IAM Profile: backend-profile (CloudWatch + SSM access)
Internet Access: Via NAT Gateway (outbound only)
```

**Justification:**

**Security benefits:**

- **No direct internet exposure:** Backend has no public IP address
- **ALB as single entry point:** Only ALB can send traffic to application port
- **Defense in depth:** Security Group + Network isolation + NAT gateway
- **Principle of least privilege:** Only necessary outbound access

**Operational benefits:**

- **Package management:** Can install npm packages via NAT
- **OS updates:** Can apply security patches
- **External APIs:** Can call third-party services (payment, email, etc.)
- **AWS service access:** Via VPC endpoints or public internet

**Why not public subnets:**

- Direct internet exposure increases attack surface
- Would need to manage inbound security rules for each instance
- Makes it harder to implement proper WAF/DDoS protection
- Backend doesn't need to accept inbound connections from internet

---

### Decision: Multi-AZ Distribution with Count

**Context:**  
Backend instances need high availability across multiple Availability Zones. Terraform provides two primary patterns for creating multiple resources: `count` and `for_each`.

**Decision:**  
Use `count` with modulo operator to distribute instances evenly across availability zones.

**Implementation:**

```hcl
resource "aws_instance" "backend" {
  count = var.backend_instance_count  # 2 instances

  subnet_id = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]

  # count.index = 0: 0 % 2 = 0 → subnet[0] (us-east-1a)
  # count.index = 1: 1 % 2 = 1 → subnet[1] (us-east-1b)
}
```

**Justification:**

**Why count over for_each:**

| Aspect          | Count                               | For_Each                             |
| --------------- | ----------------------------------- | ------------------------------------ |
| Use case        | Fixed number of identical resources | Dynamic list of resources            |
| Resource naming | Indexed (backend[0], backend[1])    | Named by key                         |
| Scaling         | Changes can cause recreation        | More stable with additions/deletions |
| Complexity      | Simple                              | More complex                         |

**For this project:**

- Number of backends is fixed (2 for QA, 2 for PROD)
- All backends are identical (homogeneous configuration)
- Not frequently adding/removing instances
- Simpler to understand and maintain

**When for_each would be better:**

- Dynamic list of subnets that changes
- Need to identify resources by name instead of index
- Frequently adding/removing resources
- Heterogeneous configurations

**Trade-offs accepted:**

- If we reduce count from 2 to 1, Terraform may recreate wrong instance
- Acceptable because we won't be scaling backends dynamically
- For dynamic scaling, would use Auto Scaling Group instead

---

### Decision: IAM Role and Instance Profile

**Context:**  
Backend instances need to interact with AWS services (CloudWatch Logs, Parameter Store, potentially S3). Using hardcoded credentials is a security anti-pattern.

**Decision:**  
Implement IAM role with instance profile, granting least-privilege access to required AWS services.

**Implementation:**

**IAM Role (qa-backend-role):**

```hcl
resource "aws_iam_role" "backend" {
  assume_role_policy = {
    # Allow EC2 service to assume this role
    Principal = { Service = "ec2.amazonaws.com" }
  }
}
```

**IAM Policies:**

1. **CloudWatch Logs:** Write application logs
2. **SSM Parameter Store:** Read secrets and configuration

**Instance Profile:**

```hcl
resource "aws_iam_instance_profile" "backend" {
  role = aws_iam_role.backend.name
}

resource "aws_instance" "backend" {
  iam_instance_profile = aws_iam_instance_profile.backend.name
}
```

**Justification:**

**Security benefits:**

| Without IAM Role              | With IAM Role                      |
| ----------------------------- | ---------------------------------- |
| Hardcoded credentials in code | No credentials in code             |
| Long-term static keys         | Temporary auto-rotated credentials |
| Manual rotation required      | AWS manages rotation               |
| Risk of committing to git     | No secrets to leak                 |
| Permanent if compromised      | Expires with instance              |

**How it works:**

```
1. EC2 instance boots with instance profile
2. AWS provides temporary credentials via metadata service
3. Credentials automatically rotated every 6 hours
4. Application uses AWS SDK without configuration
5. Credentials expire when instance terminates
```

**Example usage in application:**

```javascript
// No configuration needed - uses instance profile automatically
const AWS = require("aws-sdk");
const ssm = new AWS.SSM();

// Read database password from Parameter Store
const dbPassword = await ssm
  .getParameter({
    Name: "/movie-analyst/qa/db-password",
    WithDecryption: true,
  })
  .promise();
```

**Policies granted:**

**CloudWatch Logs:**

- `logs:CreateLogGroup` - Create log groups for application
- `logs:CreateLogStream` - Create log streams
- `logs:PutLogEvents` - Write log events
- `logs:DescribeLogStreams` - List log streams

**SSM Parameter Store:**

- `ssm:GetParameter` - Read individual parameters
- `ssm:GetParameters` - Read multiple parameters
- `ssm:GetParametersByPath` - Read all parameters under a path

**Scope:** Only `/movie-analyst/{environment}/*` parameters (least privilege)

---

### Decision: User Data for Initial Configuration

**Context:**  
Backend instances require baseline setup before application deployment: system updates, development tools, and directory structure.

**Decision:**  
Use user data scripts for system-level initialization. Reserve Ansible for application deployment.

**Implementation:**

```bash
#!/bin/bash
yum update -y
yum groupinstall -y "Development Tools"
yum install -y git wget curl vim
timedatectl set-timezone America/Bogota
mkdir -p /opt/movie-analyst
```

**Justification:**

**Why Development Tools:**

- Node.js packages with native modules require C++ compiler
- Examples: bcrypt (password hashing), node-sass (CSS compilation)
- `npm install` fails without gcc, make, python
- Alternative: Use Alpine packages or pre-built binaries (production)

**User Data characteristics:**

- Executes once on first boot
- Runs as root (no sudo needed)
- Completes before instance is "ready"
- Limited to 16KB size
- Errors don't prevent instance launch

**User Data vs Ansible:**

| Aspect          | User Data             | Ansible                |
| --------------- | --------------------- | ---------------------- |
| **When**        | First boot only       | On-demand, repeatable  |
| **Purpose**     | System initialization | Application deployment |
| **Complexity**  | Simple scripts        | Complex orchestration  |
| **Idempotency** | No                    | Yes                    |

**For this project:**

- **User Data:** Install system packages, create directories, set timezone
- **Ansible (Days 11-14):** Deploy Node.js app, configure services, manage config files

**Production considerations:**

- User data updates require instance recreation
- Not idempotent (runs once)
- Consider Golden AMIs (Packer) for production
- Or use immutable infrastructure (containers)

---

### Decision: Detailed CloudWatch Monitoring

**Context:**  
AWS provides two levels of EC2 monitoring: Basic (5-minute intervals, free) and Detailed (1-minute intervals, $2.10/instance/month).

**Decision:**  
Enable detailed monitoring for learning and troubleshooting purposes.

**Implementation:**

```hcl
resource "aws_instance" "backend" {
  monitoring = true  # Enable detailed monitoring
}
```

## Compute Architecture - Frontend Instances

### Decision: Frontend EC2 Instances in Public Subnets

**Context:**  
The Movie Analyst platform requires a presentation layer to serve the user interface. The frontend must serve static assets (HTML, CSS, JavaScript, images), make API calls to the backend via an Application Load Balancer, download dependencies and updates from the internet, and be highly available across multiple Availability Zones.

Two architectural approaches were considered:

1. Static hosting (S3 + CloudFront)
2. Dynamic web server (EC2 + Nginx)

**Decision:**  
Deploy frontend EC2 instances running Nginx in **public subnets**, distributed across multiple Availability Zones, with traffic routed through an Application Load Balancer.

**Instance Specifications:**

- **Instance Type:** t3.micro (free tier eligible)
- **AMI:** Amazon Linux 2 (latest, auto-discovered via data source)
- **Count:** 2 (one per AZ)
- **Subnets:** public-subnet-1 (us-east-1a), public-subnet-2 (us-east-1b)
- **Security Group:** frontend-sg
- **IAM Role:** frontend-role (SSM + CloudWatch)
- **Public IPs:** Auto-assigned
- **Web Server:** Nginx (via amazon-linux-extras)

**Storage:**

- **Volume Type:** gp3
- **Size:** 8 GB
- **Encryption:** Enabled
- **Delete on Termination:** True

**Justification:**

**Why EC2 over S3 + CloudFront:**

| Aspect      | S3 + CloudFront | EC2 + Nginx                  |
| ----------- | --------------- | ---------------------------- |
| Cost        | ~$5/month       | $0 (free tier)               |
| Flexibility | Static only     | Dynamic capable              |
| Learning    | Limited         | Full infrastructure exposure |
| Complexity  | Low             | Medium                       |
| Performance | Global CDN      | Regional                     |

**Primary reasons:**

- Educational value (hands-on EC2 management)
- Free tier availability (t3.micro 750 hours/month)
- Flexibility for future SSR or proxying
- Consistency with backend compute model

**Trade-off accepted:** Regional availability instead of global CDN (acceptable for educational project).

---

### Decision: Public Subnets Placement

**Context:**  
Frontend instances require outbound internet access for package updates, dependency installation, CDN downloads, and time synchronization.

**Decision:**  
Deploy frontend in public subnets with strict security groups.

**Alternatives Considered:**

| Approach                     | Cost                   | Complexity | Selected |
| ---------------------------- | ---------------------- | ---------- | -------- |
| **Public subnet + SG**       | $0                     | Low        | ✅ Yes   |
| Private subnet + NAT Gateway | +$32/month             | Medium     | ❌ No    |
| VPC Endpoints                | +$7/month per endpoint | High       | ❌ No    |

**Why public subnet:**

- Direct internet access (no NAT Gateway cost)
- Simpler architecture
- Security maintained via security groups (only ALB can access HTTP)

**Key security principle:** Public subnet does NOT mean public access. Security groups enforce "only ALB can reach port 80/443."

---

### Implementation Details

**Nginx Installation:**

**Incorrect approach:**

```bash
yum install -y nginx  # ❌ Fails on Amazon Linux 2
```

**Correct approach:**

```bash
amazon-linux-extras install nginx1 -y
systemctl enable nginx
systemctl start nginx
```

**Reason:** Nginx is provided via Amazon Linux Extras repository on AL2, not standard yum repos.

---

**Custom Hostnames:**

**Purpose:** Easier troubleshooting and clearer logs.

**Implementation:**

```bash
hostnamectl set-hostname frontend-${count.index + 1}-${var.environment}
echo "127.0.0.1 frontend-${count.index + 1}-${var.environment}" >> /etc/hosts
```

**Result:**

- frontend-1-qa.movie-analyst.local
- frontend-2-qa.movie-analyst.local

---

### Security Group Design

**Ingress rules:**

- **HTTP (80):** Only from ALB security group
- **SSH (22):** Only from Bastion security group

**Egress rules:**

- All traffic (0.0.0.0/0) for package updates

**Key principle:** Frontend must not be directly exposed to the internet.

**Traffic flow:**

```
User → ALB (alb-sg) → Frontend (frontend-sg) → Backend (backend-sg)
```

---

### Monitoring Strategy

**QA Environment:**

- Basic CloudWatch monitoring (5-minute intervals)
- Cost: $0

**Production Environment:**

- Detailed CloudWatch monitoring (1-minute intervals)
- Cost: ~$2.10/month per instance

**Decision rationale:** Cost vs observability needs. QA doesn't require minute-level granularity.

---

### User Data Logging

**Challenge:** User data script failures are silent by default.

**Solution:** Enable full logging to CloudWatch and local file.

**Implementation:**

```bash
#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
```

**Benefits:**

- Debuggable boot process
- Persistent logs in `/var/log/user-data.log`
- Faster issue resolution
- CloudWatch integration

---

### Cost Analysis

**QA Environment:**
| Resource | Specification | Free Tier | Cost |
|----------|---------------|-----------|------|
| EC2 t3.micro (2 instances) | 730 hours each | 750 hours/month | $0 |
| EBS gp3 (8GB × 2) | 16GB total | 30GB/month | $0 |
| Data transfer out | <100GB | 100GB/month | $0 |
| Basic monitoring | 5-min intervals | Included | $0 |
| **Total** | | | **$0/month** |

**Production Environment:**
| Resource | Cost |
|----------|------|
| EC2 t3.micro (2) | $0 (free tier) |
| EBS gp3 (16GB) | $0 (free tier) |
| Detailed monitoring | ~$4.20/month |
| **Total** | **~$4.20/month** |

---

### Security Considerations

**Network security:**

- Deployed in public subnets but protected by security groups
- No direct internet access to application port (only via ALB)
- SSH access only from Bastion (no direct internet SSH)

**Data security:**

- EBS volumes encrypted at rest (AES-256)
- IAM roles for AWS service access (no hardcoded credentials)
- Security group references instead of CIDR blocks

**Access control:**

- Principle of least privilege
- Defense in depth (SG + subnet isolation + IAM)

## Database Architecture - RDS MySQL

### Decision: Use Terraform Registry Module for RDS

**Context:**  
RDS configuration is complex with 50+ parameters (instance sizing, storage, backups, monitoring, parameter groups, option groups, IAM roles). Building from scratch would be error-prone, time-consuming, and require deep RDS expertise.

**Decision:**  
Use `terraform-aws-modules/rds/aws` version ~> 6.0 from Terraform Registry.

**Justification:**

- **Battle-tested:** 1.8k+ GitHub stars, maintained by Anton Babenko (core Terraform contributor)
- **Reduced complexity:** Abstracts parameter groups, option groups, IAM roles into simple inputs
- **Industry standard:** 95% of production RDS deployments use this module
- **Maintainability:** Module updates automatically handle AWS API changes
- **Built-in features:** Automatic password management via AWS Secrets Manager integration
- **Production-ready:** Includes monitoring, backups, encryption by default

**Alternative considered:**

- Writing RDS resources manually → Rejected (too complex, 200+ lines of code, reinventing the wheel)

**Version constraint:** `~> 6.0` means >= 6.0.0 AND < 7.0.0 (allows minor updates, prevents breaking changes)

---

### Decision: Workspace-Aware Configuration (QA vs Production)

**Context:**  
Production environments require higher availability and monitoring than QA, but at significant additional cost. Running production-grade infrastructure 24/7 in QA would exhaust budget unnecessarily.

**Decision:**  
Implement conditional configuration based on Terraform workspace using ternary operators.

**Configuration Matrix:**

| Configuration            | QA                  | Production             | Cost Impact              | Justification                                                                                                                                      |
| ------------------------ | ------------------- | ---------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Multi-AZ**             | ❌ Single-AZ        | ✅ Multi-AZ            | +$13/month               | QA: Single point of failure acceptable for cost savings. PROD: 99.95% SLA with automatic failover to standby in different AZ within 60-120 seconds |
| **Backup Retention**     | 1 day               | 7 days                 | $0 (storage = DB size)   | QA: Minimum AWS requirement. PROD: One-week disaster recovery window meets RPO requirements                                                        |
| **Deletion Protection**  | ❌ Disabled         | ✅ Enabled             | $0                       | QA: Frequent terraform destroy for cost management. PROD: Prevent accidental data loss from human error                                            |
| **Final Snapshot**       | ❌ Skip             | ✅ Create              | $0.095/GB-month          | QA: Faster infrastructure teardown (destroy in 2 min vs 10 min). PROD: Point-in-time recovery before deletion                                      |
| **Enhanced Monitoring**  | ❌ Disabled (basic) | ✅ 60-second intervals | +$2.10/month             | QA: CloudWatch basic metrics (5-min) sufficient. PROD: Detailed OS-level metrics for performance troubleshooting                                   |
| **Performance Insights** | ❌ Disabled         | ❌ Disabled            | N/A (would be +$7/month) | Not implemented: Cost vs benefit not justified for application scale. Basic query analysis through CloudWatch Logs sufficient                      |
| **Max Connections**      | 100                 | 200                    | $0 (parameter only)      | QA: Lower concurrent user simulation. PROD: Headroom for production traffic spikes                                                                 |

**Total Production Additional Cost:** ~$15/month  
**Justification:** Acceptable cost for production-grade reliability and observability. Represents 13% of $115 budget for 3-month project.

**Implementation:**

```hcl
multi_az = var.environment == "prod" ? true : false
backup_retention_period = var.environment == "prod" ? 7 : 1
monitoring_interval = var.environment == "prod" ? 60 : 0
deletion_protection = var.environment == "prod" ? true : false
skip_final_snapshot = var.environment == "prod" ? false : true
```

**Key benefit:** Single codebase for both environments. Deploy to production with:

```bash
terraform workspace select prod
terraform apply  # All production configs automatically applied
```

**No code duplication, no drift between environments.**

---

### Decision: Enhanced Monitoring IAM Role (Production Only)

**Context:**  
RDS Enhanced Monitoring requires an IAM role to publish OS-level metrics to CloudWatch Logs. This role is unnecessary in QA (basic monitoring sufficient) but critical in production for troubleshooting performance issues.

**Decision:**  
Create IAM role conditionally only in production workspace using `count` pattern.

**Implementation:**

```hcl
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix        = "${var.environment}-rds-monitoring-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
```

**Why conditional:**

- QA uses basic monitoring (no role needed, count = 0)
- Production uses enhanced monitoring (role required, count = 1)
- Reduces resource count in QA environment (cleaner state)
- Saves minimal IAM API calls

**Role permissions:**

- **Managed policy:** `AmazonRDSEnhancedMonitoringRole` (AWS-managed)
- **Allows:** RDS to send OS-level metrics to CloudWatch Logs
- **Trust policy:** Only `monitoring.rds.amazonaws.com` can assume

**What enhanced monitoring provides:**

- CPU utilization per core (vs aggregate)
- Memory usage breakdown (free, cached, buffers)
- Active database connections per process
- Read/write IOPS per device
- Network traffic per interface
- 1-60 second granularity (vs 5-minute basic)

---

### Decision: Password Management via AWS Secrets Manager

**Context:**  
Database passwords must be secured, rotatable, and auditable. Initially considered using `terraform.tfvars` (gitignored) for simplicity, but discovered the Terraform Registry RDS module includes built-in AWS Secrets Manager integration.

**Decision:**  
Use AWS Secrets Manager for password storage (automatic feature of registry module, not explicitly configured).

**How it works:**

1. Terraform passes `db_password` variable during initial `terraform apply`
2. RDS module automatically creates secret in AWS Secrets Manager
3. Secret name format: `rds!cluster-<random-id>` (AWS-managed naming)
4. RDS retrieves password from Secrets Manager during instance creation
5. Password never stored in plain text in Terraform state
6. Can be rotated via AWS Secrets Manager console (manual or automatic Lambda)

**Benefits:**

- **Security:** Passwords encrypted at rest (AES-256 with AWS KMS)
- **Auditability:** CloudTrail logs all secret access (who, when, from where)
- **Rotation:** Can enable automatic 90-day rotation with zero downtime
- **Separation of concerns:** Developers don't need password after initial deployment
- **Compliance:** Meets PCI-DSS, HIPAA, SOC 2 password management requirements
- **No state exposure:** Password never appears in Terraform state file

**Cost:**

- Secret storage: $0.40/month per secret
- API calls: $0.05 per 10,000 requests
- Typical monthly cost: ~$0.40-0.45 (RDS makes ~100 API calls/month)

**Initial setup:**

```hcl
# terraform.tfvars (used only during initial apply)
db_password = "SecurePassword123!"

# After deployment, password stored in:
# AWS Secrets Manager → rds!cluster-a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6
```

**Accessing password:**

```bash
# Via AWS Console
AWS Console → Secrets Manager → Secrets → rds!cluster-xxxxx → Retrieve secret value

# Via AWS CLI
aws secretsmanager get-secret-value --secret-id rds!cluster-xxxxx --query SecretString --output text
```

**Why this is better than alternatives:**

| Method                              | Security | Rotation  | Audit Trail      | Cost      | Selected |
| ----------------------------------- | -------- | --------- | ---------------- | --------- | -------- |
| **AWS Secrets Manager**             | High     | Automatic | Yes (CloudTrail) | ~$0.40/mo | ✅ Yes   |
| terraform.tfvars (gitignored)       | Medium   | Manual    | No               | $0        | ❌ No    |
| Hardcoded in code                   | Very Low | Manual    | No               | $0        | ❌ Never |
| Environment variables               | Medium   | Manual    | No               | $0        | ❌ No    |
| AWS Systems Manager Parameter Store | Medium   | Manual    | Yes              | $0        | ❌ No    |

**Production best practice implemented:**

- Password rotation can be enabled post-deployment (every 90 days recommended)
- Integration with Lambda for zero-downtime rotation (uses MySQL `ALTER USER`)
- CloudTrail audit logs for compliance reporting
- Automatic password complexity validation

**Discovery:** This was a hidden feature of the registry module, not documented in the README. Discovered when connection failed with password from `terraform.tfvars`, investigated AWS Console, found secret in Secrets Manager.

---

### Decision: Storage and Engine Configuration

**Storage Type:** GP3

**Why GP3 over GP2:**

- Latest generation general-purpose SSD (released 2020)
- 3,000 IOPS baseline (vs GP2's variable 100-16,000 IOPS based on size)
- 125 MB/s throughput baseline (vs GP2's variable)
- Lower cost: $0.08/GB-month (vs GP2's $0.10/GB-month)
- Can independently scale IOPS and throughput if needed (GP2 cannot)

**Storage sizing:**

- Allocated: 20GB (free tier limit)
- Max autoscaling: 100GB (prevents runaway costs)
- Encryption: Enabled (AES-256, no performance penalty, no extra cost)

**Engine:** MySQL 8.0

**Why MySQL 8.0:**

- Latest stable major version (8.0.35 at time of deployment)
- Application codebase already uses MySQL (compatibility)
- Modern features: JSON support, CTEs, window functions
- Better performance than 5.7 (query optimizer improvements)

**Character encoding:**

- **Character set:** utf8mb4 (full 4-byte Unicode support including emojis 🎬🍿)
- **Collation:** utf8mb4_unicode_ci (case-insensitive, language-aware sorting)
- **Why utf8mb4 not utf8:** utf8 in MySQL is limited to 3 bytes (missing emoji, some Asian characters)

**Why not other engines:**

| Engine       | Pros                                         | Cons                                              | Decision    |
| ------------ | -------------------------------------------- | ------------------------------------------------- | ----------- |
| **MySQL**    | Application compatibility, mature, free tier | Limited features vs PostgreSQL                    | ✅ Selected |
| PostgreSQL   | More features, better standards compliance   | Application rewrite needed                        | ❌ Rejected |
| Aurora MySQL | Better performance, serverless option        | 20% more expensive, overkill for scale            | ❌ Rejected |
| MariaDB      | MySQL fork, more features                    | Compatibility concerns, unknown long-term support | ❌ Rejected |

---

### Security Configuration

**Network isolation:**

- **Deployed in:** Private database subnets (10.0.21.0/24, 10.0.22.0/24)
- **Public accessibility:** Disabled (cannot be reached from internet)
- **Security group:** Allows MySQL (3306) only from backend security group

**Access pattern:**

```
User → Frontend → ALB → Backend → RDS
            ❌           ❌      ✅
         (blocked)   (blocked) (allowed)

Bastion → Backend → RDS
   ❌        ✅       ✅
(blocked) (allowed) (via backend)
```

**Key security principle: Defense in depth**

1. **Network layer:** Private subnets (no internet gateway routing)
2. **Security group layer:** Only backend-sg can access port 3306
3. **IAM layer:** RDS uses service-linked role for AWS operations
4. **Encryption layer:** Storage encrypted with AWS-managed KMS key

**Why Bastion cannot access RDS directly:**

- Separation of duties (Bastion is SSH jump host, not application server)
- Reduces attack surface (even if Bastion compromised, database unreachable)
- Forces all database access through application layer (audit trail)

**Encryption:**

- **Storage encryption:** Enabled (AES-256 at rest)
- **Backup encryption:** Automatic (inherits storage encryption)
- **Cost:** $0 (no additional charge for encryption)
- **Compliance:** Required by PCI-DSS, HIPAA, SOC 2

**Network flow for database query:**

```
Backend instance (10.0.11.183)
    ↓ MySQL protocol (port 3306)
VPC local routing (10.0.0.0/16)
    ↓
RDS Security Group check
    ↓ Source: backend-sg? ✅ Allow
RDS instance (10.0.21.x)
```

---

### Cost Analysis

**QA Environment (current deployment):**
| Resource | Specification | Free Tier | Monthly Cost |
|----------|---------------|-----------|--------------|
| RDS Instance | db.t3.micro, Single-AZ | 750 hours | $0 |
| Storage | 20GB GP3 | 20GB limit | $0 |
| Backups | 20GB (1 day retention) | = storage size | $0 |
| Secrets Manager | 1 secret | 30-day trial | $0.40 |
| CloudWatch Logs | 3 log groups | 5GB/month | $0 |
| Data transfer | <1GB | 100GB/month | $0 |
| **Total** | | | **$0.40/month** |

**Production Environment (when deployed):**
| Resource | Specification | Cost |
|----------|---------------|------|
| RDS Instance | db.t3.micro, Multi-AZ (2 instances) | ~$13/month |
| Storage | 20GB GP3 × 2 (primary + standby) | $0 (free tier) |
| Backups | 20GB (7 days retention) | $0 (= storage) |
| Enhanced Monitoring | 60-second intervals | $2.10/month |
| Secrets Manager | 1 secret | $0.40/month |
| CloudWatch Logs | 3 log groups | $0 (free tier) |
| **Total** | | **~$15.50/month** |

**Budget impact:** $46.50 over 3-month project (40% of $115 budget) - Justified by production-grade availability, monitoring, and disaster recovery capabilities.

**Cost optimization decisions:**

- Single-AZ in QA (save $13/month)
- Basic monitoring in QA (save $2.10/month)
- No Performance Insights (save $7/month in both envs)
- GP3 instead of io1/io2 (save ~$50/month)
- No read replicas (save $13+/month)

---

### DB Subnet Group Design

**Configuration:**

- **Name:** `qa-rds-subnet-group` (prod: `prod-rds-subnet-group`)
- **Subnets:**
  - database-subnet-1 (10.0.21.0/24, us-east-1a)
  - database-subnet-2 (10.0.22.0/24, us-east-1b)

**Why required:**

- **AWS RDS requirement:** Minimum 2 subnets in different Availability Zones
- **Even for Single-AZ:** Subnet group still needs 2+ subnets (AWS API requirement)
- **Enables Multi-AZ:** RDS can place standby in different subnet automatically
- **Failure domain isolation:** Primary and standby never in same AZ

**Architecture benefit:**

- QA is Single-AZ but subnet group spans 2 AZs
- Promoting to Multi-AZ requires zero infrastructure changes
- Just change `multi_az = true` and Terraform handles the rest

**Resource structure:**

```hcl
resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.environment}-rds-subnet-group-"
  subnet_ids  = var.database_subnet_ids  # Passed from networking module

  lifecycle {
    create_before_destroy = true
  }
}
```

---

### Dependencies

**Depends on:**

- VPC and networking module (database subnets, route tables)
- Security module (RDS security group, backend security group for reference)
- Compute module (backend instances for connectivity testing)

**Required by:**

- Backend application (needs database for data persistence)
- Data migrations (schema creation via ORM)
- Application health checks (database connectivity validation)

---
