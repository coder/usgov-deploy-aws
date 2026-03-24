# coder4gov.com — Architecture Diagrams

> **Audience:** New engineers, architects, and security reviewers evaluating the system.
>
> Every diagram below uses [Mermaid](https://mermaid.js.org/) syntax and renders natively on GitHub. Open this file in any Markdown viewer that supports Mermaid (GitHub, VS Code with the Mermaid extension, etc.).

---

## Table of Contents

1. [How to Read These Diagrams](#how-to-read-these-diagrams)
2. [Executive Overview (C4 Context)](#1-executive-overview--c4-context-level)
3. [System Container Diagram (C4 Container)](#2-system-container-diagram--c4-container-level)
4. [Network Topology](#3-network-topology)
5. [Security Groups & Port-Level Access](#3a-security-groups--port-level-access)
6. [Ingress & Egress Traffic Flows](#3b-ingress--egress-traffic-flows)
7. [EKS Cluster Architecture](#4-eks-cluster-architecture)
8. [Authentication & SSO Flow](#5-authentication--sso-flow)
9. [AI Model Routing](#6-ai-model-routing)
10. [GitOps Reconciliation Flow](#7-gitops-reconciliation-flow)
11. [Secret Management Flow](#8-secret-management-flow)
12. [Terraform Layer Dependency Graph](#9-terraform-layer-dependency-graph)
13. [FIPS Compliance Architecture](#10-fips-compliance-architecture)
14. [Disaster Recovery & Backup Architecture](#11-disaster-recovery--backup-architecture)
15. [WAF & Security Boundary](#12-waf--security-boundary)

---

## How to Read These Diagrams

This document follows an adapted **C4 model** (Context, Containers, Components, Code) to present the architecture at multiple abstraction levels:

| Level | What It Shows | Audience |
|-------|---------------|----------|
| **Context (L1)** | The system as a single box plus external actors and dependencies | Executives, new joiners |
| **Container (L2)** | Major deployable units (services, databases, buckets) and their protocols | Architects, tech leads |
| **Component (L3)** | Internal structure of a single container — classes, modules, controllers | Developers |
| **Code (L4)** | Source-level detail — typically not diagrammed, just read the code | Developers |

Diagrams 1–2 are Context/Container level. Diagrams 3–12 zoom into specific cross-cutting concerns (network, security, GitOps, etc.) at Component level.

**Color legend used throughout:**

| Color/Style | Meaning |
|-------------|---------|
| Blue nodes | Internal services we operate |
| Green nodes | AWS managed services |
| Orange nodes | External third-party APIs |
| Dashed lines | Asynchronous / eventual-consistency flows |
| Solid lines | Synchronous request/response |

---

## 1. Executive Overview — C4 Context Level

The highest-level view. coder4gov.com is a secure cloud development platform for government developers. It connects to identity providers, AI model APIs, and AWS infrastructure.

```mermaid
graph TB
    subgraph External Actors
        DEV["👤 Developers<br/><i>Write code in cloud workspaces</i>"]
        ADMIN["👤 Platform Admins<br/><i>Manage templates, users, policies</i>"]
        SECOPS["👤 SecOps / Auditors<br/><i>Review logs, dashboards, compliance</i>"]
    end

    subgraph coder4gov["☁️ coder4gov.com Platform"]
        SYSTEM["🏛️ coder4gov.com<br/>Secure Cloud Development Platform<br/><i>EKS · Coder · Keycloak · LiteLLM · GitLab</i>"]
    end

    subgraph External AI Providers
        OPENAI["🤖 OpenAI API<br/><i>GPT-5.4, GPT-5.3-codex</i>"]
        GEMINI["🤖 Google Gemini API<br/><i>Gemini 3.1 Pro, 3 Flash</i>"]
        BEDROCK["🤖 AWS Bedrock<br/><i>Claude Sonnet 4, Opus 4, Haiku 4.5</i>"]
    end

    subgraph AWS Infrastructure
        R53["🌐 Route 53<br/><i>DNS: *.coder4gov.com</i>"]
        SES_EXT["📧 Amazon SES<br/><i>Transactional email</i>"]
    end

    INTERNET(("🌍 Internet<br/><i>WAF-protected boundary</i>"))

    DEV -->|HTTPS| INTERNET
    ADMIN -->|HTTPS| INTERNET
    SECOPS -->|HTTPS| INTERNET
    INTERNET -->|TLS 1.2+| SYSTEM

    SYSTEM -->|HTTPS + API Key| OPENAI
    SYSTEM -->|HTTPS + API Key| GEMINI
    SYSTEM -->|HTTPS + IRSA| BEDROCK
    SYSTEM -->|DNS queries| R53
    SYSTEM -->|SMTP/TLS| SES_EXT
```

---

## 2. System Container Diagram — C4 Container Level

All deployable containers/services and how they communicate. This is the "what runs where" view that architects need to understand integration points and data flows.

```mermaid
graph TB
    USER["👤 Developer / Admin"]

    subgraph INTERNET_BOUNDARY["Internet Boundary"]
        WAF_EKS["🛡️ WAF ACL<br/><i>EKS services</i><br/>CRS · Bad Inputs · Bot Control<br/>Keycloak /admin IP restriction"]
        WAF_GL["🛡️ WAF ACL<br/><i>GitLab</i><br/>CRS · Bad Inputs · Bot Control<br/>Rate Limiting"]
    end

    subgraph EKS["EKS Cluster — coder4gov (K8s 1.32)"]
        subgraph SYSTEM_PODS["System Pods (system node group)"]
            CODER_S["🟦 Coder coderd<br/><i>dev.coder4gov.com</i><br/>Control plane"]
            CODER_P["🟦 Coder Provisioner<br/><i>Terraform runner</i><br/>Creates workspaces"]
            LITELLM["🟦 LiteLLM<br/><i>AI Gateway</i><br/>Multi-model proxy"]
            KC["🟦 Keycloak<br/><i>sso.coder4gov.com</i><br/>OIDC/SAML IdP"]
            GRAFANA["🟦 Grafana<br/><i>grafana.dev.coder4gov.com</i><br/>Dashboards"]
            LOKI["🟦 Loki<br/><i>Log aggregation</i>"]
            PROM["🟦 Prometheus<br/><i>Metrics</i>"]
            ISTIOD["🟦 Istiod<br/><i>Service mesh control plane</i>"]
            FLUX["🟦 FluxCD<br/><i>GitOps reconciler</i>"]
            ESO["🟦 External Secrets Operator<br/><i>Secret sync</i>"]
            KARP_CTRL["🟦 Karpenter<br/><i>Node autoscaler</i>"]
            ALB_CTRL["🟦 ALB Controller<br/><i>Ingress → ALB</i>"]
        end

        subgraph WORKSPACE_PODS["Workspace Pods (Karpenter nodes)"]
            WS1["💻 Dev Workspace 1"]
            WS2["💻 Dev Workspace 2"]
            WSN["💻 Dev Workspace N"]
        end
    end

    subgraph EC2_GITLAB["EC2 Instance — m7a.2xlarge"]
        GITLAB["🟦 GitLab CE<br/><i>gitlab.coder4gov.com</i><br/>+ Docker Runner"]
    end

    subgraph AWS_MANAGED["AWS Managed Services"]
        RDS["🟩 RDS PostgreSQL 15<br/><i>Multi-AZ</i><br/>DBs: coder, litellm, keycloak"]
        S3_GITLAB["🟩 S3: gitlab-backups<br/><i>Versioning ON</i>"]
        S3_LOKI["🟩 S3: loki-logs<br/><i>Lifecycle → IA 90d</i>"]
        S3_GENERAL["🟩 S3: general<br/><i>Artifacts</i>"]
        ECR["🟩 ECR<br/><i>coder, base-fips, desktop-fips</i>"]
        SM["🟩 Secrets Manager<br/><i>RDS pwd, API keys, license</i>"]
        KMS["🟩 KMS CMK<br/><i>Encrypts everything</i>"]
        OPENSEARCH["🟩 OpenSearch Serverless<br/><i>SIEM collection</i>"]
        SES["🟩 SES<br/><i>SMTP relay</i>"]
    end

    subgraph EXTERNAL["External AI Providers"]
        OPENAI_E["🟧 OpenAI API"]
        GEMINI_E["🟧 Google Gemini API"]
        BEDROCK_E["🟧 AWS Bedrock"]
    end

    %% User traffic
    USER -->|HTTPS| WAF_EKS
    USER -->|HTTPS| WAF_GL

    WAF_EKS -->|"ALB → HTTPS"| CODER_S
    WAF_EKS -->|"ALB → HTTPS"| KC
    WAF_EKS -->|"ALB → HTTPS"| GRAFANA
    WAF_GL -->|"ALB → HTTPS"| GITLAB

    %% Internal flows
    CODER_S -->|gRPC| CODER_P
    CODER_S -->|"OIDC (HTTPS)"| KC
    CODER_S -->|"PostgreSQL 5432<br/>TLS + force_ssl"| RDS
    CODER_P -->|"K8s API / Terraform"| WS1
    CODER_P -->|"K8s API / Terraform"| WS2

    WS1 -->|"OpenAI-compat API"| LITELLM
    WS2 -->|"OpenAI-compat API"| LITELLM

    LITELLM -->|"HTTPS + IRSA<br/>(no API key)"| BEDROCK_E
    LITELLM -->|"HTTPS + API Key"| OPENAI_E
    LITELLM -->|"HTTPS + API Key"| GEMINI_E
    LITELLM -->|"PostgreSQL 5432"| RDS

    KC -->|"PostgreSQL 5432"| RDS
    GRAFANA -->|"OIDC SSO"| KC
    GITLAB -->|"OIDC SSO"| KC

    LOKI -->|"S3 API"| S3_LOKI
    GITLAB -->|"S3 API"| S3_GITLAB
    ESO -->|"GetSecretValue"| SM
    SM -->|"Decrypt"| KMS

    FLUX -->|"HTTPS poll / webhook"| GITLAB

    KARP_CTRL -->|"EC2 API"| WSN
    ALB_CTRL -->|"ELBv2 API"| WAF_EKS
```

---

## 3. Network Topology

The VPC uses a `10.0.0.0/16` CIDR divided into six `/20` subnets across two Availability Zones. Each `/20` provides 4,094 usable host IPs. The subnet allocation is computed dynamically via `cidrsubnet(var.vpc_cidr, 4, offset)`, producing the layout below. Public subnets host ALBs and NAT Gateways; private-system subnets host EKS system nodes; private-workload subnets host Karpenter-managed workspace nodes.

```mermaid
graph TB
    INTERNET(("🌍 Internet"))
    IGW["Internet Gateway"]

    INTERNET <-->|"All traffic"| IGW

    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph AZ_A["us-west-2a"]
            PUB_A["<b>Public 10.0.0.0/20</b><br/>4,094 hosts<br/>──────────<br/>• ALB (EKS services)<br/>• NAT Gateway A<br/>• EIP"]
            SYS_A["<b>Private-System 10.0.32.0/20</b><br/>4,094 hosts<br/>──────────<br/>• EKS system node group<br/>• Coder, Keycloak, LiteLLM<br/>• Istio, FluxCD, ESO, Karpenter"]
            WKL_A["<b>Private-Workload 10.0.64.0/20</b><br/>4,094 hosts<br/>──────────<br/>• Karpenter workspace nodes<br/>• Developer workspaces"]
        end

        subgraph AZ_B["us-west-2b"]
            PUB_B["<b>Public 10.0.16.0/20</b><br/>4,094 hosts<br/>──────────<br/>• ALB (GitLab)<br/>• NAT Gateway B<br/>• EIP"]
            SYS_B["<b>Private-System 10.0.48.0/20</b><br/>4,094 hosts<br/>──────────<br/>• EKS system node group<br/>• Multi-AZ replicas"]
            WKL_B["<b>Private-Workload 10.0.80.0/20</b><br/>4,094 hosts<br/>──────────<br/>• Karpenter workspace nodes<br/>• Developer workspaces"]
        end

        RT_PUB["Route Table: Public<br/>0.0.0.0/0 → IGW"]
        RT_PRIV_A["Route Table: Private-A<br/>0.0.0.0/0 → NAT GW A"]
        RT_PRIV_B["Route Table: Private-B<br/>0.0.0.0/0 → NAT GW B"]

        RDS_INST["RDS Multi-AZ<br/>Primary + Standby<br/>in private subnets"]
        GITLAB_EC2["GitLab EC2<br/>(ASG, private subnets)"]
    end

    %% Public route
    IGW --- RT_PUB
    RT_PUB --- PUB_A
    RT_PUB --- PUB_B

    %% NAT GW flows
    PUB_A -->|"NAT GW A"| RT_PRIV_A
    PUB_B -->|"NAT GW B"| RT_PRIV_B
    RT_PRIV_A --- SYS_A
    RT_PRIV_A --- WKL_A
    RT_PRIV_B --- SYS_B
    RT_PRIV_B --- WKL_B

    %% Data tier
    SYS_A -.->|"5432/tcp"| RDS_INST
    SYS_B -.->|"5432/tcp"| RDS_INST
    GITLAB_EC2 -.->|"private"| SYS_A

    %% Flow logs
    VPC -.->|"VPC Flow Logs"| CW["☁️ CloudWatch Logs<br/><i>365-day retention</i>"]
```

**Traffic Flow Summary:**

| Path | Route |
|------|-------|
| Internet → EKS services | Internet → IGW → ALB (public subnet) → Target pods (private-system subnet) |
| Internet → GitLab | Internet → IGW → ALB (public subnet) → EC2 (private subnet) |
| Pods → Internet (e.g., AI APIs) | Pod → NAT GW (public subnet) → IGW → Internet |
| Pod → RDS | Pod (private subnet) → RDS endpoint (private subnet, same VPC) |

---

## 3a. Security Groups & Port-Level Access

Five security groups control network access across the deployment. The EKS module creates two automatically (cluster SG, node SG); the remaining three are explicit Terraform resources. All follow least-privilege: every ingress rule names its source, and no security group allows `0.0.0.0/0` inbound except the ALBs on ports 80/443.

```mermaid
graph TB
    INTERNET3(("Internet"))

    subgraph PUBLIC["Public Subnets"]
        ALB_EKS3["ALB: EKS Services\n<i>SG: managed by ALB Controller</i>\n───────\nIngress: 443/tcp from 0.0.0.0/0\nEgress: target pods via node SG"]
        ALB_GL3["ALB: GitLab\n<i>SG: gitlab-alb</i>\n───────\nIngress: 80,443/tcp from 0.0.0.0/0\nEgress: 80/tcp → gitlab-ec2 SG"]
    end

    subgraph PRIVATE_SYS["Private-System Subnets"]
        EKS_NODE3["EKS Node SG\n<i>SG: coder4gov-eks-node</i>\n───────\nTagged: karpenter.sh/discovery\nIngress: all from cluster SG\nIngress: all from self (node↔node)\nEgress: all outbound"]
        EKS_CLUSTER3["EKS Cluster SG\n<i>SG: coder4gov-eks-cluster</i>\n───────\nIngress: 443/tcp from node SG\nEgress: all to node SG"]
        GL_EC23["GitLab EC2\n<i>SG: gitlab-ec2</i>\n───────\nIngress: 80/tcp from gitlab-alb SG ONLY\nIngress: 22/tcp DISABLED (GL-016)\nEgress: all (S3, SES, ECR, packages)"]
    end

    subgraph PRIVATE_DATA["Private Subnets (data tier)"]
        RDS3["RDS PostgreSQL\n<i>SG: coder4gov-rds</i>\n───────\nIngress: 5432/tcp from VPC CIDR\nIngress: 5432/tcp from EKS node SG\nEgress: all outbound"]
    end

    %% Internet → ALBs
    INTERNET3 -->|"443/tcp HTTPS"| ALB_EKS3
    INTERNET3 -->|"80,443/tcp"| ALB_GL3

    %% ALBs → backends
    ALB_EKS3 -->|"target-type: ip\npod IPs in node SG"| EKS_NODE3
    ALB_GL3 -->|"80/tcp"| GL_EC23

    %% Cluster ↔ Node
    EKS_CLUSTER3 <-->|"443/tcp API\nall node comms"| EKS_NODE3

    %% Nodes → RDS
    EKS_NODE3 -->|"5432/tcp\nCoder, LiteLLM, Keycloak"| RDS3
    GL_EC23 -.->|"no direct DB access\n(not in SG rule)"| RDS3

    %% Nodes → Internet (via NAT)
    EKS_NODE3 -->|"all outbound\nvia NAT GW"| INTERNET3
    GL_EC23 -->|"all outbound\nvia NAT GW"| INTERNET3
```

### Port Matrix

Every allowed port in the system:

| Source | Destination | Port | Protocol | Purpose | Terraform Resource |
|--------|-------------|------|----------|---------|--------------------|
| `0.0.0.0/0` | GitLab ALB SG | 443 | TCP | HTTPS from internet | `5-gitlab/security-groups.tf` |
| `0.0.0.0/0` | GitLab ALB SG | 80 | TCP | HTTP → HTTPS redirect | `5-gitlab/security-groups.tf` |
| GitLab ALB SG | GitLab EC2 SG | 80 | TCP | ALB → GitLab (TLS terminated at ALB) | `5-gitlab/security-groups.tf` |
| `0.0.0.0/0` | EKS ALB (managed) | 443 | TCP | HTTPS to Coder/Keycloak/Grafana | ALB Controller annotations |
| EKS ALB | EKS Node SG | pod ports | TCP | ALB → target pods (IP mode) | ALB Controller target-type: ip |
| EKS Node SG | EKS Cluster SG | 443 | TCP | kubelet → API server | EKS module (auto-created) |
| EKS Cluster SG | EKS Node SG | all | TCP | API server → kubelets, webhooks | EKS module (auto-created) |
| EKS Node SG | EKS Node SG | all | all | Pod-to-pod (CNI, Istio mTLS) | EKS module (auto-created) |
| EKS Node SG | RDS SG | 5432 | TCP | Coder/LiteLLM/Keycloak → Postgres | `3-eks/main.tf` |
| VPC CIDR | RDS SG | 5432 | TCP | Broad VPC access (fallback) | `2-data/rds.tf` |
| GitLab EC2 SG | `0.0.0.0/0` | all | all | Outbound (S3, SES, ECR, apt) | `5-gitlab/security-groups.tf` |
| EKS Node SG | `0.0.0.0/0` | all | all | Outbound via NAT (AI APIs, ECR, etc.) | EKS module (auto-created) |

### What Is NOT Allowed

| Blocked Path | Why | Enforcement |
|---|---|---|
| Internet → GitLab EC2 directly | No public IP, no SG ingress from `0.0.0.0/0` | SG + private subnet |
| Internet → EKS nodes directly | No public IP, private subnets only | Subnet routing |
| Internet → RDS | No public access, private subnets, SG restricted | `publicly_accessible = false` + SG |
| SSH (port 22) → GitLab EC2 | SSH disabled per GL-016 | SG rule absent (empty `allowed_ssh_cidrs`) |
| SSH → EKS nodes | No SSH key pair, no SG rule | EKS module config |
| GitLab EC2 → RDS | Not in the EKS Node SG, no SG rule for GitLab→RDS | Explicit omission |
| Pod → Pod (cross-namespace, no mesh) | Istio STRICT mTLS on coder/litellm/keycloak namespaces | PeerAuthentication |

---

## 3b. Ingress & Egress Traffic Flows

Detailed path for every traffic type entering or leaving the VPC.

```mermaid
sequenceDiagram
    actor User
    participant WAF as AWS WAF
    participant ALB as ALB (public subnet)
    participant ISTIO as Istio Sidecar
    participant Pod as App Pod (private subnet)
    participant NAT as NAT Gateway
    participant ExtAPI as External API (OpenAI, etc.)

    Note over User,Pod: === INGRESS: User → Coder ===
    User->>WAF: HTTPS :443 (dev.coder4gov.com)
    WAF->>WAF: Evaluate rules (CRS, Bot Control)
    WAF->>ALB: Allowed request
    ALB->>ALB: TLS termination (ACM cert)
    ALB->>ISTIO: HTTP → pod IP (target-type: ip)
    ISTIO->>Pod: mTLS (Istio STRICT)
    Pod-->>ISTIO: Response
    ISTIO-->>ALB: Response
    ALB-->>User: HTTPS response

    Note over Pod,ExtAPI: === EGRESS: Pod → AI API ===
    Pod->>NAT: HTTPS :443 (api.openai.com)
    NAT->>ExtAPI: HTTPS via IGW + EIP
    ExtAPI-->>NAT: Response
    NAT-->>Pod: Response

    Note over Pod,Pod: === EAST-WEST: Pod → Pod ===
    Pod->>ISTIO: App request (e.g., Coder → LiteLLM)
    ISTIO->>ISTIO: mTLS handshake (Istio CA)
    ISTIO->>Pod: Decrypted request
```

### Egress Destinations

All outbound connections from the VPC route through NAT Gateways (one per AZ) with static Elastic IPs. This is relevant for IP allowlisting on external services.

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| LiteLLM pods | `bedrock-runtime.us-west-2.amazonaws.com` | 443 | Bedrock API (Claude models) — FIPS endpoint |
| LiteLLM pods | `api.openai.com` | 443 | OpenAI API (GPT-5.4, Codex) |
| LiteLLM pods | `generativelanguage.googleapis.com` | 443 | Gemini API |
| ESO pods | `secretsmanager.us-west-2.amazonaws.com` | 443 | Secrets Manager — FIPS endpoint |
| EKS nodes | `api.ecr.us-west-2.amazonaws.com` | 443 | ECR image pulls — FIPS endpoint |
| EKS nodes | `eks.us-west-2.amazonaws.com` | 443 | EKS API — FIPS endpoint |
| Loki pods | `s3.us-west-2.amazonaws.com` | 443 | S3 log storage — FIPS endpoint |
| GitLab EC2 | `email-smtp.us-west-2.amazonaws.com` | 587 | SES SMTP (TLS STARTTLS) |
| GitLab EC2 | `packages.gitlab.com`, apt repos | 443 | Package updates |
| All pods | `169.254.169.254` | 80 | IMDS (instance metadata — disabled for pods via IRSA) |

---

## 4. EKS Cluster Architecture

The EKS cluster uses a two-tier node model: a managed **system node group** for platform services and a **Karpenter-managed workspace pool** for developer workspaces. The system nodes carry a `CriticalAddonsOnly` taint to prevent workspace pods from being scheduled on them. VPC-CNI prefix delegation is enabled for high pod density.

```mermaid
graph TB
    subgraph EKS_CLUSTER["EKS Cluster: coder4gov (Kubernetes 1.32)"]
        subgraph CP["EKS Control Plane (AWS-managed)"]
            API["K8s API Server<br/><i>Public + Private endpoints</i>"]
            ETCD["etcd<br/><i>Encrypted with KMS CMK</i>"]
        end

        subgraph SYSTEM_NG["System Node Group<br/><b>m7a.xlarge</b> (4 vCPU / 16 GiB)<br/>ON_DEMAND · 2–4 nodes<br/>100 GiB gp3 root disk"]
            direction LR
            SYS_LABEL["Label: scheduling.coder.com/pool=system<br/>Taint: CriticalAddonsOnly=:NoSchedule"]

            subgraph PLATFORM_SERVICES["Platform Services"]
                PS_CODER["Coder coderd"]
                PS_PROV["Coder Provisioner"]
                PS_LITELLM["LiteLLM"]
                PS_KC["Keycloak"]
            end

            subgraph OBSERVABILITY["Observability"]
                OBS_GRAFANA["Grafana"]
                OBS_LOKI["Loki"]
                OBS_PROM["Prometheus"]
            end

            subgraph MESH_AND_GITOPS["Mesh & GitOps"]
                MG_ISTIO["Istiod"]
                MG_FLUX["FluxCD<br/><i>source, kustomize,<br/>helm, notification</i>"]
            end

            subgraph INFRA_CTRL["Infrastructure Controllers"]
                IC_ESO["External Secrets Operator"]
                IC_KARP["Karpenter Controller"]
                IC_ALB["ALB Controller"]
                IC_EBS["EBS CSI Driver"]
                IC_VPC["VPC CNI<br/><i>prefix delegation</i>"]
            end
        end

        subgraph WORKSPACE_NP["Workspace NodePool (Karpenter-managed)<br/><b>m7a/m7i .xlarge → .4xlarge</b><br/>SPOT + ON_DEMAND · consolidation enabled<br/>200 GiB gp3 KMS-encrypted EBS"]
            direction LR
            WS_LABEL["Label: scheduling.coder.com/pool=workspaces<br/>No taint (open scheduling)"]

            WS_POD1["🖥️ Workspace Pod<br/><i>dev-alice</i>"]
            WS_POD2["🖥️ Workspace Pod<br/><i>dev-bob</i>"]
            WS_POD3["🖥️ Workspace Pod<br/><i>dev-carol</i>"]
        end
    end

    subgraph KARPENTER_SPEC["Karpenter Configuration"]
        NC["EC2NodeClass: coder<br/>──────────<br/>AMI: AL2023@latest<br/>Subnets: workload-tagged<br/>SG: karpenter.sh/discovery<br/>EBS: 200Gi gp3 KMS-encrypted"]
        NP["NodePool: workspaces<br/>──────────<br/>Types: m7a.xlarge–4xlarge, m7i.xlarge–4xlarge<br/>Capacity: spot + on-demand<br/>AZs: us-west-2a, us-west-2b<br/>Limits: 200 CPU / 800Gi RAM<br/>Consolidation: WhenEmptyOrUnderutilized (5m)<br/>Expiry: 720h (30 days)"]
    end

    API --> SYSTEM_NG
    API --> WORKSPACE_NP
    IC_KARP -->|"Provisions nodes"| WORKSPACE_NP
    NC -.-> WORKSPACE_NP
    NP -.-> WORKSPACE_NP
    PS_PROV -->|"Creates workspace pods"| WORKSPACE_NP
```

---

## 5. Authentication & SSO Flow

All user-facing services (Coder, GitLab, Grafana) delegate authentication to Keycloak at `sso.coder4gov.com` using OpenID Connect (OIDC). Keycloak is the single source of identity and supports WebAuthn/passkey as the primary authentication mechanism. The OIDC authorization code flow is shown below.

### 5.1 Coder Login (Primary Flow)

```mermaid
sequenceDiagram
    actor User
    participant Browser
    participant Coder as Coder<br/>dev.coder4gov.com
    participant KC as Keycloak<br/>sso.coder4gov.com

    User->>Browser: Navigate to dev.coder4gov.com
    Browser->>Coder: GET /
    Coder->>Browser: 302 Redirect to Keycloak
    Browser->>KC: GET /realms/coder4gov/protocol/openid-connect/auth<br/>?client_id=coder&redirect_uri=...&scope=openid
    KC->>Browser: Login page (WebAuthn / passkey prompt)
    User->>Browser: Authenticate with passkey
    Browser->>KC: POST authentication credentials
    KC->>KC: Validate credentials, create session
    KC->>Browser: 302 Redirect with authorization code
    Browser->>Coder: GET /api/v2/users/oidc/callback?code=AUTH_CODE
    Coder->>KC: POST /realms/coder4gov/protocol/openid-connect/token<br/>Exchange code for tokens
    KC->>Coder: ID token + access token + refresh token
    Coder->>Coder: Validate ID token, extract claims<br/>Create or update user record in RDS
    Coder->>Browser: Set session cookie<br/>302 Redirect to dashboard
    Browser->>User: Coder dashboard loaded ✅
```

### 5.2 GitLab and Grafana SSO (Same Pattern, Different Clients)

```mermaid
sequenceDiagram
    actor User
    participant Browser
    participant App as GitLab / Grafana
    participant KC as Keycloak<br/>sso.coder4gov.com

    User->>Browser: Navigate to gitlab.coder4gov.com<br/>or grafana.dev.coder4gov.com
    Browser->>App: GET /
    App->>Browser: 302 Redirect to Keycloak<br/>?client_id=gitlab (or grafana)
    Browser->>KC: Authorization request
    alt User already has active Keycloak session
        KC->>Browser: 302 Redirect with code (SSO — no re-auth)
    else No session
        KC->>Browser: Login page
        User->>Browser: Authenticate
        Browser->>KC: POST credentials
        KC->>Browser: 302 Redirect with code
    end
    Browser->>App: GET /callback?code=AUTH_CODE
    App->>KC: Exchange code for tokens
    KC->>App: ID token + access token
    App->>Browser: Set session, redirect to app
    Browser->>User: App loaded ✅ (single sign-on)
```

---

## 6. AI Model Routing

Developer workspaces connect to AI models through LiteLLM, a multi-provider proxy that presents a unified OpenAI-compatible API. LiteLLM routes requests to AWS Bedrock (Claude), OpenAI, or Google Gemini based on the model name. Bedrock authentication uses IRSA (IAM Roles for Service Accounts) — no static API keys. OpenAI and Gemini use API keys sourced from AWS Secrets Manager via External Secrets Operator.

```mermaid
sequenceDiagram
    participant WS as Developer Workspace<br/>(Coder IDE / CLI)
    participant CB as Coder AI Integration<br/>(AI Bridge)
    participant LL as LiteLLM Proxy<br/>(litellm namespace)
    participant BR as AWS Bedrock<br/>(us-west-2)
    participant OAI as OpenAI API
    participant GEM as Google Gemini API

    Note over WS,LL: All internal traffic is mTLS (Istio STRICT)

    WS->>CB: AI completion request<br/>(OpenAI-compatible format)
    CB->>LL: POST /v1/chat/completions<br/>model: "claude-sonnet"

    alt model = claude-sonnet / claude-opus / claude-haiku
        Note over LL,BR: Auth: IRSA → STS AssumeRoleWithWebIdentity<br/>No API key needed
        LL->>BR: bedrock:InvokeModel<br/>us.anthropic.claude-sonnet-4-6<br/>AWS SigV4 signed
        BR-->>LL: Streaming response
    else model = gpt-5.4 / gpt-5.3-codex / gpt-5.4-mini
        Note over LL,OAI: Auth: API key from K8s Secret<br/>(OPENAI_API_KEY via ESO)
        LL->>OAI: POST /v1/chat/completions<br/>Authorization: Bearer sk-...
        OAI-->>LL: Streaming response
    else model = gemini-3.1-pro / gemini-3-flash
        Note over LL,GEM: Auth: API key from K8s Secret<br/>(GEMINI_API_KEY via ESO)
        LL->>GEM: POST /v1/chat/completions<br/>Authorization: Bearer AI...
        GEM-->>LL: Streaming response
    end

    LL-->>CB: Stream tokens back
    CB-->>WS: Display completion in IDE
    LL->>LL: Log request to RDS<br/>(token count, latency, model)
```

### Model Catalog

| Model Alias | Provider | Underlying Model ID | Auth Method |
|-------------|----------|---------------------|-------------|
| `claude-sonnet` | AWS Bedrock | `us.anthropic.claude-sonnet-4-6` | IRSA (SigV4) |
| `claude-opus` | AWS Bedrock | `us.anthropic.claude-opus-4-6-v1` | IRSA (SigV4) |
| `claude-haiku` | AWS Bedrock | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | IRSA (SigV4) |
| `gpt-5.4` | OpenAI | `openai/gpt-5.4` | API key |
| `gpt-5.3-codex` | OpenAI | `openai/gpt-5.3-codex` | API key |
| `gpt-5.4-mini` | OpenAI | `openai/gpt-5.4-mini` | API key |
| `gemini-3.1-pro` | Google | `gemini/gemini-3.1-pro-preview` | API key |
| `gemini-3-flash` | Google | `gemini/gemini-3-flash-preview` | API key |

---

## 7. GitOps Reconciliation Flow

All Kubernetes application state is managed declaratively via FluxCD. Code changes flow from developer commits through GitLab to FluxCD, which reconciles the desired state against the cluster. FluxCD polls the Git repository every 5 minutes and reconciles Kustomizations every 10 minutes.

```mermaid
graph LR
    subgraph DEV["Developer"]
        COMMIT["git push"]
    end

    subgraph GITHUB["GitHub"]
        GH_REPO["github.com/coder/gov.demo.coder.com<br/><i>Source of truth</i>"]
    end

    subgraph GITLAB_INST["GitLab CE (gitlab.coder4gov.com)"]
        GL_MIRROR["Mirror Repository<br/><i>Pull mirror from GitHub</i>"]
    end

    subgraph FLUX_SYSTEM["FluxCD (flux-system namespace)"]
        SRC_CTRL["Source Controller<br/><i>GitRepository: platform</i><br/><i>Interval: 5m</i>"]
        KUST_CTRL["Kustomize Controller<br/><i>Kustomization: platform</i><br/><i>Path: ./clusters/gov-demo</i><br/><i>Interval: 10m, Prune: true</i>"]
        HELM_CTRL["Helm Controller<br/><i>Processes HelmRelease CRs</i>"]
        NOTIF_CTRL["Notification Controller<br/><i>Status reporting</i>"]
    end

    subgraph K8S_RESOURCES["Kubernetes Cluster"]
        NS["Namespaces<br/><i>coder, keycloak, litellm,<br/>monitoring, flux-system</i>"]
        HR_CODER["HelmRelease: coder<br/><i>coder/coder chart v2.*</i>"]
        HR_KC["HelmRelease: keycloak<br/><i>bitnami/keycloak v24.*</i>"]
        HR_LL["HelmRelease: litellm<br/><i>litellm-helm v0.*</i>"]
        HR_MON["HelmRelease: coder-observability<br/><i>Grafana + Loki + Prometheus</i>"]
        SECRETS["ExternalSecrets<br/><i>coder-db, litellm-keys,<br/>keycloak-db, coder-license</i>"]
    end

    COMMIT -->|Push| GH_REPO
    GH_REPO -->|"Pull mirror"| GL_MIRROR
    GL_MIRROR -->|"HTTPS poll (5m)"| SRC_CTRL
    SRC_CTRL -->|"New revision detected"| KUST_CTRL
    KUST_CTRL -->|"Apply manifests"| NS
    KUST_CTRL -->|"Apply manifests"| SECRETS
    KUST_CTRL -->|"Create/update CRs"| HR_CODER
    KUST_CTRL -->|"Create/update CRs"| HR_KC
    KUST_CTRL -->|"Create/update CRs"| HR_LL
    KUST_CTRL -->|"Create/update CRs"| HR_MON
    HELM_CTRL -->|"Reconcile Helm charts"| HR_CODER
    HELM_CTRL -->|"Reconcile Helm charts"| HR_KC
    HELM_CTRL -->|"Reconcile Helm charts"| HR_LL
    HELM_CTRL -->|"Reconcile Helm charts"| HR_MON
    NOTIF_CTRL -.->|"Status webhook"| GL_MIRROR
```

### Repository Layout

```
clusters/gov-demo/
├── infrastructure/
│   ├── kustomization.yaml      # Root kustomization
│   ├── namespaces.yaml         # Namespace definitions
│   ├── sources/                # HelmRepository sources
│   │   ├── coder.yaml
│   │   ├── coder-observability.yaml
│   │   ├── litellm.yaml
│   │   └── bitnami.yaml
│   └── secrets/                # ExternalSecret definitions
│       ├── coder-db.yaml
│       ├── coder-license.yaml
│       ├── litellm-keys.yaml
│       └── keycloak-db.yaml
└── apps/                       # HelmRelease definitions
    ├── coder-server/
    ├── coder-provisioner/
    ├── keycloak/
    ├── litellm/
    └── monitoring/
```

---

## 8. Secret Management Flow

All secrets are stored in AWS Secrets Manager, encrypted with a KMS Customer Managed Key. The External Secrets Operator (ESO) synchronizes secrets into Kubernetes using IRSA-authenticated access. Secrets refresh every hour.

```mermaid
graph LR
    subgraph AWS_SM["AWS Secrets Manager"]
        SEC_RDS["coder4gov/rds-master-password<br/><i>{username, password, host, port, dbname}</i>"]
        SEC_OAI["coder4gov/openai-api-key<br/><i>{api_key}</i>"]
        SEC_GEM["coder4gov/gemini-api-key<br/><i>{api_key}</i>"]
        SEC_LIC["coder4gov/coder-license<br/><i>{license}</i>"]
        SEC_SES["coder4gov/ses-smtp-credentials<br/><i>{smtp_username, smtp_password, endpoint}</i>"]
    end

    KMS_KEY["🔐 KMS CMK<br/><i>alias/coder4gov</i><br/>Auto-rotation enabled"]

    subgraph K8S_ESO["Kubernetes — External Secrets Operator"]
        CSS["ClusterSecretStore<br/><b>aws-secrets-manager</b><br/><i>Provider: AWS SecretsManager</i><br/><i>Auth: IRSA JWT</i>"]
        IRSA_ESO["IRSA Role<br/><i>coder4gov-eso-*</i><br/>Scoped to:<br/>secretsmanager:GetSecretValue<br/>on coder4gov/*"]

        subgraph EXT_SECRETS["ExternalSecret Resources"]
            ES_CDB["ExternalSecret<br/><b>coder-db-credentials</b><br/><i>ns: coder</i><br/>Refresh: 1h"]
            ES_LK["ExternalSecret<br/><b>litellm-api-keys</b><br/><i>ns: litellm</i><br/>Refresh: 1h"]
            ES_KDB["ExternalSecret<br/><b>keycloak-db-credentials</b><br/><i>ns: keycloak</i><br/>Refresh: 1h"]
            ES_LIC["ExternalSecret<br/><b>coder-license</b><br/><i>ns: coder</i><br/>Refresh: 1h"]
        end

        subgraph K8S_SECRETS["Kubernetes Secrets (auto-created)"]
            KS_CDB["Secret: coder-db-credentials"]
            KS_LK["Secret: litellm-api-keys<br/><i>OPENAI_API_KEY, GEMINI_API_KEY</i>"]
            KS_KDB["Secret: keycloak-db-credentials"]
            KS_LIC["Secret: coder-license"]
        end
    end

    subgraph CONSUMERS["Pod Consumers"]
        POD_CODER["Coder coderd<br/><i>env: CODER_PG_CONNECTION_URL</i>"]
        POD_LL["LiteLLM<br/><i>env: OPENAI_API_KEY,<br/>GEMINI_API_KEY</i>"]
        POD_KC["Keycloak<br/><i>env: DB password</i>"]
    end

    %% Encryption
    SEC_RDS -.->|"Encrypted with"| KMS_KEY
    SEC_OAI -.->|"Encrypted with"| KMS_KEY
    SEC_GEM -.->|"Encrypted with"| KMS_KEY
    SEC_LIC -.->|"Encrypted with"| KMS_KEY
    SEC_SES -.->|"Encrypted with"| KMS_KEY

    %% ESO flow
    CSS -->|"IRSA auth"| IRSA_ESO
    ES_CDB -->|"remoteRef"| CSS
    ES_LK -->|"remoteRef"| CSS
    ES_KDB -->|"remoteRef"| CSS
    ES_LIC -->|"remoteRef"| CSS

    CSS -->|"GetSecretValue"| SEC_RDS
    CSS -->|"GetSecretValue"| SEC_OAI
    CSS -->|"GetSecretValue"| SEC_GEM
    CSS -->|"GetSecretValue"| SEC_LIC

    %% Secret creation
    ES_CDB -->|"creates"| KS_CDB
    ES_LK -->|"creates"| KS_LK
    ES_KDB -->|"creates"| KS_KDB
    ES_LIC -->|"creates"| KS_LIC

    %% Pod consumption
    KS_CDB -->|"env/volume mount"| POD_CODER
    KS_LK -->|"env vars"| POD_LL
    KS_KDB -->|"env var"| POD_KC
    KS_LIC -->|"env/volume mount"| POD_CODER
```

---

## 9. Terraform Layer Dependency Graph

Infrastructure is decomposed into six Terraform layers (0–5) that form a directed acyclic graph. Each layer reads outputs from previous layers via `terraform_remote_state`. This enables independent planning/applying and minimizes blast radius. Layer 4 optionally bootstraps FluxCD, which then takes over application lifecycle via GitOps.

```mermaid
graph TD
    L0["<b>Layer 0 — State Backend</b><br/><i>0-state/</i><br/>──────────<br/>• S3 bucket (terraform state)<br/>• DynamoDB (state locking)<br/>• KMS key (state encryption)<br/>──────────<br/><i>Local state (bootstrap)</i>"]

    L1["<b>Layer 1 — Network</b><br/><i>1-network/</i><br/>──────────<br/>• VPC (10.0.0.0/16)<br/>• 6 subnets (2 AZs × 3 tiers)<br/>• IGW, 2× NAT GW, route tables<br/>• Route 53 zone<br/>• ACM certs (wildcard + apex)<br/>• VPC Flow Logs"]

    L2["<b>Layer 2 — Data</b><br/><i>2-data/</i><br/>──────────<br/>• KMS CMK (encrypts everything)<br/>• RDS PostgreSQL 15 (Multi-AZ)<br/>• S3 × 3 (gitlab, loki, general)<br/>• ECR × 3 (coder, base-fips, desktop-fips)<br/>• Secrets Manager × 5<br/>• SES (domain + SMTP)<br/>• OpenSearch Serverless (SIEM)"]

    L3["<b>Layer 3 — EKS</b><br/><i>3-eks/</i><br/>──────────<br/>• EKS cluster (K8s 1.32)<br/>• System node group (m7a.xlarge)<br/>• IRSA roles × 4<br/>• Cluster add-ons (VPC-CNI, CoreDNS,<br/>  kube-proxy, EBS CSI)<br/>• EKS → RDS SG rule"]

    L4["<b>Layer 4 — Bootstrap</b><br/><i>4-bootstrap/</i><br/>──────────<br/>• Karpenter (controller + NodePool)<br/>• Istio (base + istiod + STRICT mTLS)<br/>• ALB Controller (IRSA + Helm)<br/>• External Secrets (IRSA + Helm +<br/>  ClusterSecretStore)<br/>• WAF Web ACL (EKS services)<br/>• FluxCD (optional, gated)"]

    L5["<b>Layer 5 — GitLab</b><br/><i>5-gitlab/</i><br/>──────────<br/>• EC2 launch template (m7a.2xlarge)<br/>• ASG (min=1, max=1)<br/>• ALB + HTTPS listener<br/>• WAF Web ACL (GitLab)<br/>• Route 53 A record<br/>• IAM instance profile"]

    FLUX_APPS["<b>FluxCD → Apps</b><br/><i>clusters/gov-demo/</i><br/>──────────<br/>• Coder server + provisioner<br/>• Keycloak<br/>• LiteLLM<br/>• Monitoring (Grafana/Loki/Prom)<br/>• ExternalSecrets"]

    %% Dependencies with key outputs
    L0 -->|"s3_bucket, dynamo_table,<br/>kms_key_arn"| L1
    L1 -->|"vpc_id, subnet_ids,<br/>route53_zone_id,<br/>acm_cert_arns"| L2
    L1 -->|"vpc_id, subnet_ids"| L3
    L2 -->|"kms_key_arn, rds_sg_id,<br/>rds_endpoint, s3_bucket_arns,<br/>ecr_repo_urls, secret_arns"| L3
    L3 -->|"cluster_name, cluster_endpoint,<br/>oidc_provider_arn,<br/>node_sg_id, irsa_role_arns"| L4
    L2 -->|"kms_key_arn, rds_endpoint"| L4
    L1 -->|"public_subnet_ids,<br/>route53_zone_id, acm_cert_arn"| L5
    L2 -->|"kms_key_arn, s3_bucket_names"| L5
    L4 -->|"waf_acl_arn"| L5

    L4 -.->|"FluxCD reconciles<br/>clusters/gov-demo/"| FLUX_APPS
    L5 -.->|"GitLab repo URL<br/>feeds FluxCD"| FLUX_APPS

    style L0 fill:#e8f5e9,stroke:#4caf50,stroke-width:2px
    style L1 fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style L2 fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style L3 fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style L4 fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style L5 fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style FLUX_APPS fill:#fff3e0,stroke:#ff9800,stroke-width:2px
```

### Layer Output → Consumer Map

| Source Layer | Key Output | Consumer |
|-------------|-----------|----------|
| L0 | `s3_bucket`, `dynamodb_table`, `kms_key_arn` | All layers (backend config) |
| L1 | `vpc_id`, `vpc_cidr` | L2, L3, L5 |
| L1 | `public_subnet_ids` | L5 (ALB) |
| L1 | `private_system_subnet_ids` | L3 (EKS system nodes) |
| L1 | `private_workload_subnet_ids` | L3 (EKS), L4 (Karpenter) |
| L1 | `route53_zone_id` | L2 (SES), L5 (GitLab DNS) |
| L1 | `acm_wildcard_cert_arn` | L5 (GitLab ALB), FluxCD apps (Ingress) |
| L2 | `kms_key_arn` | L3 (EKS encryption), L4 (Karpenter EBS), L5 (GitLab EBS) |
| L2 | `rds_endpoint`, `rds_security_group_id` | L3 (SG rule), FluxCD apps (DB connection) |
| L2 | `secret_arns` | L4 (ESO policy scope) |
| L3 | `cluster_name`, `cluster_endpoint` | L4 (all Helm charts), L5 |
| L3 | `oidc_provider_arn` | L4 (IRSA roles for ESO, ALB, Karpenter) |
| L3 | `irsa_role_arns` | FluxCD apps (service account annotations) |
| L4 | `waf_web_acl_arn` | FluxCD apps (ALB Ingress annotations) |

---

## 10. FIPS Compliance Architecture

FIPS 140-2/140-3 compliance is enforced at every layer of the stack — from AWS API calls through the application runtime down to workspace container images. This diagram shows all FIPS enforcement points.

```mermaid
graph TB
    subgraph TRANSIT["Encryption in Transit"]
        T1["TLS 1.2+ enforced on all connections<br/><i>ALB: ELBSecurityPolicy-TLS13-1-2-2021-06</i>"]
        T2["Istio mTLS STRICT<br/><i>All east-west pod traffic</i><br/><i>Namespaces: coder, litellm, keycloak, istio-system</i>"]
        T3["RDS force_ssl = 1<br/><i>Rejects non-TLS PostgreSQL connections</i>"]
        T4["S3 bucket policies<br/><i>Deny aws:SecureTransport=false</i><br/><i>Deny s3:TlsVersion < 1.2</i>"]
    end

    subgraph REST["Encryption at Rest"]
        R1["KMS CMK (alias/coder4gov)<br/><i>Auto-rotation enabled</i><br/><i>Encrypts: RDS, S3, EBS, ECR,<br/>Secrets Manager, OpenSearch</i>"]
        R2["EKS Secrets encryption<br/><i>cluster_encryption_config → KMS CMK</i>"]
        R3["EBS gp3 volumes<br/><i>KMS-encrypted (system + workspace nodes)</i>"]
        R4["Terraform state bucket<br/><i>SSE-KMS with dedicated state key</i>"]
    end

    subgraph API_FIPS["AWS FIPS API Endpoints"]
        F1["use_fips_endpoint = true<br/><i>All Terraform providers</i>"]
        F2["FIPS endpoints for:<br/>• S3, KMS, STS, EC2<br/>• Secrets Manager, RDS<br/>• EKS, ECR, SES"]
    end

    subgraph APP_FIPS["Application-Level FIPS"]
        A1["Coder Binary<br/><i>Built with GOFIPS140=latest</i><br/><i>Go FIPS 140-3 cryptographic module</i><br/><i>GOEXPERIMENT=systemcrypto</i>"]
        A2["Workspace Images<br/><i>RHEL 9 UBI base</i><br/><i>crypto-policies set to FIPS</i><br/><i>update-crypto-policies --set FIPS</i>"]
        A3["GitLab EC2<br/><i>AL2023 with FIPS kernel</i><br/><i>fips-mode-setup --enable</i>"]
    end

    subgraph AUDIT["Audit & Logging"]
        AU1["VPC Flow Logs → CloudWatch<br/><i>365-day retention</i>"]
        AU2["CloudTrail → OpenSearch SIEM"]
        AU3["WAF Logs → CloudWatch<br/><i>90-day retention</i>"]
        AU4["Coder audit logging enabled<br/><i>CODER_AUDIT_LOGGING=true</i>"]
        AU5["RDS log_connections = 1<br/>RDS log_disconnections = 1<br/>RDS log_statement = ddl"]
    end

    TRANSIT --- REST
    REST --- API_FIPS
    API_FIPS --- APP_FIPS
    APP_FIPS --- AUDIT
```

### FIPS Enforcement Checklist

| Layer | Control | Configuration |
|-------|---------|---------------|
| **AWS API** | FIPS endpoints | `use_fips_endpoint = true` in all providers |
| **Network** | TLS 1.2+ only | ALB policy `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| **Service mesh** | mTLS STRICT | Istio PeerAuthentication in coder, litellm, keycloak, istio-system |
| **Database** | Force SSL | RDS parameter `rds.force_ssl = 1` |
| **Storage** | KMS-CMK encryption | All S3 buckets use `aws:kms` with CMK |
| **Storage** | Deny insecure transport | S3 bucket policies block non-TLS and TLS < 1.2 |
| **Compute** | FIPS crypto | Coder built with `GOFIPS140=latest` |
| **Compute** | FIPS kernel | GitLab EC2 on AL2023 FIPS mode |
| **Workspace** | FIPS crypto-policies | RHEL 9 UBI images with FIPS mode |
| **Secrets** | KMS-CMK encryption | All Secrets Manager secrets use CMK |
| **EKS** | Envelope encryption | etcd secrets encrypted with KMS CMK |
| **Disk** | KMS-CMK encryption | All EBS volumes (system + workspace) KMS-encrypted |

---

## 11. Disaster Recovery & Backup Architecture

The platform is designed for rapid recovery. Stateful data is backed up with configurable retention. Stateless infrastructure can be fully reconstructed from Terraform state and Git repositories.

```mermaid
graph TB
    subgraph STATEFUL["Stateful Components — What's Backed Up"]
        subgraph RDS_BACKUP["RDS PostgreSQL"]
            RDS_INST2["RDS Instance<br/><i>3 databases: coder, litellm, keycloak</i>"]
            RDS_SNAP["Automated Snapshots<br/><i>Daily, 03:00–04:00 UTC</i><br/><i>Retention: 7 days (configurable)</i>"]
            RDS_MAZ["Multi-AZ Failover<br/><i>Synchronous standby replica</i><br/><i>Automatic failover on failure</i>"]
            RDS_FINAL["Final Snapshot on Delete<br/><i>skip_final_snapshot = false</i><br/><i>deletion_protection = true</i>"]
        end

        subgraph S3_BACKUP["S3 Buckets"]
            S3_GL2["gitlab-backups<br/><i>Versioning: ENABLED</i><br/><i>All versions retained</i>"]
            S3_LK2["loki-logs<br/><i>Lifecycle: → IA after 90 days</i>"]
            S3_GN2["general<br/><i>Artifacts storage</i>"]
            S3_TF["terraform-state<br/><i>Versioning: ENABLED</i><br/><i>All versions retained</i>"]
        end

        subgraph GL_BACKUP["GitLab"]
            GL_CRON["Daily Backup Cron<br/><i>gitlab-backup create</i>"]
            GL_S3["Backups → S3<br/><i>gitlab-backups bucket</i>"]
            GL_EBS["Data Volume (gp3)<br/><i>delete_on_termination = false</i><br/><i>Persists across instance replacement</i>"]
        end

        subgraph SECRETS_BACKUP["Secrets Manager"]
            SM_VER["Automatic Versioning<br/><i>Previous versions retained</i>"]
            SM_KMS2["KMS CMK Encryption<br/><i>Key rotation enabled</i>"]
        end
    end

    subgraph STATELESS["Stateless Components — Rebuilt from Code"]
        subgraph INFRA_REBUILD["Infrastructure (Terraform)"]
            TF_STATE2["Terraform State in S3<br/><i>Versioned, KMS-encrypted</i>"]
            TF_LOCK2["DynamoDB Lock Table<br/><i>PITR enabled</i>"]
            TF_CODE["Terraform Code in Git<br/><i>Full infra defined in 6 layers</i>"]
        end

        subgraph APP_REBUILD["Applications (GitOps)"]
            GIT_REPO["Git Repository<br/><i>clusters/gov-demo/</i><br/><i>Full app stack defined declaratively</i>"]
            FLUX_REC["FluxCD Reconciliation<br/><i>Auto-recovers all K8s resources</i>"]
        end

        subgraph IMG_REBUILD["Container Images"]
            ECR_REG["ECR Repositories<br/><i>30 tagged images retained</i><br/><i>Scan on push enabled</i>"]
            CI_PIPE["CI Pipelines<br/><i>Can rebuild any image from source</i>"]
        end
    end

    RDS_INST2 --> RDS_SNAP
    RDS_INST2 --> RDS_MAZ
    RDS_INST2 --> RDS_FINAL
    GL_CRON --> GL_S3
    TF_STATE2 --> TF_CODE
    GIT_REPO --> FLUX_REC

    subgraph RTO_RPO["Recovery Targets"]
        RTO["<b>RTO (Recovery Time Objective)</b><br/>──────────<br/>EKS + Apps: ~30 min (Terraform + FluxCD)<br/>RDS: ~5 min (Multi-AZ failover)<br/>GitLab: ~15 min (ASG self-healing)"]
        RPO["<b>RPO (Recovery Point Objective)</b><br/>──────────<br/>RDS: ~5 min (sync replication)<br/>S3: 0 (versioned, durable)<br/>GitLab: up to 24h (daily backup)<br/>Secrets: 0 (API-updated immediately)"]
    end
```

### Recovery Playbooks

| Failure Scenario | Recovery Method | Estimated Time |
|-----------------|-----------------|----------------|
| Single EKS node failure | Karpenter auto-replaces workspace nodes; ASG replaces system nodes | 2–5 min |
| AZ outage | Multi-AZ: RDS failover, EKS reschedules to surviving AZ, NAT GW per-AZ | 5–10 min |
| RDS instance failure | Automatic Multi-AZ failover to standby | ~5 min |
| GitLab instance failure | ASG launches new instance, EBS data volume persists | 10–15 min |
| Full cluster loss | `terraform apply` layers 0–4, FluxCD reconciles apps from Git | ~30 min |
| Accidental secret deletion | Restore from Secrets Manager version history | < 1 min |
| Terraform state corruption | Restore previous version from S3 versioning | < 5 min |

---

## 12. WAF & Security Boundary

All public-facing services are protected by AWS WAF Web ACLs. There are two independent WAF ACLs: one for EKS-hosted services (Coder, Keycloak, Grafana) created in Layer 4, and one for GitLab created in Layer 5. Internal pod-to-pod traffic is secured by Istio mTLS.

```mermaid
graph TB
    INTERNET2(("🌍 Internet<br/><i>Untrusted</i>"))

    subgraph EDGE_SECURITY["Edge Security Layer"]
        R53_2["Route 53<br/><i>*.coder4gov.com</i><br/><i>DNS resolution</i>"]

        subgraph WAF_LAYER["AWS WAF v2"]
            subgraph WAF_EKS2["WAF ACL: EKS Services<br/><i>(Layer 4 — 4-bootstrap/waf.tf)</i>"]
                W_E_R0["P5: Keycloak /admin IP restriction<br/><i>Block non-allowlisted CIDRs</i>"]
                W_E_R1["P10: AWSManagedRulesCommonRuleSet<br/><i>XSS, SQLi, LFI, RFI, etc.</i>"]
                W_E_R2["P20: AWSManagedRulesKnownBadInputsRuleSet<br/><i>Log4j, Java deserialization, etc.</i>"]
                W_E_R3["P30: AWSManagedRulesBotControlRuleSet<br/><i>Block scrapers, allow verified bots</i>"]
            end

            subgraph WAF_GL2["WAF ACL: GitLab<br/><i>(Layer 5 — 5-gitlab/alb.tf)</i>"]
                W_G_R1["P10: AWSManagedRulesCommonRuleSet<br/><i>SizeRestrictions_BODY → count mode</i>"]
                W_G_R2["P20: AWSManagedRulesKnownBadInputsRuleSet"]
                W_G_R3["P30: AWSManagedRulesBotControlRuleSet<br/><i>Inspection: COMMON</i>"]
                W_G_R4["P40: Rate Limiting<br/><i>2,000 req/5min per IP</i>"]
            end
        end
    end

    subgraph ALB_LAYER["Application Load Balancers"]
        ALB_EKS2["ALB: EKS Services<br/><i>TLS termination</i><br/><i>ACM wildcard cert</i><br/><i>Policy: TLS13-1-2-2021-06</i>"]
        ALB_GL2["ALB: GitLab<br/><i>TLS termination</i><br/><i>ACM wildcard cert</i><br/><i>Policy: TLS13-1-2-2021-06</i>"]
    end

    subgraph MESH_LAYER["Service Mesh (Istio)"]
        PROXY_IN["Istio Sidecar (inbound)<br/><i>Envoy proxy</i><br/><i>mTLS STRICT</i>"]
        PROXY_OUT["Istio Sidecar (outbound)<br/><i>Envoy proxy</i><br/><i>mTLS STRICT</i>"]
    end

    subgraph APP_LAYER["Application Pods"]
        POD_C2["Coder<br/><i>dev.coder4gov.com</i>"]
        POD_KC2["Keycloak<br/><i>sso.coder4gov.com</i>"]
        POD_GR2["Grafana<br/><i>grafana.dev.coder4gov.com</i>"]
        POD_LL2["LiteLLM<br/><i>Internal only</i>"]
    end

    subgraph GITLAB_LAYER["GitLab EC2"]
        GL_INST["GitLab CE<br/><i>gitlab.coder4gov.com</i>"]
    end

    %% Flow — EKS path
    INTERNET2 -->|"DNS lookup"| R53_2
    INTERNET2 -->|"HTTPS :443"| WAF_EKS2
    WAF_EKS2 -->|"Allowed traffic"| ALB_EKS2
    ALB_EKS2 -->|"HTTP :80 → target pods"| PROXY_IN
    PROXY_IN -->|"mTLS"| POD_C2
    PROXY_IN -->|"mTLS"| POD_KC2
    PROXY_IN -->|"mTLS"| POD_GR2

    %% Internal pod-to-pod
    POD_C2 <-->|"mTLS (Istio STRICT)"| PROXY_OUT
    PROXY_OUT <-->|"mTLS"| POD_LL2
    PROXY_OUT <-->|"mTLS"| POD_KC2

    %% Flow — GitLab path
    INTERNET2 -->|"HTTPS :443"| WAF_GL2
    WAF_GL2 -->|"Allowed traffic"| ALB_GL2
    ALB_GL2 -->|"HTTP :80 → target"| GL_INST

    %% WAF logging
    WAF_EKS2 -.->|"Logs"| CW_WAF1["CloudWatch<br/><i>aws-waf-logs-coder4gov-eks</i>"]
    WAF_GL2 -.->|"Logs"| CW_WAF2["CloudWatch<br/><i>aws-waf-logs-coder4gov-gitlab</i><br/><i>90-day retention</i>"]
```

### Security Layers Summary

| Layer | Component | Protection |
|-------|-----------|------------|
| **L1 — DNS** | Route 53 | Domain registration, DNSSEC-capable |
| **L2 — WAF** | AWS WAF v2 | Common Rule Set, Bad Inputs, Bot Control, IP restriction, rate limiting |
| **L3 — TLS** | ALB | TLS 1.2+ termination with ACM certs, HSTS headers (63072000s) |
| **L4 — Mesh** | Istio mTLS STRICT | All east-west traffic encrypted, identity-verified |
| **L5 — App** | Coder, Keycloak | OIDC auth, passkey/WebAuthn, audit logging, RBAC |
| **L6 — Data** | RDS, S3, SM | KMS encryption at rest, force SSL, bucket policies |
| **L7 — Audit** | CloudWatch, OpenSearch | VPC Flow Logs, CloudTrail, WAF logs, Coder audit logs |

---

*Last updated: 2025 · Generated from source analysis of `infra/terraform/` and `clusters/gov-demo/`*
