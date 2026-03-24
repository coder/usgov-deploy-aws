# GovCloud Demo Environment — Requirements Document

**Project:** gov.demo.coder.com
**Classification:** Unclassified — For Demo/Reference Use
**Version:** 0.1.0-DRAFT
**Date:** 2025-03-24

---

## 1. Purpose

This document defines the requirements for a GovCloud-hosted demonstration
environment that mimics a sensitive government customer deployment. The
environment shall be GitOps-controlled, FIPS-enabled, and deploy a standard
developer-platform tool chain centered on Coder.

All requirements use **shall** (mandatory), **should** (recommended), or
**may** (optional) language per RFC 2119 to enable traceability.

---

## 2. Trade Studies

### 2.1 GitOps Engine — FluxCD vs ArgoCD

| Criterion | FluxCD | ArgoCD |
|---|---|---|
| Security posture | Pull-based, no UI attack surface, K8s RBAC-native | Built-in Web UI widens attack surface |
| FIPS / compliance fit | Security-first, no external credential exposure | Requires extra hardening for dashboard |
| Modularity | Controller-per-concern (Source, Kustomize, Helm, Notification) | Monolithic install with optional components |
| Git-native RBAC | Inherits Git provider permissions — ideal with self-hosted GitLab | Separate RBAC system in-cluster |
| Multi-cluster | Hub-spoke via Flux-in-management-cluster pattern | Native multi-cluster, heavier footprint |
| UI / Visibility | CLI-only (Devtron or Weave GitOps dashboards optional add-on) | Rich built-in Web UI |
| Bootstrap | `flux bootstrap` CLI or Terraform provider | `kubectl apply` + ArgoCD CLI |

**Decision: FluxCD**

Rationale:
- FluxCD's modular, pull-based architecture is a better fit for security-
  sensitive environments where minimizing attack surface matters.
- Git-native RBAC aligns with the self-hosted GitLab instance that will serve
  as the source-of-truth, keeping access decisions in one place.
- The Flux Terraform provider enables bootstrap-as-code, which pairs well with
  the Terraform-centric IaC approach taken by ai.coder.com.
- ControlPlane Enterprise for FluxCD is available directly from AWS Marketplace
  for EKS, simplifying procurement in GovCloud.

### 2.2 GitLab CE — EKS vs EC2

| Criterion | EKS (Helm chart) | EC2 (Omnibus) |
|---|---|---|
| Operational complexity | High — multi-component chart (Webservice, Sidekiq, Gitaly, Registry, etc.), requires RDS + ElastiCache + EFS/S3 | Low — single-binary "omnibus" install on one or more instances |
| FIPS enablement | Requires FIPS-compiled container images for every sub-component; GitLab CE does not ship official FIPS images | GitLab Omnibus on RHEL/AL2023 with FIPS-enabled kernel — well-documented path |
| STIG applicability | No published CIS/STIG for GitLab-on-K8s | RHEL 9 / AL2023 STIG baselines apply directly to host OS |
| Scaling model | Horizontal pod autoscaling per component | Vertical + ASG horizontal (Omnibus supports multi-node reference arch) |
| Backup / DR | Complex — distributed state across PVCs, RDS, S3 | Straightforward — `gitlab-backup create` to S3 |
| Community support | Helm chart is community-maintained; EKS-specific docs are thin | GitLab's own AWS reference architecture targets EC2+RDS+ElastiCache |

**Decision: EC2 (Omnibus)**

Rationale:
- GitLab's own reference architecture for AWS uses EC2 with RDS and
  ElastiCache, and this is the path with the most complete documentation.
- FIPS enablement on the host OS (RHEL 9 or Amazon Linux 2023 in FIPS mode) is
  well-understood and does not require custom container image builds.
- STIG compliance maps directly to the host OS baseline (RHEL 9 STIG) rather
  than requiring a Kubernetes-specific hardening guide.
- For a demo environment, the operational simplicity of Omnibus outweighs the
  scaling benefits of Kubernetes.

### 2.3 Nexus Repository OSS — EKS vs EC2

| Criterion | EKS (Helm chart) | EC2 (Docker / standalone) |
|---|---|---|
| Official support | Sonatype provides Helm charts, but HA charts target Pro only; CE is "manually adjusted" | Standalone install (Java) or Docker — fully supported for CE |
| Storage | Requires EFS CSI driver for cross-AZ persistence; S3 blobstore available | EBS volume + S3 sync for backup — simpler |
| Resource requirements | Min 4 CPU / 8 GB per pod; needs EFS, ALB controller, CSI drivers | Same compute, but no K8s overhead |
| FIPS | Same container-level FIPS concerns as GitLab | Host-OS FIPS mode covers all crypto |
| Resilience | K8s self-healing, but CE is single-replica only | ASG with health checks + EBS snapshot restore |
| Complexity | Moderate — Helm + EFS + ALB + PVC management | Low — Docker Compose or systemd on EC2 |

**Decision: EC2**

Rationale:
- Nexus CE is inherently single-instance (no HA clustering) so Kubernetes
  orchestration provides minimal benefit for resilience.
- Sonatype's own HA/resilience Helm chart targets Pro; CE would require manual
  chart modifications.
- EC2 with Docker Compose behind an NLB is operationally simpler and aligns
  with the GitLab EC2 deployment, reducing the number of distinct operational
  patterns.
- FIPS enablement on the host OS is straightforward.

---

## 3. Recommended Additional Tools

Based on typical government customer integration points:

| Tool | Purpose | Deployment Target | Rationale |
|---|---|---|---|
| **HashiCorp Vault (OSS)** | Secrets management, PKI, dynamic credentials | EKS (Helm) | Central secrets management for all services; Vault Agent injector integrates natively with K8s workloads and Coder templates; FIPS-capable builds available |
| **Keycloak** | Identity Provider / SSO (SAML 2.0, OIDC) | EKS (Helm) | Gov customers typically require a centralized IdP; Keycloak federates to PIV/CAC via X.509, integrates with GitLab/Coder/Nexus/Vault; FIPS-capable with BouncyCastle FIPS provider |
| **Harbor** | Container registry with vulnerability scanning | EKS (Helm) | Provides Trivy-based image scanning, RBAC, and replication — critical for supply chain security in gov; complements Nexus (which handles language-level artifacts) |
| **Prometheus + Grafana + Loki** | Observability stack | EKS (Helm) | Consistent with the ai.coder.com reference architecture; Coder ships a purpose-built `coder-observability` chart |
| **External Secrets Operator** | Bridge between Vault and K8s Secrets | EKS (Helm) | Eliminates manual secret management in GitOps manifests |

---

## 4. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AWS GovCloud (us-gov-west-1)                    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                         VPC                                  │   │
│  │                                                              │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │              EKS Cluster (FIPS-enabled)              │     │   │
│  │  │                                                     │     │   │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐    │     │   │
│  │  │  │  Coder   │ │ LiteLLM  │ │   FluxCD         │    │     │   │
│  │  │  │  Server  │ │ (AI GW)  │ │   Controllers    │    │     │   │
│  │  │  └──────────┘ └──────────┘ └──────────────────┘    │     │   │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐    │     │   │
│  │  │  │  Vault   │ │ Keycloak │ │   Harbor          │    │     │   │
│  │  │  └──────────┘ └──────────┘ └──────────────────┘    │     │   │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐    │     │   │
│  │  │  │ ExtSecrets│ │Prometheus│ │ Grafana + Loki   │    │     │   │
│  │  │  └──────────┘ └──────────┘ └──────────────────┘    │     │   │
│  │  │  ┌────────────────────────────────────────────┐    │     │   │
│  │  │  │       Karpenter (Workspace Node Scaling)    │    │     │   │
│  │  │  └────────────────────────────────────────────┘    │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  │                                                              │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐     │   │
│  │  │  GitLab CE   │  │  Nexus OSS   │  │   RDS (PG 15)  │     │   │
│  │  │  (EC2/ASG)   │  │  (EC2/ASG)   │  │  Coder + Vault │     │   │
│  │  └──────────────┘  └──────────────┘  └────────────────┘     │   │
│  │                                                              │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐     │   │
│  │  │ ElastiCache  │  │   S3         │  │    KMS          │     │   │
│  │  │ (Redis/GL)   │  │ (artifacts,  │  │ (FIPS 140-3 L3)│     │   │
│  │  └──────────────┘  │  logs, Loki) │  └────────────────┘     │   │
│  │                    └──────────────┘                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  GitOps Flow:  GitLab CE ──► FluxCD ──► EKS Cluster         │   │
│  │                GitLab CE ──► FluxCD ──► EC2 (via Terraform)  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Requirements

### 5.1 Infrastructure — AWS GovCloud

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| INFRA-001 | The environment **shall** be deployed entirely within AWS GovCloud (us-gov-west-1 or us-gov-east-1). | Must | FedRAMP High baseline region |
| INFRA-002 | All AWS API calls **shall** use FIPS-validated endpoints (via `AWS_USE_FIPS_ENDPOINT=true`). | Must | FIPS 140-3 endpoints per AWS compliance page |
| INFRA-003 | All data at rest **shall** be encrypted using AWS KMS with FIPS 140-3 Level 3 validated HSMs (SSE-KMS). | Must | Applies to S3, EBS, RDS, ElastiCache |
| INFRA-004 | All data in transit **shall** use TLS 1.2 or higher with FIPS-validated cryptographic modules. | Must | |
| INFRA-005 | Infrastructure **shall** be defined as code using Terraform, stored in the gov.demo.coder.com Git repository. | Must | |
| INFRA-006 | The VPC **shall** use private subnets for all compute workloads with NAT gateway (or fck-nat equivalent) for outbound internet access. | Must | Reference ai.coder.com pattern |
| INFRA-007 | The VPC **should** implement at least 2 Availability Zones for all stateful services. | Should | |
| INFRA-008 | All EC2 instances **shall** use Bottlerocket FIPS AMIs or RHEL 9 / Amazon Linux 2023 with FIPS mode enabled at the kernel level. | Must | Bottlerocket FIPS AMIs now available for EKS managed node groups |
| INFRA-009 | All EC2 instances hosting GitLab or Nexus **should** be hardened per applicable DISA STIG (RHEL 9 STIG). | Should | User preference: best-effort, not blocking |
| INFRA-010 | All security groups **shall** follow least-privilege rules — only required ports open, source-scoped to VPC CIDR or specific SGs. | Must | |
| INFRA-011 | The environment **shall** use Route 53 for DNS management with ACM-provisioned TLS certificates. | Must | |
| INFRA-012 | The environment **shall** allocate Elastic IPs for stable ingress endpoints (Coder, Grafana, GitLab). | Should | |

### 5.2 EKS Cluster

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| EKS-001 | The EKS cluster **shall** run Kubernetes 1.30+ with the EKS-optimized AMI. | Must | |
| EKS-002 | EKS worker nodes **shall** use Bottlerocket FIPS AMIs for managed node groups. | Must | Per AWS announcement: FIPS 140-3 validated crypto modules, FIPS endpoints by default |
| EKS-003 | The EKS cluster **shall** enable the following managed add-ons: CoreDNS, kube-proxy, vpc-cni, EBS CSI driver. | Must | |
| EKS-004 | The cluster API server endpoint **shall** be private-only or dual (private + restricted public). Public access, if enabled, **shall** be restricted to known CIDR blocks. | Must | |
| EKS-005 | All IAM integration **shall** use IRSA (IAM Roles for Service Accounts) via the cluster's OIDC provider. | Must | No long-lived IAM access keys in-cluster |
| EKS-006 | EKS audit logging **shall** be enabled and shipped to CloudWatch Logs (api, audit, authenticator, controllerManager, scheduler). | Must | |
| EKS-007 | The cluster **shall** include a "system" managed node group for platform workloads (FluxCD, Karpenter, Vault, monitoring). | Must | |
| EKS-008 | The default StorageClass **shall** be EBS CSI gp3, encrypted, with `WaitForFirstConsumer` binding. | Must | Per ai.coder.com pattern |

### 5.3 Karpenter (Workspace Scaling)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| KARP-001 | Karpenter **shall** be deployed via Helm into a dedicated `karpenter` namespace with 2 replicas spread across AZs. | Must | Per ai.coder.com reference |
| KARP-002 | Karpenter controller pods **shall** be pinned to the system managed node group via node affinity. | Must | Prevent self-eviction loop |
| KARP-003 | At least one EC2NodeClass **shall** be defined for Coder workspace nodes with ≥200 GiB gp3 root volumes. | Must | ai.coder.com uses 500 GiB |
| KARP-004 | At least one NodePool **shall** be defined supporting both spot and on-demand capacity types. | Must | Cost optimization |
| KARP-005 | Spot termination handling **shall** be enabled (SQS interruption queue + EventBridge rules). | Must | |
| KARP-006 | NodePools **should** define a consolidation policy of `WhenEmpty` with a configurable TTL. | Should | |
| KARP-007 | An image-prefetch DaemonSet **should** be deployed to warm workspace base images on Karpenter-provisioned nodes. | Should | Per ai.coder.com pattern |
| KARP-008 | EC2NodeClass **shall** use subnet and security group discovery via tags (`karpenter.sh/discovery`). | Must | |

### 5.4 FluxCD (GitOps)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| FLUX-001 | FluxCD **shall** be the sole GitOps engine for the environment. | Must | Per trade study §2.1 |
| FLUX-002 | FluxCD **shall** be bootstrapped via the Flux Terraform provider or `flux bootstrap` CLI targeting the self-hosted GitLab CE instance. | Must | |
| FLUX-003 | The FluxCD source repository **shall** be the gov.demo.coder.com repository hosted on the self-hosted GitLab CE. | Must | After initial bootstrap, migrate source from GitHub to GitLab |
| FLUX-004 | FluxCD **shall** deploy the following controllers: source-controller, kustomize-controller, helm-controller, notification-controller. | Must | |
| FLUX-005 | All Flux Kustomizations **shall** use a structured directory layout: `clusters/<cluster-name>/`, `infrastructure/`, `apps/`. | Must | Flux recommended repo structure |
| FLUX-006 | Flux **shall** reconcile at an interval no greater than 5 minutes. | Must | |
| FLUX-007 | Flux **should** be configured with health checks and dependency ordering (`dependsOn`) for infrastructure-before-apps sequencing. | Should | |
| FLUX-008 | Flux **shall** use SSH key-based authentication to the GitLab repository with keys stored as Kubernetes Secrets. | Must | |
| FLUX-009 | Flux notifications **should** be configured to send reconciliation status to a Slack/webhook endpoint. | Should | |
| FLUX-010 | The initial bootstrapping of FluxCD onto the EKS cluster **shall** be automated as part of the Terraform infrastructure code. | Must | |

### 5.5 Coder

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| CDR-001 | Coder **shall** be deployed on EKS via the official Helm chart. | Must | |
| CDR-002 | Coder **shall** be exposed via an AWS NLB with TLS termination using ACM certificates. | Must | |
| CDR-003 | Coder **shall** use an RDS PostgreSQL 15+ instance as its database backend. | Must | |
| CDR-004 | Coder **shall** integrate with the Keycloak IdP for OIDC-based authentication. | Must | |
| CDR-005 | Coder **shall** leverage Karpenter-managed NodePools for workspace scheduling. | Must | |
| CDR-006 | Coder **shall** be configured with pod topology spread constraints across availability zones. | Should | |
| CDR-007 | Coder provisioners **shall** use IRSA for AWS API access (no static credentials). | Must | |
| CDR-008 | Coder workspace templates **shall** be stored in the GitLab CE instance and managed via Terraform. | Must | |
| CDR-009 | Coder **shall** have AI Bridge enabled. | Must | See §5.6 |
| CDR-010 | Coder **shall** be deployed with the `coder-observability` Helm chart for Prometheus + Grafana + Loki integration. | Must | |
| CDR-011 | Coder resource requests **shall** be at minimum 1000m CPU / 2Gi memory per replica. | Must | Per ai.coder.com baseline |
| CDR-012 | Coder **should** support both Kubernetes-based and EC2-based workspace templates. | Should | |

### 5.6 AI Bridge + LiteLLM

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| AI-001 | Coder AI Bridge **shall** be enabled to proxy AI coding tool requests (Claude Code, Cursor, Copilot, etc.). | Must | |
| AI-002 | LiteLLM **shall** be deployed on EKS via Helm as the upstream AI gateway for AI Bridge. | Must | Per ai.coder.com pattern |
| AI-003 | LiteLLM **shall** integrate with AWS Bedrock using IRSA (IAM role with `AmazonBedrockFullAccess` or scoped policy). | Must | No static keys |
| AI-004 | LiteLLM **shall** be configured with horizontal pod autoscaling (min 1, max 5 replicas, 80% CPU target). | Must | |
| AI-005 | LiteLLM **shall** use a PostgreSQL database (RDS or standalone) for API key management and usage tracking. | Must | |
| AI-006 | AI Bridge **shall** support both Anthropic-compatible and OpenAI-compatible client endpoints. | Must | Per Coder AI Bridge docs |
| AI-007 | AI Bridge **shall** record token usage, model selection, and request metadata for observability. | Must | |
| AI-008 | LiteLLM **should** be fronted by a LoadBalancer service for direct administrative access. | Should | |
| AI-009 | LiteLLM model configuration **shall** be managed via a ConfigMap reconciled by FluxCD. | Must | GitOps-managed model routing |

### 5.7 GitLab CE

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| GL-001 | GitLab Community Edition **shall** be deployed on EC2 using the Omnibus package. | Must | Per trade study §2.2 |
| GL-002 | The GitLab EC2 instance(s) **shall** run RHEL 9 or Amazon Linux 2023 with FIPS kernel mode enabled. | Must | |
| GL-003 | GitLab **shall** use RDS PostgreSQL as its database backend (replacing the bundled PostgreSQL). | Must | |
| GL-004 | GitLab **shall** use ElastiCache Redis as its cache/queue backend (replacing the bundled Redis). | Must | |
| GL-005 | GitLab **shall** use S3 for object storage (LFS, artifacts, uploads, packages, backups). | Must | |
| GL-006 | GitLab **shall** be fronted by an NLB or ALB with TLS termination via ACM. | Must | |
| GL-007 | GitLab **shall** serve as the Git source-of-truth for all GitOps repositories (FluxCD source). | Must | |
| GL-008 | GitLab **shall** serve as the Git host for Coder workspace templates. | Must | |
| GL-009 | GitLab **should** integrate with Keycloak for SAML/OIDC SSO. | Should | |
| GL-010 | GitLab **should** be deployed in an Auto Scaling Group (min 1, max 2) for instance recovery. | Should | |
| GL-011 | GitLab host OS **should** be hardened per DISA RHEL 9 STIG. | Should | |
| GL-012 | GitLab backups **shall** be automated daily to S3 with a 30-day retention policy. | Must | |

### 5.8 Nexus Repository OSS

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| NEX-001 | Nexus Repository OSS **shall** be deployed on EC2. | Must | Per trade study §2.3 |
| NEX-002 | The Nexus EC2 instance **shall** run RHEL 9 or Amazon Linux 2023 with FIPS kernel mode enabled. | Must | |
| NEX-003 | Nexus **shall** use S3 as its blobstore backend for artifact storage. | Must | Unlimited, durable storage |
| NEX-004 | Nexus **shall** be configured with proxy repositories for: Maven Central, npm registry, PyPI, Docker Hub. | Must | Standard dependency proxying |
| NEX-005 | Nexus **shall** be configured with hosted repositories for: internal Maven, npm, Docker. | Must | |
| NEX-006 | Nexus **shall** be fronted by an NLB or ALB with TLS termination via ACM. | Must | |
| NEX-007 | Nexus host OS **should** be hardened per DISA RHEL 9 STIG. | Should | |
| NEX-008 | Nexus **shall** be deployed in an Auto Scaling Group (min 1, max 1) for self-healing on instance failure. | Must | CE is single-instance only |
| NEX-009 | Nexus data **shall** be persisted on an EBS volume with automated snapshots. | Must | |
| NEX-010 | Nexus **should** integrate with Keycloak for SSO via SAML (Nexus Pro) or LDAP-backed auth. | Should | CE has limited SSO; Keycloak LDAP adapter is an option |

### 5.9 Vault (Secrets Management)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| VLT-001 | HashiCorp Vault OSS **shall** be deployed on EKS via the official Helm chart. | Must | |
| VLT-002 | Vault **shall** use auto-unseal via AWS KMS. | Must | FIPS 140-3 L3 validated HSM backing |
| VLT-003 | Vault **shall** use an integrated Raft storage backend or RDS PostgreSQL. | Must | |
| VLT-004 | Vault **shall** be the central secrets store for all services (GitLab, Nexus, Coder, LiteLLM). | Must | |
| VLT-005 | Vault **should** be configured as a PKI CA for internal TLS certificate issuance. | Should | |
| VLT-006 | The External Secrets Operator **shall** be deployed to sync Vault secrets into Kubernetes Secrets for FluxCD-managed workloads. | Must | |

### 5.10 Keycloak (Identity Provider)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| KC-001 | Keycloak **shall** be deployed on EKS via the official Bitnami or Keycloak Operator Helm chart. | Must | |
| KC-002 | Keycloak **shall** use RDS PostgreSQL as its database backend. | Must | |
| KC-003 | Keycloak **shall** be configured as the central OIDC/SAML IdP for Coder, GitLab, Grafana, and Vault. | Must | |
| KC-004 | Keycloak **should** be configured with an X.509 user certificate authentication flow (PIV/CAC simulation). | Should | Gov customer integration point |
| KC-005 | Keycloak **shall** use BouncyCastle FIPS or an equivalent FIPS-validated crypto provider. | Must | |

### 5.11 Harbor (Container Registry)

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| HBR-001 | Harbor **shall** be deployed on EKS via the official Helm chart. | Must | |
| HBR-002 | Harbor **shall** use S3 for image layer storage. | Must | |
| HBR-003 | Harbor **shall** be configured with automatic Trivy vulnerability scanning on push. | Must | |
| HBR-004 | Harbor **should** replicate critical base images from upstream registries on a scheduled basis. | Should | Air-gap simulation |
| HBR-005 | Harbor **shall** integrate with Keycloak for OIDC authentication. | Must | |
| HBR-006 | Harbor **should** serve as the container registry for Coder workspace images and GitLab CI/CD pipelines. | Should | |

### 5.12 Observability

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| OBS-001 | Prometheus **shall** be deployed for metrics collection from all EKS workloads. | Must | |
| OBS-002 | Grafana **shall** be deployed with dashboards for Coder, Karpenter, EKS, and LiteLLM. | Must | |
| OBS-003 | Loki **shall** be deployed for centralized log aggregation with S3 backend storage. | Must | |
| OBS-004 | The Grafana Agent **shall** be deployed as a DaemonSet across all nodes (including Karpenter-managed). | Must | |
| OBS-005 | Grafana **shall** integrate with Keycloak for OIDC authentication. | Should | |
| OBS-006 | The `coder-observability` Helm chart **should** be used to deploy the Coder-specific observability stack. | Should | Pre-built dashboards for coderd, provisionerd, workspaces |

### 5.13 Security & Compliance

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| SEC-001 | All cryptographic operations **shall** use FIPS 140-2/140-3 validated modules. | Must | |
| SEC-002 | AWS KMS **shall** be used for all encryption key management (EBS, S3, RDS, Secrets Manager). | Must | KMS HSMs are FIPS 140-3 L3 certified |
| SEC-003 | All inter-service communication **shall** use TLS 1.2+. | Must | |
| SEC-004 | No long-lived IAM access keys **shall** be used for in-cluster workloads; IRSA **shall** be the standard pattern. | Must | |
| SEC-005 | CloudTrail **shall** be enabled for all API activity logging. | Must | |
| SEC-006 | All container images **should** be sourced from Harbor (internal registry) or verified upstream sources. | Should | |
| SEC-007 | Kubernetes NetworkPolicies **should** be enforced to restrict pod-to-pod communication to required paths only. | Should | |
| SEC-008 | EC2 instances **should** be hardened per DISA STIG for the applicable OS (RHEL 9 or AL2023). | Should | Best-effort per user guidance |
| SEC-009 | EKS nodes **should** use Bottlerocket FIPS AMIs which follow a minimal, immutable OS design. | Should | Reduced attack surface |
| SEC-010 | All Terraform state **shall** be stored in an S3 backend with DynamoDB locking, encrypted via KMS. | Must | |

### 5.14 FluxCD Bootstrap & GitOps Workflow

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-001 | The EKS cluster **shall** be provisioned via Terraform before FluxCD bootstrap. | Must | |
| BOOT-002 | FluxCD bootstrap **shall** be executed as a Terraform resource (`flux_bootstrap_git`) within the infrastructure code. | Must | |
| BOOT-003 | The bootstrap process **shall** install FluxCD controllers and configure them to reconcile from the GitLab CE repository. | Must | |
| BOOT-004 | The repository **shall** use the following directory structure: | Must | |

```
gov.demo.coder.com/
├── docs/
│   └── REQUIREMENTS.md          # This document
├── infra/
│   ├── terraform/
│   │   ├── 1-network/           # VPC, subnets, NAT, Route 53
│   │   ├── 2-data/              # RDS, ElastiCache, S3, KMS
│   │   ├── 3-eks/               # EKS cluster, managed node groups, IRSA roles
│   │   ├── 4-bootstrap/         # FluxCD bootstrap, Karpenter install
│   │   └── 5-ec2-services/      # GitLab CE, Nexus OSS EC2 instances
│   └── modules/                 # Reusable Terraform modules
├── clusters/
│   └── gov-demo/
│       ├── flux-system/         # FluxCD self-managed manifests
│       ├── infrastructure/      # Cluster-level infra (CRDs, namespaces, policies)
│       │   ├── sources/         # HelmRepositories, GitRepositories
│       │   ├── karpenter/       # NodePools, EC2NodeClasses
│       │   ├── cert-manager/
│       │   ├── external-secrets/
│       │   └── kustomization.yaml
│       └── apps/                # Application deployments
│           ├── coder/
│           ├── litellm/
│           ├── vault/
│           ├── keycloak/
│           ├── harbor/
│           ├── monitoring/
│           └── kustomization.yaml
└── templates/                   # Coder workspace templates
    ├── kubernetes-claude/
    ├── aws-linux/
    └── aws-devcontainer/
```

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BOOT-005 | Infrastructure HelmReleases **shall** reconcile before application HelmReleases (via `dependsOn`). | Must | |
| BOOT-006 | The bootstrap sequence **shall** be: Network → Data → EKS → FluxCD → Karpenter → Platform Services → Coder. | Must | |
| BOOT-007 | All Helm chart versions **shall** be pinned in the FluxCD HelmRelease manifests. | Must | Reproducibility |

---

## 6. Requirement Traceability Matrix

| Req ID | Category | Traces To |
|---|---|---|
| INFRA-001 – INFRA-012 | AWS GovCloud Infrastructure | FedRAMP High baseline, NIST SP 800-53 |
| EKS-001 – EKS-008 | EKS Cluster | CIS Amazon EKS Benchmark, ai.coder.com reference |
| KARP-001 – KARP-008 | Karpenter | ai.coder.com reference architecture |
| FLUX-001 – FLUX-010 | FluxCD GitOps | Trade Study §2.1, FluxCD best practices |
| CDR-001 – CDR-012 | Coder | ai.coder.com reference, Coder docs |
| AI-001 – AI-009 | AI Bridge / LiteLLM | ai.coder.com reference, Coder AI Bridge docs |
| GL-001 – GL-012 | GitLab CE | Trade Study §2.2, GitLab AWS reference arch |
| NEX-001 – NEX-010 | Nexus OSS | Trade Study §2.3, Sonatype docs |
| VLT-001 – VLT-006 | Vault | HashiCorp Vault reference arch |
| KC-001 – KC-005 | Keycloak | Gov IdP integration pattern |
| HBR-001 – HBR-006 | Harbor | Supply chain security, gov container policy |
| OBS-001 – OBS-006 | Observability | ai.coder.com reference |
| SEC-001 – SEC-010 | Security & Compliance | FIPS 140-2/3, DISA STIG, NIST SP 800-53 |
| BOOT-001 – BOOT-007 | Bootstrap / GitOps Workflow | FluxCD docs, Terraform Flux provider |

---

## 7. Open Items / Decisions Needed

| # | Item | Status |
|---|---|---|
| 1 | GovCloud region selection: us-gov-west-1 vs us-gov-east-1 | Open |
| 2 | Domain name for the environment (e.g., `gov.demo.coder.com`) | Open |
| 3 | Bedrock model access: which Claude / Nova models to enable in GovCloud | Open — verify Bedrock availability in GovCloud |
| 4 | STIG depth: automated STIG scanning (e.g., OpenSCAP) vs manual checklist | Open — user indicated best-effort |
| 5 | Vault deployment: OSS Raft mode vs Vault with RDS backend | Open |
| 6 | Coder license tier: Enterprise vs OSS (impacts external provisioners, RBAC) | Open |
| 7 | GitLab CE runner strategy: Shell executor on GitLab EC2, or K8s executor on EKS | Open |
| 8 | Harbor vs ECR: whether to use Harbor or lean on native ECR in GovCloud | Open |
| 9 | Air-gap simulation: should the env simulate disconnected/air-gapped constraints | Open |
| 10 | FluxCD enterprise (ControlPlane) vs OSS | Open |
