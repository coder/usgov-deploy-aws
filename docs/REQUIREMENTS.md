# Gov Demo Environment — Requirements Document

**Project:** gov.demo.coder.com
**Classification:** Unclassified — For Demo/Reference Use
**Version:** 0.2.0-DRAFT
**Date:** 2025-03-24

---

## 1. Purpose

This document defines the requirements for a demonstration environment that
mimics a sensitive government customer deployment. The environment is
GitOps-controlled, FIPS-enabled, and deploys a lean developer-platform tool
chain centered on Coder.

The environment deploys to **AWS commercial** (us-east-1 or us-west-2) by
default. All region-specific configuration is parameterized so the stack can be
repointed to **AWS GovCloud** (us-gov-west-1) with a variable change — no IaC
refactoring required.

This is a **one-SE-maintainable** environment. Scope is deliberately minimal:
only the tools needed to demo Coder + AI in a gov-flavored context. Anything
that doesn't directly serve a demo narrative is deferred.

All requirements use **shall** (mandatory), **should** (recommended), or
**may** (optional) language per RFC 2119 to enable traceability.

---

## 2. Scope Decisions

### 2.1 What's In

| Component | Where | Why |
|---|---|---|
| **Coder** (server + provisioners) | EKS | The product being demoed |
| **Karpenter** | EKS | Workspace node scaling (per ai.coder.com) |
| **LiteLLM + AI Bridge** | EKS | AI coding demo hook |
| **FluxCD** | EKS | GitOps — low maintenance once bootstrapped |
| **GitLab CE** (Omnibus) | EC2 | Git source-of-truth, OIDC provider for Coder, CI runner host |
| **coder-observability** | EKS | One Helm chart → Prometheus + Grafana + Loki, pre-wired dashboards |
| **External Secrets Operator** | EKS | Bridges AWS Secrets Manager into K8s Secrets for FluxCD |

### 2.2 What's Cut (and the replacement)

| Cut | Replaced By | Rationale |
|---|---|---|
| Vault | **AWS Secrets Manager** + External Secrets Operator | Zero ops — no unsealing, no Raft, no policy authoring |
| Keycloak | **GitLab CE built-in OIDC** | GitLab can act as an OIDC provider for Coder directly |
| Harbor | **Amazon ECR** | Native to AWS, no maintenance, FIPS endpoints available |
| Nexus OSS | **Deferred** | Only needed if artifact proxying is part of a specific demo |
| Standalone Prom/Grafana/Loki | **coder-observability chart** | Single Helm release, pre-built Coder dashboards |

### 2.3 GovCloud Portability

The following items are parameterized to enable a GovCloud pivot:

| Parameter | Commercial Default | GovCloud Override |
|---|---|---|
| `aws_region` | `us-east-1` | `us-gov-west-1` |
| `aws_partition` | `aws` | `aws-us-gov` |
| `use_fips_endpoints` | `true` | `true` |
| `ami_type` | Bottlerocket FIPS | Bottlerocket FIPS |
| `acm_domain` | `gov.demo.coder.com` | same or customer domain |
| `ecr_registry` | `<account>.dkr.ecr.us-east-1.amazonaws.com` | `<account>.dkr.ecr.us-gov-west-1.amazonaws.com` |

No code changes — only `terraform.tfvars` changes.

---

## 3. Trade Study: FluxCD vs ArgoCD

| Criterion | FluxCD | ArgoCD |
|---|---|---|
| Security posture | Pull-based, no UI attack surface, K8s RBAC-native | Built-in Web UI widens attack surface |
| FIPS / compliance fit | Security-first, no external credential exposure | Requires extra hardening for dashboard |
| Modularity | Controller-per-concern (Source, Kustomize, Helm, Notification) | Monolithic install with optional components |
| Git-native RBAC | Inherits Git provider permissions — ideal with self-hosted GitLab | Separate RBAC system in-cluster |
| Maintenance burden | Low — set and forget after bootstrap | Medium — UI, Redis, app-of-apps pattern |
| Bootstrap | `flux bootstrap` CLI or Terraform provider | `kubectl apply` + ArgoCD CLI |

**Decision: FluxCD**

Rationale:
- Minimal attack surface and maintenance burden — critical for a one-SE env.
- Flux Terraform provider enables bootstrap-as-code alongside the EKS cluster.
- Git-native RBAC aligns with GitLab as source-of-truth.
- ControlPlane Enterprise for FluxCD available on AWS Marketplace if needed later.

---

## 4. Architecture Overview

```
┌───────────────────────────────────────────────────────────────┐
│              AWS Commercial (us-east-1) [GovCloud-portable]   │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                          VPC                             │  │
│  │                                                         │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │            EKS Cluster (FIPS-enabled)              │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌───────────┐ ┌───────────┐ ┌────────────────┐  │  │  │
│  │  │  │  Coder    │ │  LiteLLM  │ │  FluxCD        │  │  │  │
│  │  │  │  Server   │ │  (AI GW)  │ │  Controllers   │  │  │  │
│  │  │  └───────────┘ └───────────┘ └────────────────┘  │  │  │
│  │  │  ┌───────────┐ ┌───────────┐ ┌────────────────┐  │  │  │
│  │  │  │ ExtSecrets│ │ Prom/Graf │ │  Loki          │  │  │  │
│  │  │  │ Operator  │ │ /Loki     │ │  (S3 backend)  │  │  │  │
│  │  │  └───────────┘ └───────────┘ └────────────────┘  │  │  │
│  │  │  ┌─────────────────────────────────────────────┐  │  │  │
│  │  │  │     Karpenter (Workspace Node Scaling)       │  │  │  │
│  │  │  └─────────────────────────────────────────────┘  │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌──────────────┐  ┌────────────┐  ┌────────────────┐  │  │
│  │  │  GitLab CE   │  │ RDS PG 15  │  │  ECR           │  │  │
│  │  │  (EC2)       │  │ (Coder DB) │  │  (images)      │  │  │
│  │  └──────────────┘  └────────────┘  └────────────────┘  │  │
│  │                                                         │  │
│  │  ┌──────────────┐  ┌────────────┐  ┌────────────────┐  │  │
│  │  │ Secrets Mgr  │  │  S3        │  │  KMS           │  │  │
│  │  │              │  │ (logs,     │  │ (FIPS 140-3)   │  │  │
│  │  └──────────────┘  │  backups)  │  └────────────────┘  │  │
│  │                    └────────────┘                       │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  GitOps:  GitLab CE ──► FluxCD ──► EKS Cluster               │
└───────────────────────────────────────────────────────────────┘
```

**Total things to keep alive:** EKS cluster (4 Helm charts) + 1 EC2 instance (GitLab) + managed AWS services.

---

## 5. Requirements

### 5.1 Infrastructure — AWS

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| INFRA-001 | The environment **shall** deploy to AWS commercial by default (us-east-1 or us-west-2). | Must | |
| INFRA-002 | All region-specific configuration (region, partition, AMI IDs, endpoint URLs) **shall** be parameterized to enable redeployment to AWS GovCloud with only variable changes. | Must | |
| INFRA-003 | All AWS API calls **shall** use FIPS-validated endpoints (`AWS_USE_FIPS_ENDPOINT=true`). | Must | Available in commercial us-east/west regions |
| INFRA-004 | All data at rest **shall** be encrypted using AWS KMS (SSE-KMS). | Must | KMS HSMs are FIPS 140-3 L3 certified in all regions |
| INFRA-005 | All data in transit **shall** use TLS 1.2+ with FIPS-validated cryptographic modules. | Must | |
| INFRA-006 | Infrastructure **shall** be defined as code using Terraform, stored in the gov.demo.coder.com repository. | Must | |
| INFRA-007 | The VPC **shall** use private subnets for all compute with NAT (fck-nat or AWS NAT GW) for outbound. | Must | Per ai.coder.com pattern |
| INFRA-008 | The VPC **shall** span at least 2 Availability Zones. | Must | |
| INFRA-009 | All security groups **shall** follow least-privilege — only required ports, source-scoped to VPC CIDR or specific SGs. | Must | |
| INFRA-010 | Route 53 **shall** be used for DNS with ACM-provisioned TLS certificates. | Must | |
| INFRA-011 | Elastic IPs **should** be allocated for stable ingress (Coder, GitLab, Grafana). | Should | |
| INFRA-012 | Terraform state **shall** be stored in S3 with DynamoDB locking, encrypted via KMS. | Must | |

### 5.2 EKS Cluster

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| EKS-001 | The EKS cluster **shall** run Kubernetes 1.30+. | Must | |
| EKS-002 | EKS managed node group **shall** use Bottlerocket FIPS AMIs. | Must | FIPS 140-3 validated crypto, FIPS endpoints by default |
| EKS-003 | Managed add-ons **shall** include: CoreDNS, kube-proxy, vpc-cni, EBS CSI driver. | Must | |
| EKS-004 | The API server endpoint **shall** be private-only or dual with public access restricted to known CIDRs. | Must | |
| EKS-005 | All workload IAM **shall** use IRSA via the cluster OIDC provider. No static IAM keys in-cluster. | Must | |
| EKS-006 | Audit logging **shall** be enabled (api, audit, authenticator, controllerManager, scheduler) → CloudWatch. | Must | |
| EKS-007 | A "system" managed node group **shall** run platform workloads (FluxCD, Karpenter, monitoring). | Must | |
| EKS-008 | Default StorageClass **shall** be EBS CSI gp3, encrypted, `WaitForFirstConsumer`. | Must | |

### 5.3 Karpenter

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| KARP-001 | Karpenter **shall** be deployed via Helm into `karpenter` namespace, 2 replicas across AZs. | Must | Per ai.coder.com |
| KARP-002 | Karpenter controller pods **shall** be pinned to the system node group via node affinity. | Must | |
| KARP-003 | At least one EC2NodeClass **shall** be defined for workspace nodes (≥200 GiB gp3 root). | Must | |
| KARP-004 | At least one NodePool **shall** support spot + on-demand capacity types. | Must | |
| KARP-005 | Spot termination handling **shall** be enabled (SQS + EventBridge). | Must | |
| KARP-006 | NodePools **should** use `WhenEmpty` consolidation with configurable TTL. | Should | |
| KARP-007 | An image-prefetch DaemonSet **should** warm workspace base images on new nodes. | Should | |
| KARP-008 | EC2NodeClass **shall** discover subnets/SGs via `karpenter.sh/discovery` tags. | Must | |

### 5.4 FluxCD

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| FLUX-001 | FluxCD **shall** be the sole GitOps engine. | Must | |
| FLUX-002 | FluxCD **shall** be bootstrapped via the Flux Terraform provider targeting the GitLab CE instance. | Must | |
| FLUX-003 | The source-of-truth repository **shall** be gov.demo.coder.com on the self-hosted GitLab CE. | Must | Initial bootstrap from GitHub, then migrate source |
| FLUX-004 | Controllers **shall** include: source-controller, kustomize-controller, helm-controller, notification-controller. | Must | |
| FLUX-005 | Kustomizations **shall** use structured layout: `clusters/<name>/`, `infrastructure/`, `apps/`. | Must | |
| FLUX-006 | Reconciliation interval **shall** be ≤5 minutes. | Must | |
| FLUX-007 | Dependency ordering (`dependsOn`) **shall** enforce infrastructure-before-apps. | Must | |
| FLUX-008 | Git auth **shall** use SSH keys stored as K8s Secrets. | Must | |
| FLUX-009 | Bootstrap **shall** be automated within the Terraform infrastructure code. | Must | |

### 5.5 Coder

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| CDR-001 | Coder **shall** be deployed on EKS via the official Helm chart. | Must | |
| CDR-002 | Coder **shall** be exposed via AWS NLB with TLS termination (ACM). | Must | |
| CDR-003 | Coder **shall** use RDS PostgreSQL 15+ as its database. | Must | |
| CDR-004 | Coder **shall** authenticate users via GitLab CE OIDC. | Must | GitLab as IdP — no Keycloak needed |
| CDR-005 | Coder workspaces **shall** schedule on Karpenter-managed NodePools. | Must | |
| CDR-006 | Pod topology spread **should** distribute across AZs. | Should | |
| CDR-007 | Provisioners **shall** use IRSA for AWS access. | Must | |
| CDR-008 | Workspace templates **shall** be stored in GitLab CE, managed via Terraform. | Must | |
| CDR-009 | AI Bridge **shall** be enabled. | Must | See §5.6 |
| CDR-010 | The `coder-observability` chart **shall** be deployed for monitoring. | Must | |
| CDR-011 | Resource requests **shall** be ≥1000m CPU / 2Gi memory per replica. | Must | |
| CDR-012 | Coder **should** support both K8s and EC2 workspace templates. | Should | |

### 5.6 AI Bridge + LiteLLM

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| AI-001 | AI Bridge **shall** be enabled to proxy requests from AI coding tools (Claude Code, Cursor, etc.). | Must | |
| AI-002 | LiteLLM **shall** be deployed on EKS via Helm as the upstream AI gateway. | Must | |
| AI-003 | LiteLLM **shall** integrate with AWS Bedrock via IRSA. | Must | No static keys |
| AI-004 | LiteLLM **shall** autoscale (min 1, max 5, 80% CPU target). | Must | |
| AI-005 | LiteLLM **shall** use PostgreSQL (RDS or standalone) for API key/usage tracking. | Must | |
| AI-006 | AI Bridge **shall** support Anthropic-compatible and OpenAI-compatible endpoints. | Must | |
| AI-007 | AI Bridge **shall** record token usage and request metadata. | Must | |
| AI-008 | LiteLLM model config **shall** be managed via ConfigMap reconciled by FluxCD. | Must | |

### 5.7 GitLab CE

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| GL-001 | GitLab CE **shall** be deployed on EC2 via Omnibus. | Must | |
| GL-002 | The EC2 instance **shall** run Amazon Linux 2023 or RHEL 9 with FIPS kernel mode. | Must | |
| GL-003 | GitLab **shall** use the bundled PostgreSQL and Redis (single-instance demo). | Must | Simplicity — no RDS/ElastiCache overhead for demo |
| GL-004 | GitLab **shall** use S3 for object storage (LFS, artifacts, backups). | Must | |
| GL-005 | GitLab **shall** be fronted by an NLB with TLS via ACM. | Must | |
| GL-006 | GitLab **shall** serve as Git source-of-truth for all FluxCD and Coder template repos. | Must | |
| GL-007 | GitLab **shall** act as the OIDC provider for Coder authentication. | Must | |
| GL-008 | GitLab backups **shall** run daily to S3 with 30-day retention. | Must | |
| GL-009 | GitLab host OS **should** be hardened per DISA STIG (best-effort). | Should | |
| GL-010 | GitLab **should** be in an ASG (min 1, max 1) for self-healing on instance failure. | Should | |

### 5.8 Secrets Management

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| SEC-SM-001 | **AWS Secrets Manager** **shall** store all sensitive values (DB passwords, API keys, OAuth secrets). | Must | Zero-ops replacement for Vault |
| SEC-SM-002 | The **External Secrets Operator** **shall** be deployed on EKS to sync Secrets Manager entries into K8s Secrets. | Must | |
| SEC-SM-003 | No secrets **shall** be stored in plain text in Git. All secrets **shall** be referenced via ExternalSecret CRs. | Must | |
| SEC-SM-004 | Secrets Manager **shall** use KMS encryption (default or CMK). | Must | |

### 5.9 Container Registry

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| REG-001 | **Amazon ECR** **shall** be the container registry for workspace images and CI-built images. | Must | Zero-ops, FIPS endpoints available |
| REG-002 | ECR repositories **shall** have image scanning enabled (basic or enhanced). | Must | |
| REG-003 | ECR lifecycle policies **should** retain only the last 30 tagged images per repo. | Should | Cost control |
| REG-004 | Coder workspace templates and GitLab CI **shall** push/pull from ECR. | Must | |

### 5.10 Observability

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| OBS-001 | The `coder-observability` Helm chart **shall** be deployed, providing Prometheus + Grafana + Loki. | Must | Single Helm release — pre-wired Coder dashboards |
| OBS-002 | Loki **shall** use S3 for log storage. | Must | |
| OBS-003 | Grafana Agent **shall** run as a DaemonSet on all nodes (including Karpenter-managed). | Must | |
| OBS-004 | Grafana **should** be exposed via NLB with TLS for demo access. | Should | |
| OBS-005 | Grafana **should** use a separate RDS PostgreSQL instance or SQLite for its own state. | Should | SQLite fine for demo |

### 5.11 Security & Compliance

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| SEC-001 | All cryptographic operations **shall** use FIPS 140-2/140-3 validated modules. | Must | |
| SEC-002 | AWS KMS **shall** be used for all encryption key management. | Must | |
| SEC-003 | All inter-service communication **shall** use TLS 1.2+. | Must | |
| SEC-004 | No long-lived IAM access keys in-cluster; IRSA only. | Must | |
| SEC-005 | CloudTrail **shall** be enabled. | Must | |
| SEC-006 | Container images **should** be pulled from ECR or verified upstream sources. | Should | |
| SEC-007 | NetworkPolicies **should** restrict pod-to-pod traffic to required paths. | Should | |
| SEC-008 | EC2 host OS **should** be STIG-hardened (best-effort). | Should | |
| SEC-009 | EKS nodes **should** use Bottlerocket FIPS AMIs (minimal, immutable). | Should | |

### 5.12 Bootstrap & GitOps Workflow

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-001 | EKS **shall** be provisioned via Terraform before FluxCD bootstrap. | Must | |
| BOOT-002 | FluxCD bootstrap **shall** be a Terraform resource (`flux_bootstrap_git`). | Must | |
| BOOT-003 | Bootstrap **shall** install Flux and configure reconciliation from GitLab CE. | Must | |
| BOOT-004 | The repository **shall** use the following structure: | Must | |

```
gov.demo.coder.com/
├── docs/
│   └── REQUIREMENTS.md
├── infra/
│   └── terraform/
│       ├── 1-network/            # VPC, subnets, NAT, Route 53
│       ├── 2-data/               # RDS, S3, KMS, Secrets Manager, ECR
│       ├── 3-eks/                # EKS cluster, node groups, IRSA roles
│       ├── 4-bootstrap/          # FluxCD bootstrap, Karpenter
│       └── 5-gitlab/             # GitLab CE EC2 instance
├── clusters/
│   └── gov-demo/
│       ├── flux-system/          # FluxCD self-managed manifests
│       ├── infrastructure/       # CRDs, namespaces, sources
│       │   ├── sources/
│       │   ├── karpenter/
│       │   ├── external-secrets/
│       │   └── kustomization.yaml
│       └── apps/
│           ├── coder/
│           ├── litellm/
│           ├── monitoring/
│           └── kustomization.yaml
└── templates/
    ├── kubernetes-claude/
    ├── aws-linux/
    └── aws-devcontainer/
```

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-005 | Infrastructure **shall** reconcile before apps (via `dependsOn`). | Must | |
| BOOT-006 | Deploy sequence: Network → Data → EKS → FluxCD → Karpenter → Coder + LiteLLM. | Must | |
| BOOT-007 | All Helm chart versions **shall** be pinned. | Must | |

---

## 6. Requirement Traceability Matrix

| Req ID | Category | Traces To |
|---|---|---|
| INFRA-001 – INFRA-012 | AWS Infrastructure | NIST SP 800-53, FIPS 140-3 |
| EKS-001 – EKS-008 | EKS Cluster | CIS EKS Benchmark, ai.coder.com |
| KARP-001 – KARP-008 | Karpenter | ai.coder.com reference |
| FLUX-001 – FLUX-009 | FluxCD | Trade Study §3, FluxCD best practices |
| CDR-001 – CDR-012 | Coder | ai.coder.com, Coder docs |
| AI-001 – AI-008 | AI Bridge / LiteLLM | ai.coder.com, Coder AI Bridge docs |
| GL-001 – GL-010 | GitLab CE | GitLab AWS reference arch |
| SEC-SM-001 – SEC-SM-004 | Secrets Management | AWS Secrets Manager docs |
| REG-001 – REG-004 | Container Registry | ECR docs |
| OBS-001 – OBS-005 | Observability | ai.coder.com |
| SEC-001 – SEC-009 | Security & Compliance | FIPS 140-2/3, DISA STIG |
| BOOT-001 – BOOT-007 | Bootstrap | FluxCD docs, Terraform Flux provider |

---

## 7. Open Items

| # | Item | Status |
|---|---|---|
| 1 | Commercial region: us-east-1 vs us-west-2 | Open |
| 2 | Domain name (e.g., `gov.demo.coder.com`) | Open |
| 3 | Bedrock model selection (Claude Sonnet/Opus, Nova) | Open |
| 4 | Coder license tier: Enterprise vs OSS | Open |
| 5 | GitLab CI runner strategy: shell executor on EC2, or K8s executor on EKS | Open |
| 6 | NAT strategy: fck-nat (cheap) vs AWS NAT Gateway (zero-ops) | Open |
| 7 | FluxCD: OSS vs ControlPlane Enterprise (AWS Marketplace) | Open |
