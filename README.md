# coder4gov — Deploy Coder on AWS with FIPS & GovCloud compliance

A forkable reference architecture for deploying
[Coder](https://coder.com) on AWS EKS in government-compliant
environments. FIPS 140-3, GovCloud-ready, no static IAM keys.

Fork this repo, set your variables, and run `make apply`. For the
full demo stack (GitLab, Keycloak, LiteLLM, monitoring), see
[coder/aws-gov-infra](https://github.com/coder/aws-gov-infra) which
layers on top via `terraform_remote_state`.

## Architecture

Five Terraform layers build the infrastructure. FluxCD deploys Coder
on top.

```text
┌─────────────────────────────────────────────────────────────────────┐
│  Terraform (layers 0 → 4)                                           │
│                                                                     │
│    0-state      S3 backend + DynamoDB lock table                    │
│    1-network    VPC, subnets, NAT GW, Route 53, ACM certs          │
│    2-data       RDS PostgreSQL 15, KMS CMK, ECR, Secrets Manager   │
│    3-eks        EKS cluster, managed node group, IRSA roles        │
│    4-bootstrap  Karpenter, ALB Controller, External Secrets        │
│                                                                     │
│  FluxCD (GitOps)                                                    │
│    clusters/gov-demo/   →  Coder server + provisioner HelmReleases │
│                                                                     │
│  Flow:  terraform apply ──► inject-outputs.sh ──► FluxCD ──► Coder │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

1. **Fork this repo.**

   ```bash
   gh repo fork coder/coder4gov --clone
   cd coder4gov
   ```

2. **Rename the Terraform backend** to point at your state resources.

   ```bash
   scripts/rename-backend.sh --project-name myproject --region us-west-2
   ```

3. **Set variables** in `infra/terraform/terraform.tfvars` (or pass
   `TFVARS=` to Make).

   ```hcl
   project_name = "myproject"
   domain_name  = "myproject.example.com"
   aws_region   = "us-west-2"
   ```

4. **Deploy all layers.**

   ```bash
   make init
   make apply
   ```

5. **Inject Terraform outputs** into FluxCD manifests.

   ```bash
   make inject-outputs
   ```

6. **Apply FluxCD manifests** from `clusters/gov-demo/` or bootstrap
   FluxCD to reconcile the cluster path.

7. **Access Coder** at `https://dev.<your-domain>`.

See [docs/OPERATIONS.md](docs/OPERATIONS.md) for the full step-by-step
walkthrough and day-2 operations.

## GovCloud Deployment

Copy the example tfvars and re-run the backend rename script:

```bash
cp infra/terraform/govcloud.tfvars.example terraform.tfvars
scripts/rename-backend.sh --project-name myproject --region us-gov-west-1
make apply TFVARS=terraform.tfvars
```

See [docs/OPERATIONS.md — Deploying to GovCloud](docs/OPERATIONS.md#deploying-to-govcloud)
for instance-type considerations and FIPS endpoint details.

## What's Included

| Component | Layer | Purpose |
|-----------|-------|---------|
| VPC + subnets | 1-network | Multi-AZ private/public networking |
| Route 53 + ACM | 1-network | DNS zone and TLS certificates |
| RDS PostgreSQL 15 | 2-data | Coder database (Multi-AZ, KMS-encrypted) |
| KMS CMK | 2-data | Encryption for RDS, EBS, ECR, Secrets Manager, S3 |
| ECR | 2-data | FIPS container image registry |
| Secrets Manager | 2-data | Coder license + RDS credentials |
| EKS cluster | 3-eks | Kubernetes control plane + system node group |
| Karpenter | 4-bootstrap | Workspace node autoscaling (spot + on-demand) |
| ALB Controller | 4-bootstrap | AWS Load Balancer ingress |
| External Secrets | 4-bootstrap | Secrets Manager → K8s Secrets sync |
| Coder server | FluxCD | Developer workspace platform |
| Coder provisioner | FluxCD | Terraform workspace lifecycle |
| FIPS images | `images/` | RHEL 9 UBI base, desktop, and Coder server |
| Workspace templates | `templates/` | Dev workspace + Codex CLI template |

## Compliance Features

- **FIPS 140-3 cryptography** — Coder built with `GOFIPS140=latest`
  (Go 1.24+); workspace images use RHEL 9 UBI `crypto-policies FIPS`;
  EKS nodes run AL2023 with FIPS crypto modules.
- **FIPS endpoints** — All AWS API calls routed through FIPS endpoints.
- **KMS CMK encryption** — RDS, EBS, ECR, Secrets Manager, and S3
  state bucket encrypted with customer-managed keys with automatic
  rotation.
- **TLS 1.2+ everywhere** — ALB, RDS SSL, HTTPS-only ingress.
- **No static IAM keys** — IRSA (IAM Roles for Service Accounts) for
  all pod-level AWS access.
- **Private compute** — All EKS nodes in private subnets; NAT Gateway
  for outbound only.
- **VPC Flow Logs** — CloudWatch with 365-day retention.
- **Terraform state encryption** — S3 SSE-KMS + versioning + DynamoDB
  locking.
- **GovCloud-portable** — Flip `aws_region` to `us-gov-west-1` in
  tfvars; no code changes required.

## Repo Structure

```text
├── docs/
│   ├── ARCHITECTURE.md          Infrastructure diagrams and design
│   ├── OPERATIONS.md            Day 1 / Day 2 operations and runbooks
│   ├── REQUIREMENTS.md          Requirements (shall statements)
│   └── CODER_FIPS_BUILD.md      Build Coder with FIPS 140-3
├── images/
│   ├── base-fips/Dockerfile     RHEL 9 UBI + FIPS crypto + Docker CE
│   ├── desktop-fips/Dockerfile  base-fips + XFCE + KasmVNC
│   └── coder-fips/Dockerfile    FIPS Coder server image
├── templates/
│   └── dev-codex/main.tf        Dev workspace + Codex CLI
├── clusters/
│   └── gov-demo/                FluxCD / GitOps manifests
│       ├── infrastructure/      Namespaces, HelmRepos, ExternalSecrets
│       └── apps/                Coder server + provisioner HelmReleases
├── scripts/
│   ├── rename-backend.sh        Rewrite backend blocks for your project
│   ├── inject-outputs.sh        Patch FluxCD manifests with TF outputs
│   └── seed-secrets.sh          Seed Coder license into Secrets Manager
└── infra/terraform/
    ├── 0-state/                 S3 backend + DynamoDB lock
    ├── 1-network/               VPC, subnets, NAT GW, Route 53
    ├── 2-data/                  RDS, KMS, Secrets Manager, ECR
    ├── 3-eks/                   EKS cluster, node groups, IRSA
    └── 4-bootstrap/             Karpenter, ALB Controller, External Secrets
```

## Customization

See [CONTRIBUTING.md](CONTRIBUTING.md) for the fork-and-rename
checklist and guidelines for contributing back upstream.

## Related

[coder/aws-gov-infra](https://github.com/coder/aws-gov-infra) — Full
platform overlay that layers GitLab, Keycloak, LiteLLM, and
observability on top of this repo via `terraform_remote_state`. Not
required for a standalone Coder deployment.

## License

Apache 2.0
