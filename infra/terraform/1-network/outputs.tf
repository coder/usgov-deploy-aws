###############################################################################
# Layer 1 – Outputs
# coder4gov.com — Gov Demo Environment
#
# These outputs are consumed by subsequent layers (2-data, 3-eks, etc.)
# via terraform_remote_state or direct variable passing.
###############################################################################

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, NAT Gateway)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of all private subnets (system + workload)."
  value       = concat(aws_subnet.private_system[*].id, aws_subnet.private_workload[*].id)
}

output "private_system_subnet_ids" {
  description = "IDs of the private system subnets (EKS system node group)."
  value       = aws_subnet.private_system[*].id
}

output "private_workload_subnet_ids" {
  description = "IDs of the private workload subnets (Karpenter workspace nodes)."
  value       = aws_subnet.private_workload[*].id
}

# ---------------------------------------------------------------------------
# NAT Gateways
# ---------------------------------------------------------------------------

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (one per AZ)."
  value       = aws_nat_gateway.main[*].id
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

output "route53_zone_id" {
  description = "Zone ID of the Route 53 hosted zone for the domain."
  value       = data.aws_route53_zone.main.zone_id
}

# ---------------------------------------------------------------------------
# ACM Certificates
# ---------------------------------------------------------------------------

output "acm_wildcard_cert_arn" {
  description = "ARN of the validated ACM certificate (*.domain, apex, *.dev.domain)."
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

# ---------------------------------------------------------------------------
# Flow Logs
# ---------------------------------------------------------------------------

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs."
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}
