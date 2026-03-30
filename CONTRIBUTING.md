# Contributing to usgov-deploy-aws

## Forking for Your Organization

1. **Fork the repository** — click "Fork" on GitHub or run:

   ```bash
   gh repo fork coder/usgov-deploy-aws --clone
   ```

2. **Rename key values** in your fork to match your environment:

   | File | Variable / Block | What to change |
   |------|-----------------|----------------|
   | `providers.tf` | S3 backend `bucket` | Your Terraform state bucket name |
   | `providers.tf` | DynamoDB `dynamodb_table` | Your state-lock table name |
   | `providers.tf` | Backend `region` | Your AWS region |
   | `variables.tf` | `project_name` | Your project or agency identifier |
   | `variables.tf` | `domain_name` | Your organization's domain |

3. **Deploy** — follow the step-by-step guide in
   [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Contributing Back Upstream

Improvements that benefit all users are welcome as pull requests to
`coder/usgov-deploy-aws`. Please:

1. Open an issue describing the change before writing code.
2. Keep PRs focused — one logical change per PR.
3. Include documentation updates when adding or changing behavior.
4. Ensure `terraform validate` passes before submitting.
