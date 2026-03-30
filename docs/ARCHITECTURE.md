# Architecture — usgov-deploy-aws Reference Architecture

Coder on AWS (GovCloud-portable), FIPS-compliant, multi-AZ.

## Architecture at a Glance

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                      TERRAFORM LAYER CHAIN                             │
│                                                                        │
│  ┌──────────┐   ┌──────────────┐   ┌─────────────┐   ┌────────────┐  │
│  │ 0-state  │──▶│  1-network   │──▶│   2-data    │──▶│   3-eks    │  │
│  │          │   │              │   │             │   │            │  │
│  │ S3 bucket│   │ VPC (multi-AZ│   │ RDS PG 15  │   │ EKS 1.32  │  │
│  │ DynamoDB │   │ 6 subnets   │   │ KMS CMK    │   │ IRSA roles │  │
│  │ (TF lock)│   │ NAT Gateways│   │ ECR repos  │   │ OIDC provdr│  │
│  └──────────┘   │ Route 53    │   │ Secrets Mgr│   └─────┬──────┘  │
│                  │ ACM cert    │   └─────────────┘         │         │
│                  └──────────────┘                           ▼         │
│                                                    ┌──────────────┐  │
│                                                    │ 4-bootstrap  │  │
│                                                    │              │  │
│                                                    │ Karpenter    │  │
│                                                    │ ALB Ctrlr    │  │
│                                                    │ Ext Secrets  │  │
│                                                    │ FluxCD       │  │
│                                                    └──────┬───────┘  │
└───────────────────────────────────────────────────────────┼──────────┘
                                                            │
                         FluxCD reconciles                  │
                         clusters/gov-demo/                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     EKS CLUSTER (coder4gov-eks)                        │
│                                                                        │
│  ┌─────────── System Nodes (m7a.xlarge, ON_DEMAND) ──────────────┐    │
│  │                                                                │    │
│  │  ┌──────────────┐  ┌───────────────────┐  ┌────────────────┐  │    │
│  │  │ coder-server │  │ coder-provisioner │  │   Karpenter    │  │    │
│  │  │   (coderd)   │  │      (×2)         │  │  controller    │  │    │
│  │  └──────┬───────┘  └────────┬──────────┘  └────────────────┘  │    │
│  │         │                   │                                  │    │
│  │  ┌──────────────┐  ┌───────────────────┐                      │    │
│  │  │ ALB Ctrlr    │  │ External Secrets  │                      │    │
│  │  └──────────────┘  └───────────────────┘                      │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  ┌─────────── Karpenter NodePool: workspaces (spot+OD) ──────────┐    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │    │
│  │  │ Workspace A │  │ Workspace B │  │ Workspace …  │           │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘           │    │
│  └────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼
         ┌──────────┐   ┌──────────┐   ┌──────────────┐
         │ RDS PG15 │   │ Secrets  │   │ Route 53     │
         │ (multi-AZ│   │ Manager  │   │ coder4gov.com│
         │  + FIPS) │   │ + KMS    │   │ + ACM cert   │
         └──────────┘   └──────────┘   └──────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  usgov-env-demo (separate repo) layers on top via terraform_remote_state│
│                                                                        │
│  Adds: GitLab CE · Keycloak · LiteLLM · Observability (Grafana/Loki)  │
│        Istio (mTLS) · WAF · OpenSearch (SIEM) · SES                   │
│                                                                        │
│  See: github.com/coder/usgov-env-demo                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

## System Overview

```mermaid
graph TB
    DNS["Route 53<br/>coder4gov.com"]

    subgraph VPC["us-west-2 · VPC · multi-AZ"]
        subgraph EKS["EKS: coder4gov-eks"]
            C[Coder coderd] --- P[Coder provisioner]
            ESO[Ext Secrets] --- K[Karpenter]
            ALB_CTRL[ALB Controller]
        end
        RDS[(RDS PG 15)]
        ECR[ECR]
    end

    AWS[Secrets Mgr · KMS]

    DNS --> C
    C & P --> RDS
    ESO --> AWS
```

## Network Topology

```mermaid
graph TB
    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph AZ_A["AZ-a"]
            PUB_A["Public 10.0.0.0/20<br/>ALB, NAT GW"]
            SYS_A["Private-System 10.0.32.0/20<br/>EKS system nodes"]
            WRK_A["Private-Workload 10.0.64.0/20<br/>Karpenter workspace nodes"]
        end
        subgraph AZ_B["AZ-b"]
            PUB_B["Public 10.0.16.0/20<br/>ALB, NAT GW"]
            SYS_B["Private-System 10.0.48.0/20<br/>EKS system nodes"]
            WRK_B["Private-Workload 10.0.80.0/20<br/>Karpenter workspace nodes"]
        end
    end
    IGW[Internet Gateway] --> PUB_A & PUB_B
    PUB_A --> NAT_A[NAT GW] --> SYS_A & WRK_A
    PUB_B --> NAT_B[NAT GW] --> SYS_B & WRK_B
```

### Subnets

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| Public A | 10.0.0.0/20 | a | ALB, NAT Gateway |
| Public B | 10.0.16.0/20 | b | ALB, NAT Gateway |
| Private-System A | 10.0.32.0/20 | a | EKS system node group |
| Private-System B | 10.0.48.0/20 | b | EKS system node group |
| Private-Workload A | 10.0.64.0/20 | a | Karpenter workspace nodes |
| Private-Workload B | 10.0.80.0/20 | b | Karpenter workspace nodes |

## EKS Cluster Architecture

```mermaid
graph TB
    subgraph EKS["EKS: coder4gov-eks (K8s 1.32)"]
        subgraph SYSTEM["System Node Group (m7a.xlarge, ON_DEMAND)"]
            direction LR
            CODERD["coder-server"]
            PROV["coder-provisioner (×2)"]
            KARP_CTRL["Karpenter controller"]
            ALB_CTRL2["ALB Controller"]
            ESO2["External Secrets"]
        end
        subgraph WORKSPACE["Karpenter NodePool: workspaces"]
            direction LR
            WS1["Workspace Pod A"]
            WS2["Workspace Pod B"]
            WS3["Workspace Pod ..."]
        end
    end
```

### Node Pools

| Pool | Type | Instance Types | Scaling |
|---|---|---|---|
| System | Managed Node Group | m7a.xlarge | min=2, max=4, on-demand |
| Workspaces | Karpenter NodePool | m7a/m7i .xlarge–.4xlarge | spot + on-demand, consolidation after 5m |

## Terraform Layer Dependency Graph

```mermaid
flowchart LR
    L0["0-state<br/>S3 + DynamoDB"] --> L1["1-network<br/>VPC, R53, ACM"]
    L1 --> L2["2-data<br/>RDS, KMS, ECR,<br/>Secrets Manager"]
    L2 --> L3["3-eks<br/>EKS, IRSA"]
    L3 --> L4["4-bootstrap<br/>Karpenter, ALB,<br/>Ext Secrets"]
    L4 --> FLUX["FluxCD reconciles<br/>clusters/gov-demo/"]
```

### Layer Outputs → Consumers

| Output | Source | Consumer |
|---|---|---|
| `vpc_id`, `subnet_ids` | L1 | L2, L3, L4 |
| `route53_zone_id`, `acm_wildcard_cert_arn` | L1 | L4, Flux manifests |
| `kms_key_arn`, `rds_endpoint`, `ecr_repo_urls` | L2 | L3, L4, Flux manifests |
| `cluster_name`, `oidc_provider_arn` | L3 | L4 |
| `karpenter_node_role_name` | L4 | EC2NodeClass |

## Secret Management Flow

```mermaid
sequenceDiagram
    participant SM as AWS Secrets Manager
    participant KMS as KMS CMK
    participant ESO as External Secrets Operator
    participant K8S as Kubernetes Secret
    participant APP as Coder Pod

    SM->>KMS: Encrypt secret at rest
    ESO->>SM: GetSecretValue (IRSA JWT auth)
    SM->>ESO: Encrypted value
    ESO->>K8S: Create/update K8s Secret
    APP->>K8S: Mount secret as env var
```

### Secrets

| Secret | Path | Created By | Consumed By |
|---|---|---|---|
| RDS master password | `coder4gov/rds-master-password` | Terraform (auto) | ExternalSecret → coder-db-credentials |
| Coder license | `coder4gov/coder-license` | seed-secrets.sh | ExternalSecret → coder-license |

## FIPS Compliance

| Layer | Mechanism |
|---|---|
| AWS API calls | FIPS endpoints (`use_fips_endpoint = true`) |
| Data at rest | KMS CMK (RDS, EBS, ECR, Secrets Manager, S3 state) |
| Data in transit | TLS 1.2+ (ALB `ELBSecurityPolicy-TLS13-1-2-2021-06`, RDS `rds.force_ssl`) |
| Coder binary | `GOFIPS140=latest` (Go 1.24+ native FIPS 140-3 module) |
| Workspace images | RHEL 9 UBI + `crypto-policies FIPS` |
| EKS nodes | AL2023 with FIPS crypto policy |

## Disaster Recovery

| Component | Backup | RTO | RPO |
|---|---|---|---|
| Terraform state | S3 versioning + DynamoDB PITR | < 1h | 0 (versioned) |
| RDS | Automated snapshots (7d retention) | < 1h | < 5 min |
| Coder config | Git (this repo) | < 30 min | Last commit |

## Integration Point — usgov-env-demo

This repo's Terraform state is consumed by `coder/usgov-env-demo` via
`terraform_remote_state`. That repo layers additional platform services
on top of the infrastructure defined here. No changes to this repo are
required to support those additions.
