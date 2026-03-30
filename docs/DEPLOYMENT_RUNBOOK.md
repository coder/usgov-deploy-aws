# Deployment Runbook — usgov-deploy-aws

Everything below assumes you're starting from scratch — no AWS
resources exist yet.

---

## Prerequisites

You need these on your local machine:

- **AWS CLI v2** configured with credentials that have admin access
  to the target account (`aws sts get-caller-identity` should work)
- **Terraform >= 1.10** (`terraform version`)
- **kubectl** (`kubectl version --client`)
- **Helm v3** (`helm version`)
- **yq v4+** (`yq --version`) — for `inject-outputs.sh`
- **jq** (`jq --version`)

---

## Phase A — Deploy Infrastructure (Terraform)

### A1. Clone the repo

```bash
git clone https://github.com/coder/usgov-deploy-aws.git
cd usgov-deploy-aws
```

### A2. Configure your deployment

Copy and edit the tfvars file. This is where you set your project
name, domain, region, instance sizes, etc.

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

**For GovCloud**, use the GovCloud example instead:
```bash
cp infra/terraform/govcloud.tfvars.example infra/terraform/terraform.tfvars
```

If you changed `project_name` from the default `coder4gov`, also
rename the Terraform backend buckets:

```bash
./scripts/rename-backend.sh \
  --project-name <your-project-name> \
  --region <your-region>
```

### A3. Deploy layer 0 — State Backend

**What it creates:** S3 bucket for Terraform state, DynamoDB table
for state locking, KMS key for state encryption. Uses local state
(this is the bootstrap layer).

**Why:** Every subsequent layer stores its state in this S3 bucket.
Nothing else can run until this exists.

```bash
cd infra/terraform/0-state
terraform init
terraform plan -var-file=../terraform.tfvars
# Review the plan — it creates 7 resources
terraform apply -var-file=../terraform.tfvars
cd ../../..
```

You should see outputs like:
```
state_bucket_name = "coder4gov-terraform-state"
lock_table_name   = "coder4gov-terraform-lock"
```

### A4. Deploy layer 1 — Network

**What it creates:** VPC (10.0.0.0/16), 6 subnets (2 public, 2
private-system, 2 private-workload), Internet Gateway, 2 NAT
Gateways (one per AZ for HA), Route 53 hosted zone, ACM wildcard
certificate, VPC Flow Logs to CloudWatch (365-day retention).

**Why:** Everything else runs inside this network. The ACM cert is
used by all ALB ingresses. The Route 53 zone is where DNS records go.

```bash
cd infra/terraform/1-network
terraform init
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ../../..
```

**After this step:** If you're using a new domain, you need to update
your domain registrar's NS records to point to the Route 53 name
servers in the output. Without this, ACM certificate validation will
hang forever.

```bash
cd infra/terraform/1-network
terraform output route53_name_servers
# Copy these NS records to your domain registrar
cd ../../..
```

### A5. Deploy layer 2 — Data

**What it creates:** RDS PostgreSQL 15 (Multi-AZ, KMS-encrypted,
gp3, 50–200 GiB autoscaling, 7-day backups, deletion protection),
3 ECR repositories (coder, base-fips, desktop-fips — all
KMS-encrypted with scan-on-push), KMS CMK (shared key for RDS/EBS/
ECR/Secrets Manager), Secrets Manager secrets (RDS password
auto-generated, Coder license placeholder).

**Why:** Coder needs a PostgreSQL database. ECR stores the FIPS
container images. Secrets Manager holds credentials that
ExternalSecrets syncs into Kubernetes.

```bash
cd infra/terraform/2-data
terraform init
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ../../..
```

**This takes ~10 minutes** (RDS Multi-AZ creation is slow).

Note the ECR registry URL from the output — you'll need it later:
```bash
cd infra/terraform/2-data
terraform output ecr_coder_repo_url
# e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com/coder4gov/coder
cd ../../..
```

### A6. Deploy layer 3 — EKS

**What it creates:** EKS 1.32 cluster with public+private API
endpoint, IRSA (IAM Roles for Service Accounts) enabled, secrets
encrypted with KMS. EKS addons: vpc-cni (prefix delegation +
network policy), coredns, kube-proxy, aws-ebs-csi-driver. Managed
node group: 2–4 m7a.xlarge ON_DEMAND instances in private-system
subnets, labeled `scheduling.coder.com/pool=system`, tainted
`CriticalAddonsOnly`.

**Why:** This is the Kubernetes cluster where Coder and all
platform services run. The system node group runs Coder server,
provisioner, and cluster addons. Workspace pods run on separate
Karpenter-managed nodes (next layer).

```bash
cd infra/terraform/3-eks
terraform init
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ../../..
```

**This takes ~15 minutes** (EKS cluster + managed node group).

After it finishes, configure kubectl:
```bash
aws eks update-kubeconfig \
  --name coder4gov-eks \
  --region us-west-2
kubectl get nodes  # Should show 2 system nodes
```

### A7. Deploy layer 4 — Bootstrap

**What it creates:** Karpenter (autoscaler for workspace nodes —
EC2NodeClass + NodePool targeting m7a/m7i .xlarge–.4xlarge in
private-workload subnets), AWS Load Balancer Controller (creates
ALBs from Ingress resources), External Secrets Operator
(syncs AWS Secrets Manager → Kubernetes Secrets via IRSA),
SQS queue (Karpenter spot interruption handling).

**Why:** These cluster addons must exist before Coder can run.
Karpenter scales workspace nodes on demand. ALB Controller
creates the load balancer for Coder's ingress. ESO makes
database credentials and the license available as K8s secrets.

```bash
cd infra/terraform/4-bootstrap
terraform init
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ../../..
```

Verify addons are running:
```bash
kubectl get pods -n kube-system    # ALB controller, EBS CSI
kubectl get pods -n karpenter      # Karpenter controller
kubectl get pods -n external-secrets  # ESO
```

**Or do all 5 layers at once:**
```bash
make apply TFVARS=terraform.tfvars
```

---

## Phase B — Seed Secrets

### B1. Seed the Coder license

The Terraform created a placeholder secret in Secrets Manager.
This script replaces it with your actual Coder license JWT.

```bash
./scripts/seed-secrets.sh
# Interactive: prompts for the license key
# Paste the JWT and press Enter
```

Or non-interactive:
```bash
CODER_LICENSE_JWT="eyJ..." ./scripts/seed-secrets.sh --non-interactive
```

### B2. Verify secrets are in Secrets Manager

```bash
# Should return the RDS connection JSON (auto-generated by Terraform)
aws secretsmanager get-secret-value \
  --secret-id coder4gov/rds-master-password \
  --query SecretString --output text | jq .

# Should return your license JWT (not PLACEHOLDER)
aws secretsmanager get-secret-value \
  --secret-id coder4gov/coder-license \
  --query SecretString --output text
```

---

## Phase C — Wire FluxCD Manifests

### C1. Inject Terraform outputs into HelmRelease files

The FluxCD manifests have empty placeholders for IRSA role ARNs and
ACM cert ARN. This script reads Terraform outputs and patches them.

```bash
./scripts/inject-outputs.sh
# Or preview first:
./scripts/inject-outputs.sh --dry-run
```

### C2. Commit and push the patched manifests

FluxCD watches the repo. Once you push, it deploys Coder.

```bash
git add clusters/
git commit -m "chore: inject terraform outputs into flux manifests"
git push
```

### C3. Verify Coder is running

```bash
kubectl get helmrelease -n coder       # Should show "Ready"
kubectl get pods -n coder              # coder-server + coder-provisioner
kubectl get ingress -n coder           # Should show ALB address
```

### C4. Create DNS records

If FluxCD created the ALB ingress, point your domain at it:

```bash
# Get the ALB hostname
kubectl get ingress -n coder -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

Create Route 53 records (or the Terraform may have already done
this depending on your setup):
- `dev.coder4gov.com` → ALB (A record, alias)
- `*.dev.coder4gov.com` → ALB (A record, alias)

---

## Phase D — Set Up CI/CD (GitHub Actions → ECR)

ECR repos now exist (created by layer 2). This phase wires GitHub
Actions to push FIPS images into them.

### D1. Get your AWS account ID

```bash
aws sts get-caller-identity --query Account --output text
# e.g. 123456789012
```

### D2. Create the OIDC identity provider

**What this does:** Tells AWS to trust GitHub Actions as an identity
provider. When a GitHub Actions workflow runs, GitHub issues a JWT.
This OIDC provider lets AWS validate that JWT so the workflow can
assume an IAM role — no static access keys needed.

**One-time setup. Skip if you already have this from another repo.**

Check first:
```bash
aws iam list-open-id-connect-providers \
  | grep token.actions.githubusercontent.com
# If it prints something, skip to D3
```

If nothing returned:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### D3. Create the IAM role for CI

**What this does:** Creates an IAM role that only GitHub Actions
workflows running in the `coder/usgov-deploy-aws` repo can assume.
The trust policy uses the OIDC provider from D2 and restricts
access to this specific repo. The permissions allow pushing and
pulling container images to/from ECR.

Save this as `/tmp/trust-policy.json` (replace `ACCOUNT_ID`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:coder/usgov-deploy-aws:*"
        }
      }
    }
  ]
}
```

```bash
# Replace ACCOUNT_ID in the file first, then:
aws iam create-role \
  --role-name usgov-deploy-aws-ci \
  --assume-role-policy-document file:///tmp/trust-policy.json
```

### D4. Attach ECR permissions to the role

**What this does:** Grants the CI role permission to authenticate
with ECR (GetAuthorizationToken works globally) and push/pull
images to the three repos created by Terraform layer 2. Scoped
to `coder4gov/*` repos only — can't touch anything else in ECR.

Save as `/tmp/ecr-policy.json` (replace `ACCOUNT_ID`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories"
      ],
      "Resource": "arn:aws:ecr:us-west-2:ACCOUNT_ID:repository/coder4gov/*"
    }
  ]
}
```

```bash
aws iam put-role-policy \
  --role-name usgov-deploy-aws-ci \
  --policy-name ecr-push \
  --policy-document file:///tmp/ecr-policy.json
```

### D5. Add GitHub repo secrets

**Where:** https://github.com/coder/usgov-deploy-aws/settings/secrets/actions

**Why:** The GitHub Actions workflows reference these secrets to
authenticate with AWS and know which ECR registry to push to. No
AWS access keys are stored — the workflow uses OIDC federation to
get short-lived credentials via the role from D3.

| Secret name | Value | Example |
|---|---|---|
| `ECR_REGISTRY` | `<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com` | `123456789012.dkr.ecr.us-west-2.amazonaws.com` |
| `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/usgov-deploy-aws-ci` | `arn:aws:iam::123456789012:role/usgov-deploy-aws-ci` |

### D6. Test the CI pipeline

**What this does:** Manually triggers the Coder FIPS build workflow.
It clones the Coder source, compiles a FIPS-enabled binary with
`GOFIPS140=latest`, packages it into an Alpine container image, and
pushes it to ECR with tags `v2.x.y-fips` and `latest-fips`.

1. Go to https://github.com/coder/usgov-deploy-aws/actions
2. Click **Coder FIPS Build** in the left sidebar
3. Click **Run workflow**
4. Set `push_to_ecr` to `true`
5. Click **Run workflow**

Watch the logs. The `push` job should end with:
```
Successfully pushed <REGISTRY>/coder4gov/coder:v2.30.4-fips
Successfully pushed <REGISTRY>/coder4gov/coder:latest-fips
```

Then test **Workspace FIPS Images** the same way. This builds the
RHEL 9 base-fips and desktop-fips images.

### D7. Verify images in ECR

```bash
aws ecr list-images --repository-name coder4gov/coder
aws ecr list-images --repository-name coder4gov/base-fips
aws ecr list-images --repository-name coder4gov/desktop-fips
```

---

## Phase E — Seed API Keys (for usgov-env-demo only)

Skip this if you're only deploying the base Coder. These are
needed for LiteLLM AI gateway in the usgov-env-demo platform.

```bash
aws secretsmanager create-secret \
  --name coder4gov/openai-api-key \
  --secret-string '<your-openai-api-key>'

aws secretsmanager create-secret \
  --name coder4gov/gemini-api-key \
  --secret-string '<your-gemini-api-key>'
```

---

## Order Summary

```
A1–A2  Clone + configure
A3     Layer 0: S3 state bucket          (~1 min)
A4     Layer 1: VPC, DNS, ACM            (~3 min)  → update NS records
A5     Layer 2: RDS, ECR, KMS, Secrets   (~10 min)
A6     Layer 3: EKS cluster              (~15 min)
A7     Layer 4: Karpenter, ALB, ESO      (~5 min)
B1–B2  Seed Coder license
C1–C4  Inject outputs, push, verify
D1–D7  OIDC + IAM role + GitHub secrets  (CI/CD)
E      API keys for demo env             (optional)
```

Total infrastructure time: ~35 minutes of `terraform apply` waiting.
