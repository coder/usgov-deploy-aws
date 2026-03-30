# Troubleshooting — usgov-deploy-aws

Common failures and their fixes, organized by symptom.

## 1. Backend init fails

**Symptom:** `terraform init` in any layer (1–4) fails with
`Failed to get existing workspaces` or `S3 bucket does not exist`.

**Cause:** Layer 0-state has not been applied yet. The S3 backend bucket
and DynamoDB lock table do not exist.

**Fix:**

```bash
cd infra/terraform/0-state
terraform init    # uses local backend
terraform apply
```

Then re-run `terraform init` in the failing layer.

## 2. FIPS endpoint errors

**Symptom:** Terraform or AWS CLI calls fail with `InvalidEndpoint`,
`Could not resolve host`, or TLS handshake errors mentioning
`fips.us-west-2`.

**Cause:** The target region does not support FIPS endpoints for the
service being called. Not every AWS service has a FIPS variant in every
region.

**Fix:** Check the `use_fips_endpoints` variable in your tfvars. Set it
to `false` for non-GovCloud regions or regions with limited FIPS
coverage.

```hcl
use_fips_endpoints = false
```

## 3. IRSA trust relationship fails

**Symptom:** Pods fail to assume their IAM role. `sts:AssumeRoleWithWebIdentity`
returns `InvalidIdentityToken` or the pod logs show
`An error occurred (AccessDenied)`.

**Cause:** The OIDC provider thumbprint registered in IAM does not match
the EKS cluster's current OIDC issuer certificate. This can happen after
an EKS control plane upgrade or if the cluster was recreated.

**Fix:** Re-apply the EKS layer to refresh the OIDC provider
registration.

```bash
cd infra/terraform/3-eks
terraform apply
```

Restart affected pods after the OIDC provider is updated.

## 4. FluxCD not reconciling

**Symptom:** `flux get all -A` shows resources stuck in
`NotReady`, `Source not found`, or `auth failure`.

**Cause:** Common causes include:

- Git authentication expired or misconfigured.
- Source `GitRepository` pointing at the wrong branch or URL.
- Flux controllers not running (check the `flux-system` namespace).

**Fix:**

```bash
# Check overall health.
flux check

# Inspect all Flux resources.
flux get all -A

# Force a reconciliation.
flux reconcile source git flux-system

# Check controller logs.
kubectl -n flux-system logs deploy/source-controller
kubectl -n flux-system logs deploy/kustomize-controller
```

## 5. Karpenter not scaling

**Symptom:** Workspace pods stay `Pending`. No new nodes are launched
by Karpenter.

**Cause:** Common causes include:

- `EC2NodeClass` or `NodePool` not applied or misconfigured.
- Subnets missing the `karpenter.sh/discovery` tag.
- Requested instance types not available in the AZ.
- Karpenter controller not running or lacking IAM permissions.

**Fix:**

```bash
# Verify Karpenter resources exist.
kubectl get ec2nodeclasses,nodepools

# Check Karpenter controller logs.
kubectl -n kube-system logs deploy/karpenter

# Verify subnet tags (should include karpenter.sh/discovery).
aws ec2 describe-subnets --filters "Name=tag-key,Values=karpenter.sh/discovery" \
  --query 'Subnets[].SubnetId'
```

## 6. ALB not created

**Symptom:** `Ingress` resources stay without an `ADDRESS`. No ALB
appears in the AWS console.

**Cause:** The AWS Load Balancer Controller is not running, lacks IAM
permissions, or the Ingress annotations are incorrect.

**Fix:**

```bash
# Check controller pods.
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller

# Check controller logs for permission errors.
kubectl -n kube-system logs deploy/aws-load-balancer-controller

# Verify the IngressClass exists.
kubectl get ingressclass
```

Ensure the IRSA role for the ALB controller has the correct policy
attached (see layer 4-bootstrap).

## 7. ExternalSecrets not syncing

**Symptom:** `ExternalSecret` resources show `SecretSyncedError` or
the corresponding Kubernetes `Secret` is missing.

**Cause:** Common causes include:

- `ClusterSecretStore` not created or not `Ready`.
- IRSA role for External Secrets Operator lacks `secretsmanager:GetSecretValue`.
- Secret path in AWS Secrets Manager does not match the `ExternalSecret` spec.

**Fix:**

```bash
# Check the ClusterSecretStore status.
kubectl get clustersecretstore -A

# Check individual ExternalSecret status.
kubectl get externalsecret -A

# Check ESO controller logs.
kubectl -n external-secrets logs deploy/external-secrets
```

Verify the secret exists in AWS Secrets Manager at the expected path:

```bash
aws secretsmanager describe-secret --secret-id coder4gov/rds-master-password
```

## 8. RDS connection refused

**Symptom:** Coder pods fail to connect to the database. Logs show
`connection refused` or `timeout` to the RDS endpoint.

**Cause:** The EKS node security group does not have an ingress rule
allowing traffic to the RDS security group on port 5432.

**Fix:**

```bash
# Get the RDS security group ID.
aws rds describe-db-instances --query 'DBInstances[0].VpcSecurityGroups'

# Verify the EKS node SG has outbound access to RDS SG on port 5432.
aws ec2 describe-security-groups --group-ids <rds-sg-id> \
  --query 'SecurityGroups[0].IpPermissions'
```

If the rule is missing, re-apply layer 2-data which manages the RDS
security group rules.

```bash
cd infra/terraform/2-data
terraform apply
```

## 9. inject-outputs.sh shows MISS

**Symptom:** Running `scripts/inject-outputs.sh` (in `usgov-env-demo`)
prints `SKIP` or `WARNING: Could not resolve the following values` for
one or more outputs.

**Cause:** The Terraform layer that produces the output has not been
applied yet, or `terraform init` was not run in that layer directory.

**Fix:** Apply the relevant upstream layer first:

```bash
# If usgov-deploy-aws outputs are missing:
cd ../usgov-deploy-aws/infra/terraform/<layer>
terraform init && terraform apply

# If usgov-env-demo outputs are missing:
cd infra/terraform/<layer>
terraform init && terraform apply
```

Then re-run `scripts/inject-outputs.sh --dry-run` to verify all values
resolve before running without `--dry-run`.

## 10. Provider version conflicts

**Symptom:** `terraform init` fails with
`Failed to query available provider packages` or
`Incompatible provider version`.

**Cause:** The `.terraform.lock.hcl` lockfile pins a provider version
that conflicts with the version constraint in the module, or the local
plugin cache is stale.

**Fix:**

```bash
cd infra/terraform/<layer>
terraform init -upgrade
```

If that does not resolve it, delete the `.terraform` directory and
re-initialize:

```bash
rm -rf .terraform .terraform.lock.hcl
terraform init
```
