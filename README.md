# coder4gov.com

GovCloud-flavored demo environment for [Coder](https://coder.com). Single-region
(us-west-2), multi-AZ, FIPS-enabled, GitOps-controlled via FluxCD.

**Status:** All Terraform layers written (0–5). FluxCD manifests complete. Ready for deployment.

## What This Deploys

| Component | Where | Purpose |
|---|---|---|
| Coder (Premium + AI) | EKS | Developer workspaces, AI Bridge |
| LiteLLM | EKS | AI gateway → Bedrock (Claude), OpenAI, Gemini |
| Karpenter | EKS | Workspace node autoscaling (spot + on-demand) |
| FluxCD (OSS) | EKS | GitOps reconciliation from GitLab CE |
| Istio (sidecar) | EKS | mTLS on all Coder east-west traffic |
| coder-observability | EKS | Prometheus + Grafana + Loki |
| Keycloak | EKS | Central SSO (OIDC) for Coder, GitLab, Grafana |
| External Secrets Operator | EKS | AWS Secrets Manager → K8s Secrets |
| GitLab CE + Docker Runner | EC2 (m7a.2xlarge) | Git source-of-truth, OIDC IdP, CI/CD |

## Key Design Decisions

- **FIPS everywhere** — EKS nodes use Bottlerocket FIPS AMIs; Coder binary built
  with `GOFIPS140=latest` (Go 1.24+ native FIPS 140-3); workspace images use
  RHEL 9 UBI with `crypto-policies FIPS`; all AWS APIs use FIPS endpoints
- **FluxCD over ArgoCD** — pull-based, no UI attack surface, Git-native RBAC
- **Istio mTLS** — STRICT PeerAuthentication on Coder/LiteLLM namespaces
- **Keycloak as central SSO** — OIDC for Coder, GitLab, Grafana; optional MFA/PIV
- **AWS managed services** — Secrets Manager (not Vault), ECR (not Harbor),
  NAT Gateway (not fck-nat), RDS multi-AZ
- **GovCloud-portable** — all config parameterized; flip `aws_region` to
  `us-gov-west-1` in tfvars, no code changes

## Architecture

```mermaid
graph TB
    DNS["Route 53<br/>coder4gov.com"]

    subgraph VPC["us-west-2 · VPC · multi-AZ"]
        subgraph EKS["EKS: gov-demo"]
            C[Coder coderd] --- P[Coder provisioner]
            L[LiteLLM] --- F[FluxCD]
            KC[Keycloak SSO] --- I[Istio mTLS]
            O[coder-observability] --- ESO[Ext Secrets]
            ESO[Ext Secrets] --- K[Karpenter]
        end
        GL[GitLab CE · EC2]
        RDS[(RDS PG 15)]
        ECR[ECR]
        S3[(S3)]
    end

    AWS[Secrets Mgr · KMS]

    DNS --> C & GL & O & KC
    KC -- OIDC --> C & GL & O
    GL -- GitOps --> F --> EKS
    C & L --> RDS
    ESO --> AWS
    O --> S3
```

## Repo Structure

```text
├── docs/
│   ├── REQUIREMENTS.md        # Full requirements (shall statements, traceability)
│   ├── BEDROCK_SETUP.md       # Enable Claude models in Bedrock console
│   ├── CODER_FIPS_BUILD.md    # Build Coder binary/image with FIPS 140-3
│   └── dns-bootstrap.sh      # Verify R53 zone + request ACM wildcard cert
├── images/
│   ├── base-fips/Dockerfile   # RHEL 9 UBI + FIPS crypto + Docker CE
│   ├── desktop-fips/Dockerfile# base-fips + XFCE + KasmVNC
│   └── build.gitlab-ci.yml    # GitLab CI → ECR pipeline
├── templates/
│   └── dev-codex/main.tf      # Generic dev workspace + Codex CLI
├── clusters/
│   └── gov-demo/              # FluxCD kustomizations (Day 2 — GitOps)
│       ├── flux-system/
│       ├── infrastructure/    # Namespaces, HelmRepos, ExternalSecrets
│       └── apps/              # Coder, LiteLLM, Keycloak, monitoring
└── infra/
    └── terraform/
        ├── 0-state/           # S3 backend + DynamoDB lock
        ├── 1-network/         # VPC, subnets, NAT GW, Route 53
        ├── 2-data/            # RDS, S3, KMS, Secrets Manager, ECR
        ├── 3-eks/             # EKS cluster, node groups, IRSA
        ├── 4-bootstrap/       # FluxCD + Karpenter + Istio
        └── 5-gitlab/          # GitLab CE EC2 + Docker Runner
```

## DNS

Base domain: `coder4gov.com` (AWS-registered, Route 53 authoritative)

| Subdomain | Service |
|---|---|
| `dev.coder4gov.com` | Coder |
| `*.dev.coder4gov.com` | Coder workspaces |
| `gitlab.coder4gov.com` | GitLab CE |
| `sso.coder4gov.com` | Keycloak SSO |
| `grafana.dev.coder4gov.com` | Grafana |

## AI Models (via LiteLLM)

| Provider | Models | Auth |
|---|---|---|
| AWS Bedrock | Claude Sonnet 4.6, Opus 4.6, Haiku 4.5 | IRSA (no API key) |
| OpenAI (direct) | GPT-5.4, GPT-5.3-Codex, GPT-5.4-mini | API key in Secrets Manager |
| Google Gemini | Gemini 3.1 Pro, Gemini 3 Flash | API key in Secrets Manager |

## Prerequisites

Before starting Terraform:

1. **DNS** — `coder4gov.com` is AWS-registered. Route 53 zone created in `1-network`. No delegation needed.
2. **Bedrock models** — follow `docs/BEDROCK_SETUP.md` to enable Anthropic models
3. **API keys** — store OpenAI + Gemini keys in AWS Secrets Manager
4. **Coder FIPS build** — follow `docs/CODER_FIPS_BUILD.md` to build + push to ECR
5. **FIPS images** — push `base-fips` and `desktop-fips` to ECR via `images/build.gitlab-ci.yml`

## Deploy Sequence

```mermaid
flowchart LR
    A[0-state] --> B[1-network] --> C[2-data] --> D[3-eks] --> E["4-bootstrap<br/>(flux disabled)"] --> F[5-gitlab] --> G["4-bootstrap<br/>(flux enabled)"] --> H["FluxCD reconciles<br/>clusters/gov-demo/"]
    style A fill:#e1f5fe
    style B fill:#e1f5fe
    style C fill:#e1f5fe
    style D fill:#e1f5fe
    style E fill:#e1f5fe
    style F fill:#e1f5fe
    style G fill:#fff3e0
    style H fill:#e8f5e9
```

> **Terraform owns infrastructure. FluxCD owns application workloads.**
> See [docs/OPERATIONS.md](docs/OPERATIONS.md) for the full operations guide
> including the Terraform↔GitOps boundary, day 1/day 2 procedures, and runbooks.

## Requirements

See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the full specification
(~100 shall/should statements across 15 categories with traceability matrix).
