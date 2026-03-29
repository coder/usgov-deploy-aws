# coder4gov — Coder on AWS GovCloud Reference Architecture

Standalone, FIPS-compliant reference architecture for deploying [Coder](https://coder.com)
on AWS (or AWS GovCloud). Single-region, multi-AZ, GitOps-ready.

Customers can fork this repo and deploy Coder without any additional
dependencies. For the full demo stack (GitLab, Keycloak, LiteLLM, monitoring,
etc.), see [coder/aws-gov-infra](https://github.com/coder/aws-gov-infra) which
composes on top of this repo via `terraform_remote_state`.

## What This Deploys

| Component | Where | Purpose |
|---|---|---|
| Coder (Premium) | EKS | Developer workspaces |
| Coder Provisioner | EKS | Terraform workspace lifecycle |
| Karpenter | EKS | Workspace node autoscaling (spot + on-demand) |
| External Secrets Operator | EKS | AWS Secrets Manager → K8s Secrets |
| ALB Controller | EKS | AWS Load Balancer ingress |
| RDS PostgreSQL 15 | AWS | Coder database (Multi-AZ, KMS-encrypted) |
| ECR | AWS | FIPS container images |
| KMS | AWS | Encryption for RDS, EBS, ECR |

## Key Design Decisions

- **FIPS everywhere** — EKS nodes use AL2023 with FIPS crypto; Coder binary
  built with `GOFIPS140=latest` (Go 1.24+ native FIPS 140-3); workspace images
  use RHEL 9 UBI with `crypto-policies FIPS`; all AWS APIs use FIPS endpoints
- **AWS managed services** — Secrets Manager, ECR, RDS multi-AZ, NAT Gateway
- **GovCloud-portable** — all config parameterized; flip `aws_region` to
  `us-gov-west-1` in tfvars, no code changes
- **Standalone** — no submodules, no dependencies on external repos.
  `aws-gov-infra` can layer on top via `terraform_remote_state`

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│ terraform apply (layers 0 → 1 → 2 → 3 → 4)                    │
│                                                                 │
│   0-state     S3 backend, DynamoDB lock                         │
│   1-network   VPC, subnets, Route 53                            │
│   2-data      RDS (coder DB only), KMS, ECR, Secrets Manager    │
│   3-eks       EKS cluster, managed node group                   │
│   4-bootstrap Karpenter, ALB controller, External Secrets       │
│                                                                 │
│   Outputs: VPC ID, subnet IDs, EKS cluster name/endpoint,      │
│            RDS endpoint, KMS key ARN, ECR repo URLs,            │
│            Karpenter role ARN, OIDC provider ARN                │
│                                                                 │
│   ✅ Deploy Coder via Flux manifests in clusters/gov-demo/      │
└─────────────────────────────────────────────────────────────────┘
```

## Repo Structure

```text
├── docs/
│   ├── ARCHITECTURE.md        # Infrastructure diagrams and design
│   ├── REQUIREMENTS.md        # Requirements (shall statements, traceability)
│   ├── OPERATIONS.md          # Day 1/Day 2 operations and runbooks
│   ├── CODER_FIPS_BUILD.md    # Build Coder binary/image with FIPS 140-3
│   └── dns-bootstrap.sh       # Verify R53 zone + request ACM wildcard cert
├── images/
│   ├── base-fips/Dockerfile   # RHEL 9 UBI + FIPS crypto + Docker CE
│   ├── desktop-fips/Dockerfile# base-fips + XFCE + KasmVNC
│   └── coder-fips/Dockerfile  # FIPS Coder server image
├── templates/
│   └── dev-codex/main.tf      # Generic dev workspace + Codex CLI
├── clusters/
│   └── gov-demo/              # FluxCD / GitOps manifests
│       ├── infrastructure/    # Namespaces, HelmRepos, ExternalSecrets
│       └── apps/              # Coder server + provisioner HelmReleases
├── scripts/
│   └── seed-secrets.sh        # Seed Coder license into Secrets Manager
└── infra/
    └── terraform/
        ├── 0-state/           # S3 backend + DynamoDB lock
        ├── 1-network/         # VPC, subnets, NAT GW, Route 53
        ├── 2-data/            # RDS, KMS, Secrets Manager, ECR
        ├── 3-eks/             # EKS cluster, node groups, IRSA
        └── 4-bootstrap/       # Karpenter + ALB Controller + External Secrets
```

## DNS

Base domain: `coder4gov.com` (AWS-registered, Route 53 authoritative)

| Subdomain | Service |
|---|---|
| `dev.coder4gov.com` | Coder |
| `*.dev.coder4gov.com` | Coder workspaces |

## Prerequisites

Before starting Terraform:

1. **DNS** — `coder4gov.com` is AWS-registered. Route 53 zone created in `1-network`
2. **Coder FIPS build** — follow `docs/CODER_FIPS_BUILD.md` to build + push to ECR
3. **FIPS images** — push `base-fips` and `desktop-fips` to ECR via GitHub Actions

## Deploy Sequence

```text
0-state → 1-network → 2-data → 3-eks → 4-bootstrap → Apply Flux manifests
```

1. `cd infra/terraform/0-state && terraform apply`
2. `cd ../1-network && terraform apply`
3. `cd ../2-data && terraform apply`
4. Run `scripts/seed-secrets.sh` to seed Coder license
5. `cd ../3-eks && terraform apply`
6. `cd ../4-bootstrap && terraform apply`
7. Apply FluxCD manifests from `clusters/gov-demo/` or bootstrap FluxCD

> **Terraform owns infrastructure. FluxCD owns application workloads.**
> See [docs/OPERATIONS.md](docs/OPERATIONS.md) for the full operations guide.

## Integration with aws-gov-infra

This repo exposes Terraform outputs that `coder/aws-gov-infra` consumes via
`terraform_remote_state` to layer on additional services:

| Output | Source Layer | Consumed By |
|---|---|---|
| `vpc_id`, `private_subnet_ids`, `public_subnet_ids` | 1-network | GitLab SGs, ALB, OpenSearch |
| `route53_zone_id` | 1-network | GitLab DNS, Keycloak DNS |
| `eks_cluster_name`, `eks_cluster_endpoint`, `eks_oidc_provider_arn` | 3-eks | Istio, FluxCD, Kyverno |
| `rds_endpoint`, `rds_port` | 2-data | Additional databases |
| `kms_key_arn` | 2-data | Encryption for additional resources |
| `karpenter_node_role_name` | 4-bootstrap | Podman EC2NodeClass |
| `ecr_repo_urls` | 2-data | Image references in Flux manifests |

## Requirements

See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the full specification.
