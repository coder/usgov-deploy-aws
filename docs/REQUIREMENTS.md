# Gov Demo Environment — Requirements Document

**Project:** gov.demo.coder.com
**Classification:** Unclassified — For Demo/Reference Use
**Version:** 0.3.0-DRAFT
**Date:** 2025-03-24

---

## 1. Purpose

This document defines the requirements for a two-region demonstration
environment that mimics a sensitive government customer deployment. The
environment is GitOps-controlled, FIPS-enabled, and deploys a lean
developer-platform tool chain centered on Coder.

This is a **one-SE-maintainable** environment. Scope is deliberately minimal:
only the tools needed to demo Coder + AI in a gov-flavored context.

All requirements use **shall** (mandatory), **should** (recommended), or
**may** (optional) language per RFC 2119 to enable traceability.

---

## 2. Multi-Region Topology

```
                         ┌──────────────────────────┐
                         │       Route 53 DNS        │
                         │  gov.demo.coder.com       │
                         │  *.gov.demo.coder.com     │
                         │  gitlab.gov.demo.coder.com│
                         └────────┬─────────┬────────┘
                                  │         │
              ┌───────────────────┘         └──────────────────┐
              ▼                                                ▼
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│       us-west-2 (PRIMARY)       │    │       us-east-1 (SATELLITE)     │
│                                 │    │                                 │
│  EKS Cluster: gov-demo-west    │    │  EKS Cluster: gov-demo-east    │
│  ┌───────────────────────────┐  │    │  ┌───────────────────────────┐  │
│  │ Coder Control Plane       │  │    │  │ Coder Workspace Proxy     │  │
│  │ External Provisioners     │──┼────┼──│ External Provisioners     │  │
│  │ LiteLLM (AI Gateway)      │  │    │  │ Karpenter                 │  │
│  │ Karpenter                 │  │    │  │ FluxCD                    │  │
│  │ FluxCD                    │  │    │  │ Grafana Agent (DaemonSet) │  │
│  │ coder-observability       │  │    │  └───────────────────────────┘  │
│  │ External Secrets Operator │  │    │                                 │
│  └───────────────────────────┘  │    │  Workspace nodes (Karpenter)   │
│                                 │    │                                 │
│  Workspace nodes (Karpenter)   │    │  ECR (us-east-1)               │
│                                 │    │  S3 (logs)                     │
│  GitLab CE (EC2)               │    │  Secrets Manager               │
│    ├─ OIDC provider            │    │  KMS                           │
│    ├─ Git source-of-truth      │    └─────────────────────────────────┘
│    └─ GitLab Runner (shell)    │
│                                 │
│  RDS PostgreSQL 15 (Multi-AZ)  │
│  ECR (us-west-2)               │
│  S3 (backups, logs, Loki)      │
│  Secrets Manager               │
│  KMS                           │
└─────────────────────────────────┘
```

### 2.1 Region Role Summary

| Component | us-west-2 | us-east-1 |
|---|---|---|
| Coder control plane (coderd) | ✅ | — |
| Coder workspace proxy | — | ✅ |
| External provisioners | ✅ | ✅ |
| Karpenter (workspace nodes) | ✅ | ✅ |
| LiteLLM / AI Bridge | ✅ | — |
| FluxCD | ✅ (primary) | ✅ (satellite) |
| coder-observability | ✅ | — |
| Grafana Agent | ✅ | ✅ |
| External Secrets Operator | ✅ | ✅ |
| GitLab CE (EC2) | ✅ | — |
| RDS PostgreSQL (multi-AZ) | ✅ | — |
| ECR | ✅ | ✅ (replicated or cross-region pull) |

### 2.2 GovCloud Portability

All region-specific config is parameterized. To redeploy to GovCloud:

| Parameter | Commercial Default | GovCloud Override |
|---|---|---|
| `primary_region` | `us-west-2` | `us-gov-west-1` |
| `satellite_region` | `us-east-1` | `us-gov-east-1` |
| `aws_partition` | `aws` | `aws-us-gov` |
| `use_fips_endpoints` | `true` | `true` |

No code changes — only `terraform.tfvars`.

---

## 3. Scope Decisions

### 3.1 What's In

| Component | Where | Why |
|---|---|---|
| **Coder** (control plane + proxy + provisioners) | EKS (both regions) | The product being demoed |
| **Karpenter** | EKS (both regions) | Workspace node scaling |
| **LiteLLM + AI Bridge** | EKS (us-west-2) | AI coding demo hook |
| **FluxCD** | EKS (both regions) | GitOps — low maintenance once bootstrapped |
| **GitLab CE** (Omnibus) | EC2 (us-west-2) | Git source-of-truth, OIDC provider, CI runner |
| **GitLab Runner** | Shell executor on GitLab EC2 | Simplest option — no extra infra |
| **coder-observability** | EKS (us-west-2) | One Helm chart → Prometheus + Grafana + Loki |
| **External Secrets Operator** | EKS (both regions) | Bridges AWS Secrets Manager → K8s Secrets |

### 3.2 What's Cut

| Cut | Replaced By | Rationale |
|---|---|---|
| Vault | **AWS Secrets Manager** + ESO | Zero ops |
| Keycloak | **GitLab CE built-in OIDC** | One less service |
| Harbor | **Amazon ECR** | Native, zero maintenance |
| Nexus OSS | **Deferred** | Add only if a demo calls for it |

---

## 4. Trade Study: FluxCD vs ArgoCD

| Criterion | FluxCD | ArgoCD |
|---|---|---|
| Security posture | Pull-based, no UI attack surface | Built-in Web UI widens attack surface |
| Maintenance burden | Low — set and forget | Medium — UI, Redis, app-of-apps |
| Multi-cluster | Separate Flux instance per cluster, same Git repo | Single Argo managing remotes — heavier |
| Bootstrap | `flux bootstrap` or Terraform provider | `kubectl apply` + ArgoCD CLI |

**Decision: FluxCD** — one Flux instance per EKS cluster, both reconciling
from the same GitLab repo with cluster-specific paths.

---

## 5. Requirements

### 5.1 Infrastructure — AWS

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| INFRA-001 | The primary region **shall** be us-west-2 (commercial). | Must | |
| INFRA-002 | The satellite region **shall** be us-east-1 (commercial). | Must | |
| INFRA-003 | All region/partition/endpoint configuration **shall** be parameterized for GovCloud portability. | Must | |
| INFRA-004 | All AWS API calls **shall** use FIPS-validated endpoints. | Must | |
| INFRA-005 | All data at rest **shall** be encrypted via KMS (SSE-KMS). | Must | |
| INFRA-006 | All data in transit **shall** use TLS 1.2+. | Must | |
| INFRA-007 | Infrastructure **shall** be Terraform, stored in gov.demo.coder.com. | Must | |
| INFRA-008 | Each region **shall** have its own VPC with private subnets + NAT for outbound. | Must | |
| INFRA-009 | Each VPC **shall** span ≥2 AZs. | Must | |
| INFRA-010 | VPCs **shall** be peered (or use Transit Gateway) for provisioner ↔ control plane connectivity. | Must | Provisioners in us-east-1 need to reach coderd in us-west-2 |
| INFRA-011 | Security groups **shall** follow least-privilege. | Must | |
| INFRA-012 | Route 53 **shall** manage DNS with ACM certs in both regions. | Must | |
| INFRA-013 | Terraform state **shall** be in S3 + DynamoDB, KMS-encrypted. | Must | |
| INFRA-014 | Elastic IPs **should** be allocated for stable ingress (Coder, GitLab, Grafana, Proxy). | Should | |

### 5.2 EKS Clusters

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| EKS-001 | Two EKS clusters **shall** be provisioned: `gov-demo-west` (us-west-2) and `gov-demo-east` (us-east-1). | Must | |
| EKS-002 | Both clusters **shall** run Kubernetes 1.30+. | Must | |
| EKS-003 | Managed node groups **shall** use Bottlerocket FIPS AMIs. | Must | |
| EKS-004 | Managed add-ons **shall** include: CoreDNS, kube-proxy, vpc-cni, EBS CSI driver. | Must | |
| EKS-005 | API server endpoints **shall** be private-only or dual with restricted public CIDRs. | Must | |
| EKS-006 | All workload IAM **shall** use IRSA. No static keys. | Must | |
| EKS-007 | Audit logging **shall** be enabled → CloudWatch. | Must | |
| EKS-008 | Each cluster **shall** have a "system" managed node group for platform workloads. | Must | |
| EKS-009 | Default StorageClass **shall** be EBS CSI gp3, encrypted, `WaitForFirstConsumer`. | Must | |

### 5.3 Karpenter

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| KARP-001 | Karpenter **shall** be deployed in both clusters, 2 replicas across AZs. | Must | |
| KARP-002 | Controllers **shall** be pinned to the system node group. | Must | |
| KARP-003 | Each cluster **shall** have ≥1 EC2NodeClass for workspace nodes (≥200 GiB gp3). | Must | |
| KARP-004 | NodePools **shall** support spot + on-demand. | Must | |
| KARP-005 | Spot termination handling **shall** be enabled (SQS + EventBridge). | Must | |
| KARP-006 | Consolidation **should** be `WhenEmpty` with configurable TTL. | Should | |
| KARP-007 | Image-prefetch DaemonSet **should** warm workspace base images. | Should | |
| KARP-008 | EC2NodeClass **shall** discover subnets/SGs via tags. | Must | |

### 5.4 FluxCD

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| FLUX-001 | FluxCD **shall** be the sole GitOps engine. | Must | |
| FLUX-002 | Each EKS cluster **shall** run its own FluxCD instance. | Must | |
| FLUX-003 | Both Flux instances **shall** reconcile from the same GitLab CE repo using cluster-specific paths (`clusters/gov-demo-west/`, `clusters/gov-demo-east/`). | Must | |
| FLUX-004 | FluxCD **shall** be bootstrapped via the Flux Terraform provider. | Must | |
| FLUX-005 | Controllers: source-controller, kustomize-controller, helm-controller, notification-controller. | Must | |
| FLUX-006 | Reconciliation interval **shall** be ≤5 minutes. | Must | |
| FLUX-007 | `dependsOn` **shall** enforce infrastructure-before-apps ordering. | Must | |
| FLUX-008 | Git auth **shall** use SSH keys. | Must | |

### 5.5 Coder — Control Plane (us-west-2)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| CDR-001 | Coder control plane (coderd) **shall** run in `gov-demo-west` via the official Helm chart. | Must | |
| CDR-002 | Coderd **shall** be exposed via NLB + ACM TLS at `gov.demo.coder.com`. | Must | |
| CDR-003 | Coderd **shall** use RDS PostgreSQL 15+ (multi-AZ) in us-west-2 as its database. | Must | |
| CDR-004 | RDS **shall** be multi-AZ with automated backups and 7-day retention. | Must | |
| CDR-005 | Coderd **shall** authenticate users via GitLab CE OIDC. | Must | |
| CDR-006 | AI Bridge **shall** be enabled. | Must | See §5.7 |
| CDR-007 | The `coder-observability` chart **shall** be deployed in us-west-2. | Must | |
| CDR-008 | Resource requests **shall** be ≥1000m CPU / 2Gi memory. | Must | |
| CDR-009 | Coderd **shall** set `provisionerDaemons = 0` (external provisioners only). | Must | Enterprise feature |
| CDR-010 | Pod topology spread **should** distribute across AZs. | Should | |

### 5.6 Coder — External Provisioners & Proxy

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| PROV-001 | External provisioners **shall** run in both `gov-demo-west` and `gov-demo-east` via the `coder-provisioner` Helm chart. | Must | |
| PROV-002 | Each provisioner deployment **shall** have IRSA with EC2ReadOnly + a scoped provisioner IAM policy for its region. | Must | Per ai.coder.com pattern |
| PROV-003 | Provisioners **shall** use `coderd_organization` + provisioner key secrets to authenticate to the control plane. | Must | |
| PROV-004 | Provisioners **shall** be tagged by region (e.g., `region=us-west-2`, `region=us-east-1`) so templates can target a specific region. | Must | |
| PROV-005 | Provisioners **should** run ≥2 replicas per region for availability. | Should | |
| PROV-006 | A **workspace proxy** **shall** run in `gov-demo-east` via the Coder Helm chart with `workspaceProxy = true`. | Must | |
| PROV-007 | The proxy **shall** be exposed via NLB + ACM TLS at a proxy-specific subdomain (e.g., `east.gov.demo.coder.com`). | Must | |
| PROV-008 | The proxy **shall** use `CODER_PRIMARY_ACCESS_URL` to connect back to coderd in us-west-2. | Must | Requires VPC peering / TGW |
| PROV-009 | The proxy session token **shall** be stored in Secrets Manager and synced via External Secrets Operator. | Must | |
| PROV-010 | Workspace templates **shall** be stored in GitLab CE and managed via Terraform. | Must | |
| PROV-011 | Templates **should** support both K8s and EC2 workspace types. | Should | |

### 5.7 AI Bridge + LiteLLM

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| AI-001 | AI Bridge **shall** be enabled on the control plane to proxy AI tool requests. | Must | |
| AI-002 | LiteLLM **shall** run in `gov-demo-west` via Helm. | Must | |
| AI-003 | LiteLLM **shall** integrate with AWS Bedrock via IRSA. | Must | |
| AI-004 | LiteLLM **shall** autoscale (min 1, max 5, 80% CPU). | Must | |
| AI-005 | LiteLLM **shall** use PostgreSQL for API key/usage tracking. | Must | Can share Coder RDS or standalone |
| AI-006 | AI Bridge **shall** support Anthropic + OpenAI-compatible endpoints. | Must | |
| AI-007 | AI Bridge **shall** record token usage and request metadata. | Must | |
| AI-008 | LiteLLM model config **shall** be a ConfigMap reconciled by FluxCD. | Must | |

### 5.8 GitLab CE

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| GL-001 | GitLab CE **shall** be deployed on EC2 (us-west-2) via Omnibus. | Must | |
| GL-002 | The EC2 instance **shall** run Amazon Linux 2023 or RHEL 9 with FIPS kernel. | Must | |
| GL-003 | GitLab **shall** use bundled PostgreSQL and Redis. | Must | Single-instance demo simplicity |
| GL-004 | GitLab **shall** use S3 for object storage. | Must | |
| GL-005 | GitLab **shall** be fronted by NLB + ACM TLS. | Must | |
| GL-006 | GitLab **shall** be the Git source-of-truth for FluxCD and Coder templates. | Must | |
| GL-007 | GitLab **shall** act as the OIDC provider for Coder. | Must | |
| GL-008 | GitLab backups **shall** run daily to S3, 30-day retention. | Must | |
| GL-009 | GitLab **shall** have a shell-based GitLab Runner registered on the same EC2 instance. | Must | |
| GL-010 | The runner **shall** be configured with a Docker executor using the host Docker socket or a shell executor for basic CI jobs. | Must | |
| GL-011 | Runner **should** be able to build and push container images to ECR. | Should | Needs `docker` or `kaniko` + ECR auth |
| GL-012 | A Kubernetes-based runner on EKS **may** be added later for parallelized CI. | May | Deferred unless needed |
| GL-013 | Host OS **should** be STIG-hardened (best-effort). | Should | |
| GL-014 | GitLab **should** be in an ASG (min 1, max 1) for self-healing. | Should | |

### 5.9 Secrets Management

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| SM-001 | AWS Secrets Manager **shall** store all sensitive values in both regions. | Must | |
| SM-002 | External Secrets Operator **shall** run in both EKS clusters. | Must | |
| SM-003 | No secrets in plain text in Git. All via ExternalSecret CRs. | Must | |
| SM-004 | Secrets Manager **shall** use KMS encryption. | Must | |
| SM-005 | Cross-region secrets (e.g., proxy session token) **shall** be replicated via Secrets Manager cross-region replication or Terraform-managed in both regions. | Must | |

### 5.10 Container Registry

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| REG-001 | ECR **shall** be the container registry in both regions. | Must | |
| REG-002 | ECR image scanning **shall** be enabled. | Must | |
| REG-003 | ECR lifecycle policies **should** retain last 30 tagged images. | Should | |
| REG-004 | ECR cross-region replication **should** be configured from us-west-2 → us-east-1 for workspace images. | Should | Avoid cross-region pull latency |

### 5.11 Observability

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| OBS-001 | `coder-observability` **shall** be deployed in `gov-demo-west`. | Must | |
| OBS-002 | Loki **shall** use S3 (us-west-2) for log storage. | Must | |
| OBS-003 | Grafana Agent **shall** run as DaemonSet in both clusters. | Must | |
| OBS-004 | `gov-demo-east` Agent **should** ship metrics/logs to the us-west-2 Prometheus/Loki. | Should | Single pane of glass |
| OBS-005 | Grafana **should** be exposed via NLB + TLS. | Should | |

### 5.12 Security & Compliance

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| SEC-001 | All crypto **shall** use FIPS 140-2/140-3 validated modules. | Must | |
| SEC-002 | KMS **shall** manage all encryption keys. | Must | |
| SEC-003 | All inter-service traffic **shall** use TLS 1.2+. | Must | |
| SEC-004 | No static IAM keys in-cluster; IRSA only. | Must | |
| SEC-005 | CloudTrail **shall** be enabled in both regions. | Must | |
| SEC-006 | Images **should** come from ECR or verified upstream. | Should | |
| SEC-007 | NetworkPolicies **should** restrict pod-to-pod traffic. | Should | |
| SEC-008 | EC2 host OS **should** be STIG-hardened (best-effort). | Should | |
| SEC-009 | EKS nodes **should** use Bottlerocket FIPS AMIs. | Should | |

### 5.13 Bootstrap & Repo Structure

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-001 | Both EKS clusters **shall** be provisioned via Terraform before FluxCD bootstrap. | Must | |
| BOOT-002 | FluxCD bootstrap **shall** be a Terraform resource per cluster. | Must | |
| BOOT-003 | The repo **shall** use the following structure: | Must | |

```
gov.demo.coder.com/
├── docs/
│   └── REQUIREMENTS.md
├── infra/
│   └── terraform/
│       ├── 0-state/                  # S3 backend, DynamoDB lock table
│       ├── 1-network/
│       │   ├── us-west-2/            # VPC, subnets, NAT, peering (west side)
│       │   └── us-east-1/            # VPC, subnets, NAT, peering (east side)
│       ├── 2-data/                   # RDS (multi-AZ, us-west-2), S3, KMS, ECR, Secrets Mgr
│       ├── 3-eks/
│       │   ├── us-west-2/            # gov-demo-west cluster
│       │   └── us-east-1/            # gov-demo-east cluster
│       ├── 4-bootstrap/
│       │   ├── us-west-2/            # FluxCD + Karpenter bootstrap (west)
│       │   └── us-east-1/            # FluxCD + Karpenter bootstrap (east)
│       └── 5-gitlab/                 # GitLab CE EC2 (us-west-2)
├── clusters/
│   ├── gov-demo-west/
│   │   ├── flux-system/
│   │   ├── infrastructure/
│   │   │   ├── sources/
│   │   │   ├── karpenter/
│   │   │   ├── external-secrets/
│   │   │   └── kustomization.yaml
│   │   └── apps/
│   │       ├── coder-server/
│   │       ├── coder-provisioner/
│   │       ├── litellm/
│   │       ├── monitoring/
│   │       └── kustomization.yaml
│   └── gov-demo-east/
│       ├── flux-system/
│       ├── infrastructure/
│       │   ├── sources/
│       │   ├── karpenter/
│       │   ├── external-secrets/
│       │   └── kustomization.yaml
│       └── apps/
│           ├── coder-proxy/
│           ├── coder-provisioner/
│           └── kustomization.yaml
└── templates/
    ├── kubernetes-claude/
    ├── aws-linux/
    └── aws-devcontainer/
```

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-004 | `dependsOn` **shall** enforce infrastructure-before-apps in both clusters. | Must | |
| BOOT-005 | Deploy sequence: 0-state → 1-network (both) → 2-data → 3-eks (both) → 4-bootstrap (both) → 5-gitlab → FluxCD reconciles apps. | Must | |
| BOOT-006 | All Helm chart versions **shall** be pinned. | Must | |

---

## 6. Requirement Traceability Matrix

| Req ID | Category | Traces To |
|---|---|---|
| INFRA-001 – INFRA-014 | AWS Infrastructure | NIST SP 800-53, FIPS 140-3 |
| EKS-001 – EKS-009 | EKS Clusters | CIS EKS Benchmark, ai.coder.com |
| KARP-001 – KARP-008 | Karpenter | ai.coder.com reference |
| FLUX-001 – FLUX-008 | FluxCD | Trade Study §4, FluxCD best practices |
| CDR-001 – CDR-010 | Coder Control Plane | ai.coder.com, Coder docs |
| PROV-001 – PROV-011 | Provisioners & Proxy | ai.coder.com coder-provisioner + coder-proxy modules |
| AI-001 – AI-008 | AI Bridge / LiteLLM | ai.coder.com, Coder AI Bridge docs |
| GL-001 – GL-014 | GitLab CE + Runners | GitLab AWS reference arch |
| SM-001 – SM-005 | Secrets Management | AWS Secrets Manager docs |
| REG-001 – REG-004 | Container Registry | ECR docs |
| OBS-001 – OBS-005 | Observability | ai.coder.com |
| SEC-001 – SEC-009 | Security & Compliance | FIPS 140-2/3, DISA STIG |
| BOOT-001 – BOOT-006 | Bootstrap | FluxCD docs, Terraform Flux provider |

---

## 7. Open Items

| # | Item | Status |
|---|---|---|
| 1 | Domain name (e.g., `gov.demo.coder.com`) | Open |
| 2 | Proxy subdomain convention (e.g., `east.gov.demo.coder.com`) | Open |
| 3 | Bedrock model selection + availability in both regions | Open |
| 4 | Coder license tier — external provisioners + proxy require Enterprise | Open — likely Enterprise |
| 5 | VPC peering vs Transit Gateway for cross-region connectivity | Open |
| 6 | NAT strategy: fck-nat (cheap) vs AWS NAT Gateway (zero-ops) | Open |
| 7 | GitLab runner executor: shell vs Docker-in-Docker on EC2 | Open |
| 8 | Loki cross-region: east Grafana Agent → west Loki, or separate Loki per region | Open |
| 9 | FluxCD: OSS vs ControlPlane Enterprise | Open |
