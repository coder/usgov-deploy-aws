# =============================================================================
# TFLint configuration — shared across all Terraform layers
# =============================================================================
#
# Referenced from each layer via:  tflint --config=../../../.tflint.hcl
#
# This file lives at the repo root (infra/terraform/../..) so that all layers
# (0-state through 5-gitlab) use the same ruleset and plugin versions.
# =============================================================================

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
