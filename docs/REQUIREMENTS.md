# Requirements — usgov-deploy-aws Reference Architecture

## Purpose

Define the requirements for deploying Coder on AWS (GovCloud-portable) with
FIPS 140-3 compliance. This is a standalone reference architecture — customers
can fork and deploy Coder without additional dependencies.

## Scope

### In Scope

- Coder server and provisioner deployment on EKS
- RDS PostgreSQL for Coder database
- KMS encryption (at-rest for all data stores)
- ECR for FIPS container images
- Karpenter for workspace node autoscaling
- ALB Controller for ingress
- External Secrets Operator for secrets sync
- VPC networking (multi-AZ, NAT, Route 53, ACM)
- FIPS 140-3 compliance at all layers
- GovCloud portability (parameterized region/partition)

### Out of Scope (moved to usgov-env-demo)

- GitLab CE deployment
- Keycloak SSO
- LiteLLM AI gateway
- Istio service mesh
- WAF Web ACLs
- FluxCD bootstrap
- Monitoring / coder-observability
- OpenSearch SIEM
- SES email
- Kyverno policies

## Requirements

### INFRA — Infrastructure

| ID | Priority | Statement |
|---|---|---|
| INFRA-001 | SHALL | Use Terraform >= 1.5 for all infrastructure layers |
| INFRA-002 | SHALL | Store Terraform state in S3 with DynamoDB locking |
| INFRA-003 | SHALL | Use FIPS-validated AWS API endpoints by default |
| INFRA-004 | SHALL | Encrypt all data at rest with KMS CMK (RDS, EBS, ECR, Secrets Manager) |
| INFRA-005 | SHALL | Enforce TLS 1.2+ for all data in transit |
| INFRA-006 | SHALL | Use parameterized region/partition for GovCloud portability |
| INFRA-007 | SHALL | Deploy NAT Gateway per AZ for high availability |
| INFRA-008 | SHALL | Use minimum 2 Availability Zones |
| INFRA-009 | SHALL | Apply least-privilege security groups |
| INFRA-010 | SHALL | Use Route 53 for DNS and ACM for TLS certificates |

### EKS — Elastic Kubernetes Service

| ID | Priority | Statement |
|---|---|---|
| EKS-001 | SHALL | Deploy EKS cluster version 1.32+ |
| EKS-002 | SHALL | Enable both public and private API server endpoints |
| EKS-003 | SHALL | Deploy a managed system node group (ON_DEMAND, m7a.xlarge) |
| EKS-004 | SHALL | Encrypt Kubernetes secrets at rest with KMS |
| EKS-005 | SHALL | Enable IRSA for all service accounts |
| EKS-006 | SHALL | Tag node security groups for Karpenter discovery |
| EKS-007 | SHALL | Deploy managed add-ons: vpc-cni, coredns, kube-proxy, ebs-csi |
| EKS-008 | SHALL | Enable VPC CNI network policy and prefix delegation |
| EKS-009 | SHALL | Create gp3-encrypted default StorageClass with KMS |

### KARP — Karpenter

| ID | Priority | Statement |
|---|---|---|
| KARP-001 | SHALL | Deploy Karpenter controller via Helm with IRSA |
| KARP-002 | SHALL | Schedule controller on system nodes |
| KARP-003 | SHALL | Create EC2NodeClass with KMS-encrypted EBS and workload subnets |
| KARP-004 | SHALL | Create NodePool supporting spot + on-demand with consolidation |

### CDR — Coder Server

| ID | Priority | Statement |
|---|---|---|
| CDR-001 | SHALL | Deploy Coder via Helm chart (version 2.*) |
| CDR-002 | SHALL | Configure access URL and wildcard for subdomain routing |
| CDR-003 | SHALL | Connect to RDS via ExternalSecret-managed credentials |
| CDR-004 | SHOULD | Configure IRSA service account for AWS API access |
| CDR-005 | SHALL | Use ClusterIP service with ALB Ingress |
| CDR-006 | SHALL | Disable telemetry for GovCloud compliance |
| CDR-007 | SHALL | Configure ALB Ingress with ACM TLS termination |
| CDR-008 | SHALL | Enforce subdomain-only apps (disable path-based routing) |
| CDR-009 | SHALL | Set HSTS header (2-year max-age) |
| CDR-010 | SHALL | Enable audit logging |
| CDR-011 | SHALL | Allow both CLI and browser access |
| CDR-012 | SHALL | Pin to system node pool |

### PROV — Coder Provisioner

| ID | Priority | Statement |
|---|---|---|
| PROV-001 | SHALL | Deploy external provisioner via Helm chart |
| PROV-002 | SHALL | Configure IRSA for EC2/EKS operations |
| PROV-003 | SHALL | Run 2 replicas for HA |
| PROV-004 | SHALL | Pin to system node pool |

### SEC — Security

| ID | Priority | Statement |
|---|---|---|
| SEC-001 | SHALL | Enable FIPS crypto policy on all compute |
| SEC-002 | SHALL | Use KMS CMK with key rotation enabled |
| SEC-003 | SHALL | Block all public access to S3 buckets |
| SEC-004 | SHALL | Use IAM roles (IRSA, instance profiles) — no static keys |
| SEC-005 | SHALL | Enforce IMDSv2 on all EC2 instances |

### SM — Secrets Management

| ID | Priority | Statement |
|---|---|---|
| SM-001 | SHALL | Store secrets in AWS Secrets Manager (KMS-encrypted) |
| SM-002 | SHALL | Sync secrets to K8s via External Secrets Operator |
| SM-003 | SHALL | Limit ESO access to project-scoped secrets only |

### IMG — FIPS Images

| ID | Priority | Statement |
|---|---|---|
| IMG-001 | SHALL | Build Coder binary with GOFIPS140=latest |
| IMG-002 | SHALL | Build workspace base image from RHEL 9 UBI with FIPS crypto |
| IMG-003 | SHALL | Push images to KMS-encrypted ECR repos |
| IMG-004 | SHALL | Scan images on push (ECR scan-on-push) |

## Resolved Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | AWS-registered domain via Route 53 | No delegation needed, ACM validation automatic |
| 2 | NAT Gateway per AZ (not fck-nat) | AWS managed, HA, no operational burden |
| 3 | Single RDS instance (Coder DB only) | usgov-env-demo adds additional databases via remote state |
| 4 | Karpenter (not Cluster Autoscaler) | Better bin-packing, faster scaling, consolidation |
| 5 | External Secrets Operator (not Vault) | AWS-native, simpler, Secrets Manager is FIPS-validated |
| 6 | Standalone repo | Customers can fork without understanding the full stack |
