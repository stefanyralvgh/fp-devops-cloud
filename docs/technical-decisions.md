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
Enable detailed monitoring for troubleshooting purposes (Production only).

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

# Technical Decisions - Day 10: Application Load Balancer

**Project:** Cloud Migration with Terraform & Ansible  
**Date:** January 11, 2026  
**Module:** Load Balancer (ALB)

---

## Load Balancer Architecture

### Decision: Application Load Balancer for HTTP Traffic Distribution

**Context:**  
The Movie Analyst application has multiple backend instances (2x) deployed across availability zones. Users need to access the application through a single endpoint, with automatic traffic distribution and health-based routing.

**Decision:**  
Implement AWS Application Load Balancer (ALB) in public subnets with target group routing to backend instances.

**Alternatives Considered:**

| Option                        | Cost       | Features                         | Use Case             | Selected |
| ----------------------------- | ---------- | -------------------------------- | -------------------- | -------- |
| **Application Load Balancer** | ~$16/month | Layer 7, path routing, WebSocket | Web applications     | ✅ Yes   |
| Classic Load Balancer         | ~$15/month | Layer 4, basic                   | Legacy apps          | ❌ No    |
| Network Load Balancer         | ~$16/month | Layer 4, ultra-low latency       | TCP/UDP traffic      | ❌ No    |
| No Load Balancer              | $0         | None                             | Single instance only | ❌ No    |

**Justification:**

**Application Load Balancer advantages:**

- **Layer 7 routing:** HTTP/HTTPS aware (can route based on URL paths)
- **Health checks:** Automatic removal of unhealthy instances from pool
- **Cross-zone load balancing:** Distributes traffic across AZs evenly
- **WebSocket support:** Required for real-time features (if needed)
- **Free SSL/TLS termination:** HTTPS support without extra cost
- **Integration with Auto Scaling:** Supports future scaling needs

**Why not Classic Load Balancer:**

- Deprecated by AWS (legacy technology)
- Limited Layer 7 features
- No path-based routing
- Being phased out

**Why not Network Load Balancer:**

- Layer 4 only (TCP/UDP)
- No HTTP-specific features
- Overkill for web application
- Better for non-HTTP workloads (databases, game servers)

**Real-world scenario:**

```
User request → ALB (public subnet)
  ↓
ALB health check: Backend-1 ✅ healthy, Backend-2 ❌ unhealthy
  ↓
Route to: Backend-1 only
  ↓
Backend-1 processes request → Returns response
```

---

## Module Strategy: Terraform Registry vs Custom Module

### Decision: Use Terraform Registry Module with Custom Wrapper

**Context:**  
Two approaches existed for implementing ALB:

1. Write custom Terraform code (200+ lines)
2. Use community module from Terraform Registry

**Decision:**  
Use `terraform-aws-modules/alb/aws` from Terraform Registry, wrapped in custom `modules/loadbalancer/` for consistency.

**Implementation:**

```
terraform/
├── modules/
│   └── loadbalancer/
│       ├── main.tf         # Calls registry module
│       ├── variables.tf    # Project-specific variables
│       └── outputs.tf      # Processed outputs
└── main.tf                 # Invokes loadbalancer module
```

**Justification:**

**Benefits of Registry module:**

- ✅ **Battle-tested:** Used by thousands of projects
- ✅ **Best practices:** Maintained by AWS experts
- ✅ **Reduced code:** ~20 lines vs ~200 lines custom
- ✅ **Automatic updates:** Bug fixes and improvements
- ✅ **Well-documented:** Extensive examples

**Benefits of custom wrapper:**

- ✅ **Consistency:** Matches project structure (networking, security, compute modules)
- ✅ **Abstraction:** Hides registry module complexity
- ✅ **Project-specific logic:** Environment-aware configurations
- ✅ **Future extensibility:** Easy to add custom logic if needed

**Comparison with Database module:**

| Aspect                | Database Module                  | Load Balancer Module             |
| --------------------- | -------------------------------- | -------------------------------- |
| **Registry Module**   | ✅ terraform-aws-modules/rds/aws | ✅ terraform-aws-modules/alb/aws |
| **Custom Wrapper**    | ✅ Yes (password generation)     | ✅ Yes (consistency)             |
| **Additional Logic**  | ✅ Random password, snapshots    | ❌ Minimal                       |
| **Processed Outputs** | ✅ Connection strings            | ❌ Direct passthrough            |

**Trade-offs accepted:**

- Dependency on external module (mitigated by version pinning)
- Less control over internal implementation (acceptable for standard use case)
- One extra abstraction layer (minor, improves consistency)

---

## Module Version Selection

### Decision: Downgrade from v9.0 to v8.0 due to Critical Bug

**Context:**  
Initial implementation used `version = "~> 9.0"` (latest version). During `terraform plan`, encountered error:

```
Error: Missing required argument
The argument "target_id" is required, but no definition was found.
```

**Root cause analysis:**

1. **Configuration matched official documentation** (not user error)
2. **Error occurred internally** (`.terraform/modules/alb/...`)
3. **Bug in module version 9.x:** Known issue with `target_groups` and `additional_target_group_attachments`
4. **Community reports:** Multiple users experienced same issue

**Decision:**  
Downgrade to version 8.x which is stable and well-tested.

**Implementation:**

```hcl
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"  # ✅ Stable version, bug-free
  # ...
}
```

**Justification:**

**Why version pinning matters:**

- ✅ **Stability:** v8.x is production-proven
- ✅ **Predictability:** No surprise breaking changes
- ✅ **Reproducibility:** Same version across environments
- ✅ **Team alignment:** Everyone uses identical provider/module versions

**Lessons learned:**

1. **Latest ≠ Best:** Newest versions can have regressions
2. **Pin versions explicitly:** Always use `~>` or `=` constraints
3. **Check changelogs:** Review release notes before upgrading
4. **Community validation:** Wait for community adoption before using new versions
5. **Error investigation:** Internal module errors suggest version issue, not configuration issue

**Version constraint strategy:**

| Constraint           | Meaning       | Use Case            | Selected      |
| -------------------- | ------------- | ------------------- | ------------- |
| `version = "8.7.0"`  | Exact version | Critical production | ❌ Too strict |
| `version = "~> 8.0"` | 8.x only      | Stable with patches | ✅ Yes        |
| `version = ">= 8.0"` | 8.x and above | Risky               | ❌ No         |
| No constraint        | Any version   | Never use           | ❌ No         |

**Why `~> 8.0`:**

- Allows: 8.1, 8.2, 8.7 (patch updates)
- Blocks: 9.0, 10.0 (major version changes)
- Balance: Stability + security patches

---

## Target Group Configuration

### Decision: Health Check on `/health` Endpoint

**Context:**  
ALB needs to determine which backend instances are healthy and can receive traffic.

**Decision:**  
Configure health checks to query `/health` endpoint on port 3000.

**Implementation:**

```hcl
health_check = {
  enabled             = true
  interval            = 30
  path                = "/health"
  port                = "traffic-port"  # Same as target (3000)
  healthy_threshold   = 2
  unhealthy_threshold = 2
  timeout             = 5
  protocol            = "HTTP"
  matcher             = "200-299"
}
```

**Justification:**

**Health check parameters explained:**

| Parameter               | Value      | Meaning                       |
| ----------------------- | ---------- | ----------------------------- |
| **interval**            | 30 seconds | Check every 30s               |
| **path**                | `/health`  | GET request to this endpoint  |
| **healthy_threshold**   | 2          | 2 successful checks → healthy |
| **unhealthy_threshold** | 2          | 2 failed checks → unhealthy   |
| **timeout**             | 5 seconds  | Max response time             |
| **matcher**             | 200-299    | HTTP success codes            |

**Why `/health` endpoint:**

- ✅ Standard REST API convention
- ✅ Lightweight (no DB query needed)
- ✅ Fast response (< 100ms typical)
- ✅ Can check internal dependencies if needed

**Example health check flow:**

```
ALB: GET http://10.0.11.25:3000/health
Backend-1: HTTP 200 OK {"status": "healthy"}
ALB: ✅ Healthy (1/2)

[30 seconds later]

ALB: GET http://10.0.11.25:3000/health
Backend-1: HTTP 200 OK {"status": "healthy"}
ALB: ✅ Healthy (2/2) → Instance marked healthy

[30 seconds later]

ALB: GET http://10.0.11.25:3000/health
Backend-1: [timeout after 5 seconds]
ALB: ❌ Unhealthy (1/2)

[30 seconds later]

ALB: GET http://10.0.11.25:3000/health
Backend-1: [timeout after 5 seconds]
ALB: ❌ Unhealthy (2/2) → Instance removed from pool
```

**Alternative health check paths considered:**

| Path          | Pros                    | Cons                         | Selected |
| ------------- | ----------------------- | ---------------------------- | -------- |
| **`/health`** | Standard, simple        | Requires implementation      | ✅ Yes   |
| `/`           | No code needed          | False positives              | ❌ No    |
| `/api/status` | Can check DB connection | Slower, couples health to DB | ❌ No    |

**Deregistration delay:**

```hcl
deregistration_delay = 10  # seconds
```

**Why 10 seconds:**

- Default is 300 seconds (too long for development)
- 10 seconds allows in-flight requests to complete
- Fast failover during testing

---

## Deletion Protection Strategy

### Decision: Workspace-Aware Deletion Protection

**Context:**  
Accidental ALB deletion in production would cause complete application outage. However, QA environment requires frequent iteration and testing.

**Decision:**  
Enable deletion protection only in production workspace.

**Implementation:**

```hcl
enable_deletion_protection = terraform.workspace == "prod" ? true : false
```

**Result:**

| Workspace | Protection | Behavior                                        |
| --------- | ---------- | ----------------------------------------------- |
| **qa**    | `false`    | Can be destroyed with `terraform destroy`       |
| **prod**  | `true`     | Cannot be destroyed without manual intervention |

**Justification:**

**Production protection:**

- ✅ Prevents accidental `terraform destroy`
- ✅ Requires explicit AWS Console action to disable protection
- ✅ Multi-step process reduces human error
- ✅ Audit trail in CloudTrail

**QA flexibility:**

- ✅ Rapid iteration (destroy/apply cycles)
- ✅ Testing disaster recovery procedures
- ✅ Cost optimization (can destroy overnight)
- ✅ No bureaucracy for experimentation

**To destroy protected ALB (production):**

```bash
# 1. Disable protection via AWS Console
# 2. Or update Terraform:
terraform workspace select prod
# Temporarily change: enable_deletion_protection = false
terraform apply
# Then destroy:
terraform destroy
```

---

## Security Group Integration

### Decision: Reuse Existing Security Group from Security Module

**Context:**  
The Terraform Registry ALB module can either:

1. Create its own security group (default)
2. Use an existing security group

**Decision:**  
Use security group created by `modules/security/` to maintain centralized security management.

**Implementation:**

```hcl
# ❌ Don't let ALB module create SG
# security_group_ingress_rules = { ... }
# security_group_egress_rules = { ... }

# ✅ Use our existing SG
security_groups = [var.alb_sg_id]  # From security module
```

**Justification:**

**Benefits of centralized security groups:**

| Aspect                     | With Reuse                    | Without Reuse              |
| -------------------------- | ----------------------------- | -------------------------- |
| **Single source of truth** | ✅ All SGs in security module | ❌ Split across modules    |
| **Rule changes**           | ✅ One place to update        | ❌ Multiple places         |
| **Audit**                  | ✅ Easy to review all rules   | ❌ Scattered configuration |
| **Dependencies**           | ✅ Clear module dependencies  | ❌ Implicit dependencies   |

**Security group rules (defined in security module):**

```hcl
# Ingress
HTTP (80)   ← 0.0.0.0/0 (internet)
HTTPS (443) ← 0.0.0.0/0 (internet)

# Egress
All traffic → 0.0.0.0/0 (to backend instances)
```

**Module dependency flow:**

```
main.tf
  ↓
security module → creates alb_sg
  ↓
loadbalancer module → uses alb_sg
```

---

## Cost Optimization

### ALB Cost Analysis

**Fixed costs:**

```
ALB base: $0.0225/hour × 730 hours = $16.43/month
Load Balancer Capacity Units (LCU):
  - New connections: $0.008/LCU-hour
  - Active connections: $0.008/LCU-hour
  - Processed bytes: $0.008/LCU-hour

For low-traffic app: ~1-2 LCUs = $6-12/month
Total: ~$22-28/month
```

**Cost optimization decisions:**

| Decision                     | Savings | Trade-off                      |
| ---------------------------- | ------- | ------------------------------ |
| **Single ALB**               | N/A     | None (need at least one)       |
| **HTTP only**                | $0      | No SSL/TLS (acceptable for QA) |
| **Cross-zone enabled**       | $0      | Better availability            |
| **Deletion protection (QA)** | N/A     | Can destroy when not in use    |

**Comparison with alternatives:**

| Solution         | Monthly Cost | Features                      |
| ---------------- | ------------ | ----------------------------- |
| **ALB**          | ~$25         | Full Layer 7, health checks   |
| Nginx on EC2     | ~$8          | Manual setup, no auto-scaling |
| No load balancer | $0           | Single point of failure       |

**Decision:** ALB worth the cost for production-like environment and learning experience.

---

## Key Learnings

### 1. Module Version Management

- Always pin module versions explicitly
- Latest version ≠ most stable version
- Check community issues before upgrading
- Version constraints prevent breaking changes

### 2. Registry Modules

- Powerful but not infallible (bugs exist)
- Balance between convenience and control
- Custom wrappers provide flexibility
- Consistency with project structure matters

### 3. Health Checks

- Critical for high availability
- Fast, lightweight endpoints preferred
- Threshold tuning prevents flapping
- Deregistration delay important for graceful shutdown

### 4. Workspace-Aware Configuration

- Different needs for QA vs Production
- Conditional logic with ternary operators
- Single codebase, environment-specific behavior
- Document differences clearly

---

## Future Improvements

### Phase 1 (Current Project)

- ✅ Basic HTTP load balancing
- ✅ Health checks on `/health`
- ✅ Cross-zone distribution

### Phase 2 (Production Readiness)

- [ ] HTTPS with ACM certificate
- [ ] WAF (Web Application Firewall) integration
- [ ] Access logs to S3
- [ ] CloudWatch alarms on target health

### Phase 3 (Advanced Features)

- [ ] Path-based routing (e.g., `/api/*` → Backend, `/admin/*` → Admin service)
- [ ] Host-based routing (multiple domains)
- [ ] Lambda targets for serverless functions
- [ ] Sticky sessions (if needed)

---

## Configuration Management - Ansible

### Decision: Ansible as Configuration Management Tool

**Context:**  
Infrastructure created by Terraform requires software installation and configuration. Manual SSH configuration is error-prone, not repeatable, and doesn't scale.

**Decision:**  
Use Ansible for all post-provisioning configuration and application deployment.

**Justification:**

**Ansible advantages:**

- Agentless (no software on managed nodes beyond Python and SSH)
- Declarative YAML syntax (infrastructure as code)
- Idempotent operations (safe to re-run)
- Large module ecosystem (yum, systemd, template, etc.)
- Strong community and documentation

**Alternatives considered:**

| Tool          | Pros                          | Cons                                 | Selected |
| ------------- | ----------------------------- | ------------------------------------ | -------- |
| **Ansible**   | Agentless, simple, idempotent | Slower than alternatives             | ✅ Yes   |
| Chef          | Fast, Ruby DSL                | Requires agent, complex              | ❌ No    |
| Puppet        | Mature, enterprise features   | Requires agent, steep learning curve | ❌ No    |
| Salt          | Fast, scalable                | Requires agent, less common          | ❌ No    |
| Shell scripts | Simple, no dependencies       | Not idempotent, error-prone          | ❌ No    |

**Why not shell scripts:**

- No idempotency (running twice causes problems)
- No error handling
- Hard to maintain
- Not self-documenting

---

### Decision: Ansible Control Node Location

**Context:**  
Ansible can run from:

1. Local developer machine (laptop)
2. Dedicated Ansible server
3. Bastion host

**Decision:**  
Run Ansible from Bastion Host.

**Architecture:**

```
Developer Laptop → SSH → Bastion (Ansible Control Node) → Backend Instances
```

**Justification:**

**Bastion as control node advantages:**

- Already has Ansible installed (from Day 6 setup)
- Direct network access to private subnets (no SSH proxying needed)
- Simpler inventory configuration
- More realistic production pattern
- Better performance (single SSH hop instead of proxy)
- Ansible key management contained within AWS

**Alternatives considered:**

| Location         | Pros                                  | Cons                                              | Selected |
| ---------------- | ------------------------------------- | ------------------------------------------------- | -------- |
| **Bastion**      | Simple, realistic, already configured | Requires Git setup                                | ✅ Yes   |
| Local machine    | Familiar workflow                     | Requires Ansible on Windows, complex SSH proxy    | ❌ No    |
| Dedicated server | Production-grade                      | Unnecessary for learning project, additional cost | ❌ No    |

**Trade-offs accepted:**

- Repository must be cloned to Bastion
- Changes committed from Bastion (or pushed from local)
- Bastion becomes slight SPF (but acceptable for QA)

**Why local machine was rejected:**

- Installing Ansible on Windows requires WSL or Git Bash with Python
- Inventory would need ProxyCommand for SSH jumping:

```ini
  ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p ec2-user@BASTION_IP"'
```

- More complex, less realistic
- Additional maintenance burden

---

### Decision: Inventory Organization

**Context:**  
Ansible requires inventory file defining managed hosts. Two formats available: INI and YAML.

**Decision:**  
Use INI format with separate files per environment.

**Implementation:**

**File structure:**

```
ansible/inventory/
├── qa.ini
└── prod.ini
```

**QA inventory:**

```ini
[backend]
backend-1 ansible_host=10.0.11.71
backend-2 ansible_host=10.0.12.244

[backend:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/movie-analyst-bastion-key
ansible_python_interpreter=/usr/bin/python3
```

**Key decisions:**

- **Private IPs:** Backend instances in private subnets
- **No ProxyCommand:** Not needed when running from Bastion
- **Python 3:** Amazon Linux 2 default (Ansible requires Python on targets)
- **Group variables:** Applied to all hosts in group

**Alternatives considered:**

| Format            | Pros                             | Cons                          | Selected |
| ----------------- | -------------------------------- | ----------------------------- | -------- |
| **INI**           | Simple, readable, standard       | Less flexible than YAML       | ✅ Yes   |
| YAML              | More features, nested structures | Overkill for simple inventory | ❌ No    |
| Dynamic inventory | Auto-discovers EC2 instances     | Complex setup, not needed     | ❌ No    |

**Why not dynamic inventory:**

- EC2 plugin requires AWS credentials and boto3
- Adds complexity without benefit (only 2 instances)
- Static inventory more predictable for learning
- Valid for production with many instances

---

### Decision: Role Structure

**Context:**  
Ansible roles organize related tasks, handlers, templates, and variables into reusable units.

**Decision:**  
Implement modular role-based organization:

```
roles/
├── common/       # Baseline configuration (all instances)
├── nodejs/       # Node.js + PM2 (backend instances)
└── nginx/        # Nginx (frontend instances)
```

**Common role responsibilities:**

- System updates and security patches
- Base tool installation (git, vim, curl, etc.)
- Timezone configuration
- NTP time synchronization
- SSH hardening
- Custom MOTD banner

**Justification:**

**Role-based advantages:**

- **Reusability:** Common role applies to frontend, backend, database
- **Maintainability:** Changes to baseline config in one place
- **Clarity:** Each role has single responsibility
- **Testing:** Roles can be tested independently
- **Portability:** Roles can be shared across projects

**Directory structure:**

```
roles/common/
├── README.md         # Role documentation
├── defaults/         # Default variables (lowest priority)
├── handlers/         # Service restart handlers
├── tasks/            # Main task list
└── templates/        # Jinja2 config templates
```

**Alternative (flat playbooks):**

```yaml
# Anti-pattern: Everything in one playbook
- name: Configure everything
  tasks:
    - yum: ...
    - copy: ...
    - service: ...
    # 100+ tasks, impossible to maintain
```

**Why roles are better:**

- Logical separation
- Can selectively apply (only nodejs to backend)
- Easier collaboration (different team members own different roles)

---

### Decision: Ansible Version and Python

**Context:**  
Encountered critical bug with Ansible 2.9 and package modules.

**Problem:**

```
The Python 2 bindings for rpm are needed for this module
```

**Root cause:**

- Bastion had Ansible 2.9 (installed via amazon-linux-extras)
- Ansible 2.9 is EOL (end of life)
- Known bugs when control node uses Python 2, targets use Python 3

**Decision:**  
Upgrade to Ansible 2.11+ using pip3.

**Implementation:**

```bash
# Remove legacy version
sudo yum remove -y ansible

# Install modern version
sudo pip3 install ansible

# Verify
ansible --version
# ansible-core 2.11.12
# python version = 3.7.16
```

**Result:**

- All package modules working correctly
- Idempotency restored
- No workarounds needed

**Lesson learned:**

- Always use supported Ansible versions (2.11+)
- Avoid EOL software (security and bug risks)
- Don't settle for workarounds (shell instead of package)
- Control node and managed nodes should use same Python major version

**Why shell workaround was rejected:**

```yaml
# This works but is WRONG:
- name: Update packages
  shell: yum update -y
```

**Problems with shell:**

- Not idempotent (always shows changed)
- No error handling
- Not declarative
- Defeats purpose of Ansible

---

### Decision: Security Hardening in Common Role

**Context:**  
SSH is the only way to access instances. Default configurations have security weaknesses.

**Decision:**  
Implement SSH hardening in common role.

**Implementation:**

**Changes to /etc/ssh/sshd_config:**

1. `PermitRootLogin no` - Disable root login
2. `PasswordAuthentication no` - Keys only (no passwords)

**Justification:**

**Disable root login:**

- Root has unlimited privileges
- Attackers target root account
- Better: Use ec2-user + sudo

**Disable password authentication:**

- Passwords vulnerable to brute force
- Keys cryptographically stronger
- Keys can be rotated without changing password on every server
- Industry standard for cloud servers

**Handler for changes:**

```yaml
- name: restart sshd
  systemd:
    name: sshd
    state: restarted
```

**Why handler:**

- SSH config changes require service restart
- Handler runs only if config actually changed
- Runs at end of playbook (not mid-execution, avoiding lockout)

**Risk mitigation:**

- Always test SSH key access BEFORE disabling passwords
- Keep current SSH session open while testing
- If locked out: Use AWS Systems Manager Session Manager as backup

---

### Decision: MOTD Custom Banner

**Context:**  
When SSHing to servers, useful to immediately see which server you're on.

**Decision:**  
Implement dynamic MOTD (Message of the Day) using Jinja2 template.

**Implementation:**

**Template:** `roles/common/templates/motd.j2`

```jinja2
=====================================
   Movie Analyst Backend Server
   Environment: {{ ansible_hostname }}
   IP: {{ ansible_default_ipv4.address }}
   Last Update: {{ ansible_date_time.iso8601 }}
=====================================

NOTICE: Unauthorized access prohibited
Managed by Ansible - Do not modify manually
```

**Variables used:**

- `ansible_hostname`: Auto-discovered during fact gathering
- `ansible_default_ipv4.address`: Primary IP address
- `ansible_date_time.iso8601`: Timestamp of last Ansible run

**Task:**

```yaml
- name: Set custom MOTD banner
  template:
    src: motd.j2
    dest: /etc/motd
    mode: "0644"
```

**Benefits:**

- Immediate server identification
- Shows when Ansible last ran
- Reminds not to make manual changes
- Professional appearance

**Alternative (static file):**

```yaml
- name: Copy static MOTD
  copy:
    content: "Movie Analyst Backend"
    dest: /etc/motd
```

**Why template is better:**

- Dynamic (shows actual hostname and IP)
- Updates automatically on each run
- More informative

---

### Decision: Tagging Strategy

**Context:**  
Playbooks can have many tasks. Sometimes you want to run subset.

**Decision:**  
Implement meaningful tags for selective execution.

**Tags implemented:**

- `packages`: Package installation and updates
- `system`: System configuration (timezone, NTP)
- `security`: Security hardening (SSH config)

**Usage examples:**

```bash
# Run only security tasks
ansible-playbook playbooks/common.yml --tags security

# Skip lengthy package updates during testing
ansible-playbook playbooks/common.yml --skip-tags packages

# Multiple tags
ansible-playbook playbooks/common.yml --tags "system,security"
```

**Benefits:**

- Faster iteration during development
- Production hotfixes (skip non-critical tasks)
- Testing specific changes
- Clearer task organization

**Best practices:**

- Use descriptive tag names
- Tag at task level, not play level
- Document available tags in role README
- Don't overuse (3-5 tags per role maximum)

---

### Cost Optimization

**Ansible-related costs:**

- **Ansible software:** Free (open source)
- **Bastion instance:** Already running (t3.micro, free tier)
- **Additional storage:** Minimal (~100MB for Ansible + roles)
- **Network transfer:** Negligible (configuration files are small)

**Total additional cost:** $0

---

### Production Considerations

**For production deployment, would implement:**

1. **Ansible Tower/AWX:**
   - Web UI for playbook execution
   - Role-based access control
   - Job scheduling
   - Audit logs

2. **Ansible Vault:**
   - Encrypt sensitive variables (passwords, API keys)
   - Encrypted at rest in Git
   - Decrypted only during playbook execution

3. **Dynamic Inventory:**
   - Auto-discover EC2 instances via AWS API
   - Tag-based filtering
   - No manual IP management

4. **Separate Ansible server:**
   - Dedicated instance (not Bastion)
   - High availability (multi-AZ)
   - Locked down (minimal access)

5. **CI/CD Integration:**
   - Ansible triggered by GitLab CI / GitHub Actions
   - Automated testing (ansible-lint, molecule)
   - Change approval workflow

**Why not implemented for learning project:**

- Adds complexity without educational value
- Increases cost
- Overkill for 2-instance environment
- Current approach demonstrates core concepts

---

## Decision: Ansible Inventory Structure and Verification

**Context:**  
When deploying to AWS with dynamic IPs, there's risk of inventory misconfiguration leading to playbooks running on wrong instances.

**Problem Encountered:**

- Terraform outputs showed Frontend IPs: 10.0.1.210, 10.0.2.22
- Terraform outputs showed Backend IPs: 10.0.11.79, 10.0.12.112
- Initial inventory had these reversed
- Ran playbooks before verification
- Result: Frontend configured on backend instances and vice versa

**Decision:**  
Implement mandatory inventory verification step before any playbook execution.

**Verification Process:**

```bash
# 1. Get IPs from Terraform
terraform output frontend_private_ips
terraform output backend_private_ips

# 2. Verify Ansible inventory matches
ansible all -m shell -a "hostname && ip addr show eth0 | grep 'inet '" -b

# 3. Expected output:
# frontend-1 should return: frontend-1-qa and 10.0.1.210
# backend-1 should return: backend-1-qa and 10.0.11.79
```

**Justification:**

- **Prevention:** Catches misconfigurations before they cause damage
- **Speed:** 30-second check saves hours of debugging
- **Confidence:** Provides certainty before running destructive operations
- **Repeatability:** Works even when IPs change between destroy/apply cycles

**Implementation:**
Add to deployment checklist:

```markdown
## Pre-Deployment Checklist

- [ ] Pull latest Terraform state: `terraform refresh`
- [ ] Verify outputs match expectations: `terraform output`
- [ ] Update Ansible inventory with correct IPs
- [ ] **Verify inventory with hostname check**
- [ ] Run Ansible playbooks
```

**Alternative Considered:**
Use Ansible dynamic inventory (aws_ec2 plugin) to auto-discover instances by tags.

**Why Rejected for This Project:**

- Added complexity for 4 instances
- Requires AWS IAM configuration
- Static inventory sufficient for learning project
- Dynamic inventory better for production with auto-scaling

**For Production:**
Would implement `aws_ec2` dynamic inventory:

```yaml
# inventory/aws_ec2.yml
plugin: aws_ec2
regions:
  - us-east-1
filters:
  tag:Environment: prod
  instance-state-name: running
keyed_groups:
  - key: tags.Role
    prefix: role
```

---

## Decision: Nginx as Reverse Proxy for Frontend

**Context:**  
Frontend Express app runs on port 3030, but users expect standard HTTP port 80.

**Problem:**

- Running Node.js directly on port 80 requires root privileges (security risk)
- Express serves static files inefficiently
- No HTTPS termination capability
- Limited request filtering/rate limiting

**Decision:**  
Use Nginx as reverse proxy in front of Express app.

**Architecture:**

```
Browser (port 80)
  ↓
Nginx (port 80)
  ↓
Express (port 3030)
```

**Nginx Configuration:**

```nginx
server {
    listen 80;
    server_name _;

    # Frontend - Proxy to React app running on PM2
    location / {
        proxy_pass http://localhost:3030;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Backend API - Proxy to ALB
    location /api/ {
        proxy_pass http://qa-movie-analyst-alb.us-east-1.elb.amazonaws.com/;
        rewrite ^/api/(.*) /$1 break;
    }
}
```

**Benefits:**

1. **Security:** Node.js runs as non-root user
2. **Performance:** Nginx handles static assets efficiently
3. **Flexibility:** Easy to add caching, rate limiting, SSL
4. **Standard:** Industry best practice (separation of concerns)
5. **SSL Ready:** Can easily add Let's Encrypt certificate

**Implementation Details:**

- Nginx managed by Ansible
- Configuration in `/etc/nginx/conf.d/movie-analyst.conf`
- Handlers ensure Nginx restarts on config changes
- PM2 manages Express app lifecycle

**Gotcha Discovered:**
Nginx doesn't auto-reload configuration. Need explicit restart:

```yaml
notify: restart nginx
```

Without restart, old configuration stays active even though new file exists.

**Alternative Considered:**
Run Express directly on port 80 with:

```bash
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/node
```

**Why Rejected:**

- Security risk (grants capability to all Node processes)
- Loses benefits of dedicated web server
- Makes SSL/caching harder to implement
- Not industry standard

---

## Decision: Manual Database Seeding vs Automated

**Context:**  
Application requires database populated with initial data (seed data for publications, reviewers, movies).

**Options Evaluated:**

### Option 1: Automated Seeding in Ansible

```yaml
- name: Run database seeds
  command: node seeds.js
  args:
    chdir: "{{ app_directory }}"
  environment:
    DB_HOST: "{{ db_endpoint }}"
    DB_PASS: "{{ db_password }}"
  become_user: "{{ app_user }}"
```

**Pros:**

- Fully automated deployment
- Repeatable
- No manual steps

**Cons:**

- Seeds would fail on re-runs (duplicate keys)
- Need idempotency logic (`INSERT IGNORE` or `ON DUPLICATE KEY UPDATE`)
- Harder to debug when things go wrong
- Risk of data corruption if seeds run unexpectedly

### Option 2: Manual Seeding (Selected)

**Implementation:**

```bash
# One-time manual execution
cd /opt/devops-rampup/movie-analyst-api
export DB_HOST=...
export DB_USER=admin
export DB_PASS='...'
export DB_NAME=movieanalyst
node seeds.js
```

**Decision Rationale:**

1. **Safety:** Won't accidentally corrupt data on re-deployment
2. **Visibility:** Developer sees exactly what data is being inserted
3. **Control:** Can choose when/if to re-seed
4. **Simplicity:** No need for idempotency logic
5. **Realistic:** Production databases aren't re-seeded automatically

**When to Automate:**
Would automate if:

- Using proper migration tool (Flyway, Liquibase, Knex)
- Migrations are idempotent by design
- Have separate environments (dev/staging/prod)
- Need frequent database resets (like in CI/CD testing)

**For Production:**
Would implement:

```sql
-- migrations/001_initial_schema.sql
CREATE TABLE IF NOT EXISTS publications (...);
CREATE TABLE IF NOT EXISTS reviewers (...);
CREATE TABLE IF NOT EXISTS movies (...);

-- migrations/002_seed_data.sql
INSERT INTO publications (...)
ON DUPLICATE KEY UPDATE name=VALUES(name);
```

With migration runner:

```bash
# Run all pending migrations
npm run migrate:up
```

---

## Decision: System Users for Application Services

**Context:**  
Need to create users to run PM2 and application processes.

**Options:**

### Option 1: Regular User

```yaml
- name: Create app user
  user:
    name: frontend
    create_home: yes
    shell: /bin/bash
```

### Option 2: System User (Selected)

```yaml
- name: Create app user
  user:
    name: frontend
    create_home: yes
    shell: /bin/bash
    system: yes # Key difference
```

**Decision Rationale:**

**System User Benefits:**

1. **Security:** UID < 1000, less likely to conflict with real users
2. **Convention:** Standard practice for service accounts
3. **Visibility:** Clearly indicates non-human user
4. **Restrictions:** Limited login capabilities by default

**How to Use System Users:**

```bash
# In Ansible playbooks
become_user: "{{ frontend_user }}"

# Manually
sudo -u frontend pm2 list

# Through PM2 systemd
sudo systemctl start pm2-frontend
```

**Gotcha Discovered:**
System users work perfectly fine with PM2 and systemd. The `sudo: unknown user` error we encountered wasn't because of `system: yes` flag - it was because the user creation task hadn't run properly due to inventory issues.

**Best Practice:**
Always use system users for application services:

```yaml
services_users:
  - { name: frontend, comment: "Frontend application user" }
  - { name: backend, comment: "Backend application user" }
  - { name: nginx, comment: "Nginx web server" }
```

**Alternative Considered:**
Use single user (ec2-user) for all applications.

**Why Rejected:**

- **Security:** All apps would share same permissions
- **Isolation:** Can't separate log files, PM2 processes
- **Debugging:** Harder to identify which process belongs to which app
- **Best Practice:** Violates principle of least privilege

---

## Cost Optimization Notes

**Current Setup Costs (Monthly):**

- 4x t3.micro instances: ~$7.50 (free tier: $0)
- 1x t3.micro bastion: ~$7.50 (free tier: $0)
- 1x ALB: ~$16
- 1x NAT Gateway: ~$32
- 1x RDS db.t3.micro: ~$15 (free tier: $0)
- Data transfer: ~$5
- **Total: ~$68/month** (or ~$0 with free tier)

**Cost Optimization Applied:**

1. **Frontend in Public Subnet:** Saved $32/month (no second NAT Gateway)
2. **t3.micro over t2.micro:** Better performance, still free tier
3. **Single NAT Gateway:** Used by both backend subnets
4. **No CloudWatch detailed monitoring:** Saved ~$7/month

**For Production:**

- Add Auto Scaling (pay only for what you use)
- Consider Reserved Instances (up to 75% discount)
- Use CloudFront for static assets (reduce bandwidth costs)
- Implement proper RDS backup strategy

## Monitoring Architecture - CloudWatch

### Decision: CloudWatch for Infrastructure Monitoring

**Context:**  
Need comprehensive monitoring and alerting for infrastructure health across EC2 instances, RDS database, and Application Load Balancer. Require visibility into performance metrics, resource utilization, and automatic alerting for anomalies.

**Decision:**  
Implement AWS CloudWatch with custom dashboards and metric-based alarms.

**Alternatives Considered:**

| Option               | Cost                     | Features                       | Integration  | Selected |
| -------------------- | ------------------------ | ------------------------------ | ------------ | -------- |
| **CloudWatch**       | ~$3-10/month             | Native AWS, dashboards, alarms | Seamless     | ✅ Yes   |
| Datadog              | ~$15/host/month          | Advanced features, APM         | Good         | ❌ No    |
| Prometheus + Grafana | ~$20/month (self-hosted) | Open source, flexible          | Manual setup | ❌ No    |
| New Relic            | ~$25/month               | Full observability             | Good         | ❌ No    |

**Justification:**

**CloudWatch advantages:**

- Native AWS integration (no agent installation required)
- Free tier: 10 custom metrics, 10 alarms, 1M API requests
- Automatic metric collection from EC2, RDS, ALB
- Built-in dashboards with pre-configured widgets
- Unified monitoring (all services in one place)
- Simple alarm configuration with SNS integration

**Why not third-party tools:**

- Project scale doesn't justify additional cost ($15-25/month vs $3-10/month)
- CloudWatch sufficient for basic monitoring needs
- Avoid managing additional infrastructure (Prometheus/Grafana servers)
- Native integration reduces configuration complexity

---

### Monitoring Module Structure

**Implementation:**

```
terraform/modules/monitoring/
├── main.tf           # Dashboards and alarms
├── variables.tf      # Monitoring configuration
├── outputs.tf        # Dashboard URLs, alarm ARNs
└── sns.tf            # Optional SNS topic for alerts
```

---

### CloudWatch Dashboards

**Decision:**  
Create unified dashboard with widgets for all infrastructure components.

**Dashboard sections:**

1. **ALB Metrics**
   - Request count
   - Target response time (average, p99)
   - HTTP 4xx/5xx error rates
   - Healthy/unhealthy target count
   - Active connection count

2. **EC2 Metrics (Frontend & Backend)**
   - CPU utilization (%)
   - Network in/out (bytes)
   - Disk read/write operations
   - Status check failures

3. **RDS Metrics**
   - CPU utilization (%)
   - Database connections count
   - Read/write IOPS
   - Free storage space
   - Replica lag (if Multi-AZ enabled in prod)

**Widget configuration:**

```hcl
# Example: ALB Request Count
widget {
  type = "metric"
  properties = {
    metrics = [
      ["AWS/ApplicationELB", "RequestCount",
       "LoadBalancer", var.alb_arn_suffix]
    ]
    period = 300  # 5 minutes
    stat   = "Sum"
    region = "us-east-1"
    title  = "ALB - Total Requests"
  }
}
```

**Benefits:**

- Single-pane-of-glass visibility
- Customizable time ranges (1h, 3h, 1d, 1w)
- Auto-refresh every 60 seconds
- Shareable URLs for team collaboration

---

### CloudWatch Alarms

**Decision:**  
Implement metric-based alarms with workspace-aware thresholds.

**Alarms configured:**

#### 1. EC2 CPU Utilization (All Instances)

```hcl
Metric: CPUUtilization
Threshold: 80% (QA), 80% (Production)
Evaluation periods: 2 consecutive periods
Period: 5 minutes
Actions: SNS notification (if enabled)
```

**Why 80% threshold:**

- Indicates potential performance degradation
- Allows time to investigate before reaching 100%
- Standard industry practice for web servers
- t3.micro instances can burst above baseline

**Created for:**

- 2 Frontend instances
- 2 Backend instances
- Total: 4 alarms

---

#### 2. RDS Database Connections

```hcl
Metric: DatabaseConnections
Threshold: 80 connections (QA), 160 connections (Production)
Evaluation periods: 2 consecutive periods
Period: 5 minutes
Actions: SNS notification (if enabled)
```

**Why connection monitoring:**

- RDS max connections = `{DBInstanceClassMemory/12582880}` (formula)
- db.t3.micro max connections ≈ 85-100
- Threshold at 80% prevents connection exhaustion
- Early warning of connection leaks in application

**Workspace-aware thresholds:**

| Workspace | Max Connections | Alarm Threshold | Percentage |
| --------- | --------------- | --------------- | ---------- |
| **qa**    | ~100            | 80              | 80%        |
| **prod**  | ~200 (Multi-AZ) | 160             | 80%        |

---

#### 3. ALB Target Health (Implicit)

**Automatic monitoring via target group health checks:**

- ALB automatically monitors target health every 30 seconds
- Unhealthy targets removed from rotation after 2 failed checks
- No additional alarm needed (built into ALB behavior)
- Visible in CloudWatch dashboard: `HealthyHostCount` metric

---

### SNS Topic for Alerts (Optional)

**Decision:**  
Create SNS topic but disable by default (cost optimization).

**Configuration:**

```hcl
variable "enable_sns_alerts" {
  default = false  # Disabled in both QA and Production
}
```

**Why disabled:**

- SNS costs: $0.50 per 1M notifications
- Email delivery: Free (first 1,000 emails)
- For learning project: Manual dashboard review sufficient
- Can enable in production if needed: `enable_sns_alerts = true`

**To enable SNS alerts:**

```hcl
# terraform/main.tf
module "monitoring" {
  # ...
  enable_sns_alerts = true
  alert_email       = "devops-team@example.com"
}
```

**SNS workflow (when enabled):**

1. CloudWatch alarm triggers (e.g., CPU > 80%)
2. SNS topic receives notification
3. Email sent to subscribed addresses
4. Recipient clicks confirmation link (first time only)
5. Future alarms arrive via email automatically

---

### Cost Analysis

**CloudWatch pricing breakdown:**

| Component           | QA Environment                        | Production Environment  |
| ------------------- | ------------------------------------- | ----------------------- |
| **Dashboards**      | $3/month (1 custom dashboard)         | $3/month                |
| **Alarms**          | Free (5 alarms, within 10 free limit) | Free (5 alarms)         |
| **Metrics**         | Free (all standard metrics)           | Free (standard metrics) |
| **API Requests**    | Free (< 1M/month)                     | Free (< 1M/month)       |
| **SNS**             | $0 (disabled)                         | $0 (disabled)           |
| **Logs (optional)** | Not implemented                       | Not implemented         |
| **Total**           | **$3/month**                          | **$3/month**            |

**Free tier benefits:**

- 10 alarms (we use 5)
- 10 metrics (we use standard AWS metrics only)
- 1M API requests
- 5GB log ingestion (not used)
- 3 dashboards (we use 1)

**Cost after free tier (first 12 months):**

- Same costs apply (CloudWatch free tier is permanent for standard metrics)
- Alarms free tier: 10 alarms always free
- Dashboards: $3/month per dashboard (always charged)

**Comparison with alternatives:**

| Monitoring Tool | Monthly Cost        | Features Used                        |
| --------------- | ------------------- | ------------------------------------ |
| **CloudWatch**  | $3                  | Dashboards, alarms, standard metrics |
| Datadog         | $30 (2 hosts × $15) | Overkill for project                 |
| New Relic       | $50                 | Overkill for project                 |

---

### Workspace Configuration Strategy

**Question examined:** Should monitoring be production-only or environment-agnostic?

**Decision:**  
Deploy monitoring in both QA and Production workspaces.

**Justification:**

**QA monitoring benefits:**

- Test alarm behavior before production deployment
- Identify performance issues during development
- Validate application resource usage patterns
- Practice incident response procedures
- Ensure monitoring configuration works correctly

**Workspace differences:**

| Aspect               | QA                             | Production            |
| -------------------- | ------------------------------ | --------------------- |
| **Dashboard**        | Created                        | Created               |
| **Alarms**           | Created                        | Created               |
| **SNS alerts**       | Disabled                       | Disabled (can enable) |
| **Metric retention** | 15 months (CloudWatch default) | 15 months             |
| **Cost**             | $3/month                       | $3/month              |

**No workspace-specific logic needed:**

- Same dashboard configuration for both environments
- Same alarm thresholds (80% CPU, 80% DB connections)
- Environment identification via resource tags
- Cost negligible ($3/month vs total budget)

**Alternative considered:**

- Production-only monitoring → Rejected because:
  - Misses opportunity to test monitoring in QA
  - Increases risk of misconfigured production alarms
  - Minimal cost savings ($3/month)
  - Violates principle of environment parity

---

### Monitoring Best Practices Implemented

**1. Metric-based alerting:**

- Thresholds based on resource capacity (80% rule)
- Multiple evaluation periods prevent false positives
- Clear alarm naming: `{environment}-{resource}-{metric}-alarm`

**2. Dashboard organization:**

- Logical grouping: ALB → EC2 → RDS
- Consistent widget sizing
- Relevant time ranges (1h default, customizable)
- Auto-refresh enabled

**3. Alarm fatigue prevention:**

- Only critical metrics alarmed (CPU, connections)
- 2 consecutive periods required (5 min × 2 = 10 min sustained issue)
- SNS disabled to avoid notification overload during testing

**4. Cost optimization:**

- Use standard metrics (free)
- No custom metrics (would cost $0.30/metric/month)
- No CloudWatch Logs ingestion (would cost $0.50/GB)
- Single consolidated dashboard ($3 vs $9 for 3 separate dashboards)

**5. Observability principles:**

- Metrics for what is happening (quantitative)
- Dashboards for visualization (trends over time)
- Alarms for actionable alerts (threshold breaches)

---

### Security Considerations

**IAM permissions required:**

- Terraform execution role needs: `cloudwatch:PutMetricAlarm`, `cloudwatch:PutDashboard`
- EC2 instances use CloudWatch agent (not implemented): Would need `cloudwatch:PutMetricData`
- SNS topic access (if enabled): `sns:Publish` for CloudWatch

**Dashboard access control:**

- Dashboard URLs are publicly accessible (with URL knowledge)
- No sensitive data exposed (only metric aggregates)
- For production: Consider restricting via IAM policies

**Alarm actions:**

- Alarms can only trigger SNS topics in same account
- SNS topic email subscriptions require confirmation
- No auto-remediation actions configured (safety measure)

---

### Future Enhancements (Not Implemented)

**Phase 1 (Current):**

- ✅ Basic dashboards
- ✅ CPU and connection alarms
- ✅ Standard AWS metrics

**Phase 2 (Production Hardening):**

- [ ] CloudWatch Logs for application logs
- [ ] Log insights queries for error tracking
- [ ] Custom metrics (application-level)
- [ ] Composite alarms (multiple conditions)

**Phase 3 (Advanced Observability):**

- [ ] X-Ray tracing for request flow
- [ ] Application Performance Monitoring (APM)
- [ ] Anomaly detection (machine learning-based)
- [ ] Auto-remediation via Lambda

**Why not implemented:**

- Project scope focuses on infrastructure basics
- Cost considerations ($5-20/month additional)
- Time constraints (2-3 days remaining)
- Sufficient for learning objectives

---

### Key Decisions Summary

1. **Monitoring tool:** CloudWatch (native AWS, cost-effective)
2. **Dashboard strategy:** Single unified dashboard for all components
3. **Alarm coverage:** CPU (EC2) and connections (RDS) only
4. **SNS alerts:** Disabled by default (can enable if needed)
5. **Workspace deployment:** Both QA and Production (testing parity)
6. **Cost target:** $3/month (within budget)
7. **Metric types:** Standard AWS metrics only (no custom metrics)

---
