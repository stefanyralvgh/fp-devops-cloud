# Technical Decisions - DevOps Final Project

**Project:** Cloud Migration with Terraform & Ansible  
**Cloud Provider:** AWS  
**Environments:** QA, Production  
**Last Updated:** January 6, 2026

---

## Infrastructure as Code Strategy

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

**Justification:**

- **Collaboration:** Prevents team members from stepping on each other's work
- **Durability:** S3 provides 99.999999999% durability
- **Versioning:** Enables rollback if state corruption occurs
- **Security:** Encryption and access controls protect sensitive data
- **Cost:** Both services fall within AWS free tier limits for project scope

**Cost Analysis:**

```
DynamoDB Free Tier: 1M writes + 2.5M reads/month
Estimated Project Usage: ~500 operations total
Projected Cost: $0.00

S3 Free Tier: 5GB storage + 20,000 GET requests
Estimated State Size: <10MB
Projected Cost: $0.00
```

**Alternative Considered:**  
Local state management was rejected due to collaboration requirements and lack of locking mechanism.

---

Upcoming cost considerations for evaluator review:

- **NAT Gateway:** Required for private subnet internet access (~$32/month, NOT free tier)
  - Will justify in subsequent decision log when implementing networking module
- **EC2/RDS:** Will use t2.micro/t3.micro to stay within 750 hours/month free tier

---

## References

- [Terraform Backend Configuration - HashiCorp](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [Terraform Workspaces - HashiCorp](https://developer.hashicorp.com/terraform/cli/workspaces)
- [Managing Terraform State in AWS - AWS DevOps Blog](https://aws.amazon.com/blogs/devops/best-practices-for-managing-terraform-state-files-in-aws-ci-cd-pipeline/)

---

## Decision Log Timeline

- **Day 1 (Jan 6):** Backend strategy, environment separation, repository structure
- **Day 2+:** Infrastructure module decisions (pending)

---
