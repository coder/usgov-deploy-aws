################################################################################
# Outputs – Layer 3 EKS
# Consumed by Layer 4 (Bootstrap) and Layer 5+ via remote state
################################################################################

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the EKS cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_provider" {
  description = "OIDC provider URL (without https://) for IRSA trust policies."
  value       = module.eks.oidc_provider
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------
output "cluster_security_group_id" {
  description = "Security group ID created by the EKS module for the cluster."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes (tagged for Karpenter)."
  value       = module.eks.node_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Primary security group ID of the EKS cluster."
  value       = module.eks.cluster_primary_security_group_id
}

# ---------------------------------------------------------------------------
# IRSA role ARNs – consumed by Layer 4 Helm values
# ---------------------------------------------------------------------------
output "irsa_role_arns" {
  description = "Map of IRSA role ARNs by workload name."
  value = {
    ebs_csi            = module.irsa_ebs_csi.iam_role_arn
    lb_controller      = module.irsa_lb_controller.iam_role_arn
    external_secrets   = module.irsa_external_secrets.iam_role_arn
    loki               = module.irsa_loki.iam_role_arn
    litellm            = module.irsa_litellm.iam_role_arn
    coder_provisioner  = module.irsa_coder_provisioner.iam_role_arn
  }
}

# ---------------------------------------------------------------------------
# Node IAM – needed by Karpenter in Layer 4
# ---------------------------------------------------------------------------
output "system_node_iam_role_name" {
  description = "IAM role name of the system node group (used as base for Karpenter node role)."
  value       = module.eks.eks_managed_node_groups["system"].iam_role_name
}
