# Operations Guide — coder4gov Reference Architecture

## Overview

| Component | Location | Purpose |
|---|---|---|
| Coder server | EKS (coder namespace) | Developer workspaces |
| Coder provisioner | EKS (coder namespace) | Terraform workspace lifecycle |
| Karpenter | EKS (kube-system) | Workspace node autoscaling |
| ALB Controller | EKS (lb-ctrl) | AWS Load Balancer management |
| External Secrets | EKS (external-secrets) | Secrets Manager → K8s |
| RDS PostgreSQL 15 | AWS | Coder database |

### DNS

| Subdomain | Service |
|---|---|
| `dev.coder4gov.com` | Coder |
| `*.dev.coder4gov.com` | Coder workspaces |

## Terraform vs GitOps Boundary

**Terraform** owns all AWS infrastructure (Layers 0–4):
- VPC, subnets, NAT Gateways, Route 53, ACM
- RDS, KMS, ECR, Secrets Manager
- EKS cluster, managed node groups, IRSA roles
- Karpenter, ALB Controller, External Secrets Operator

**FluxCD / GitOps** owns Kubernetes workloads:
- Coder server HelmRelease
- Coder provisioner HelmRelease
- Namespaces, secrets, Helm sources

## Day 1 — Deployment

### Step 1: Layer 0 — State Backend

```bash
cd infra/terraform/0-state
terraform init
terraform apply
```

Creates S3 bucket + DynamoDB table for Terraform state.

### Step 2: Layer 1 — Network

```bash
cd ../1-network
terraform init
terraform apply
```

Creates VPC, subnets, NAT Gateways, Route 53 zone, ACM certificates.

### Step 3: Layer 2 — Data

```bash
cd ../2-data
terraform init
terraform apply
```

Creates RDS PostgreSQL, KMS CMK, ECR repos, Secrets Manager entries.

### Step 4: Seed Secrets

```bash
cd ../../..
./scripts/seed-secrets.sh
```

Seeds the Coder enterprise license into Secrets Manager.

### Step 5: Layer 3 — EKS

```bash
cd infra/terraform/3-eks
terraform init
terraform apply
```

Creates EKS cluster, system node group, IRSA roles, StorageClass.

### Step 6: Layer 4 — Bootstrap

```bash
cd ../4-bootstrap
terraform init
terraform apply
```

Deploys Karpenter, ALB Controller, External Secrets Operator.

### Step 7: Deploy Coder

Apply FluxCD manifests from `clusters/gov-demo/` or bootstrap FluxCD to
reconcile the cluster path.

### GovCloud Migration

To deploy in GovCloud instead of commercial AWS:

1. Update `terraform.tfvars` in each layer:
   ```hcl
   aws_region    = "us-gov-west-1"
   aws_partition = "aws-us-gov"
   ```
2. Update `backend "s3"` blocks in each `providers.tf`:
   ```hcl
   region = "us-gov-west-1"
   ```
3. Update `workspace_azs` in Layer 4:
   ```hcl
   workspace_azs = ["us-gov-west-1a", "us-gov-west-1b"]
   ```
4. Re-run `terraform init -reconfigure` and `terraform apply` for each layer.

## Day 2 — Operations

### Update Coder Version

1. Edit `clusters/gov-demo/apps/coder-server/helmrelease.yaml` — update chart version
2. Edit `clusters/gov-demo/apps/coder-provisioner/helmrelease.yaml` — update chart version
3. Commit + push → FluxCD reconciles

### Add Coder Templates

1. Create template in `templates/` directory
2. Push to Coder via `coder templates push`

### Scale Workspace Nodes

Edit `infra/terraform/4-bootstrap/karpenter.tf`:
- Adjust `limits.cpu` and `limits.memory` in the NodePool
- Add/remove instance types in `workspace_instance_types` variable
- Run `terraform apply`

### Rotate Secrets

1. **RDS password**: Rotate in Secrets Manager → ExternalSecret syncs automatically
2. **Coder license**: Run `seed-secrets.sh` with new license → ExternalSecret syncs

### Upgrade EKS

1. Update `cluster_version` in `infra/terraform/3-eks/variables.tf`
2. `terraform plan` to verify add-on compatibility
3. `terraform apply` — EKS upgrade + node group rolling update

## Runbooks

### Karpenter Not Launching Nodes

1. Check Karpenter controller logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter
   ```
2. Verify NodePool exists:
   ```bash
   kubectl get nodepools
   kubectl get ec2nodeclasses
   ```
3. Check IAM permissions — Karpenter IRSA role needs EC2/SQS/IAM access
4. Check subnet tags — workload subnets need `karpenter.sh/discovery` tag

### RDS Connection Failures

1. Verify security group allows port 5432 from EKS node SG
2. Check RDS endpoint in Secrets Manager matches actual endpoint
3. Test connectivity from a pod:
   ```bash
   kubectl run -it --rm pg-test --image=postgres:15 -- \
     psql "postgresql://user:pass@endpoint:5432/coder"
   ```

### Certificate Renewal

ACM certificates auto-renew via DNS validation. If renewal fails:
1. Check Route 53 validation records exist
2. Verify ACM certificate status in AWS Console
3. Re-apply Layer 1 if records were accidentally deleted

## Security Notes

### Encryption

| Scope | Mechanism |
|---|---|
| At rest | KMS CMK (RDS, EBS, ECR, Secrets Manager, S3 state bucket) |
| In transit | TLS 1.2+ (ALB, RDS SSL, HTTPS-only) |
| Terraform state | S3 SSE-KMS + versioning |

### Network Security

- All EKS nodes in private subnets (no direct internet access)
- NAT Gateway for outbound only
- Security groups: least-privilege, VPC-scoped
- VPC Flow Logs → CloudWatch (365-day retention)

### FIPS 140-3

- AWS FIPS endpoints for all API calls
- Coder binary built with `GOFIPS140=latest`
- Workspace images: RHEL 9 UBI + `crypto-policies FIPS`
- KMS keys with automatic rotation
