################################################################################
# Outputs – Layer 4 Bootstrap / Platform Services
# coder4gov.com — Coder Reference Architecture
#
# Consumed by FluxCD manifests and application layers.
################################################################################

# ---------------------------------------------------------------------------
# Karpenter (KARP-001 through KARP-004)
# ---------------------------------------------------------------------------

output "karpenter_irsa_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)."
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_role_name" {
  description = "IAM role name for nodes launched by Karpenter."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter spot interruption events."
  value       = module.karpenter.queue_name
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------------------

output "alb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (IRSA)."
  value       = module.alb_controller_irsa.iam_role_arn
}

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator (IRSA)."
  value       = module.eso_irsa.iam_role_arn
}
