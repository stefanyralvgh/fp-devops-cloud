# Technical Decisions - DevOps Final Project

**Project:** Cloud Migration with Terraform & Ansible  
**Cloud Provider:** AWS  
**Environments:** QA, Production  
**Last Updated:** January 7, 2026

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

## Terraform Configuration - Day 2

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
