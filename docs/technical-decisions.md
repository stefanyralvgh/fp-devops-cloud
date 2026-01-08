# Technical Decisions - DevOps Final Project

**Project:** Cloud Migration with Terraform & Ansible  
**Cloud Provider:** AWS  
**Environments:** QA, Production  
**Last Updated:** January 8, 2026

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

## References

- [Terraform Backend Configuration - HashiCorp](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [Managing Terraform State in AWS - AWS DevOps Blog](https://aws.amazon.com/blogs/devops/best-practices-for-managing-terraform-state-files-in-aws-ci-cd-pipeline/)

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
