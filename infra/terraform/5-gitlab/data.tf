###############################################################################
# Layer 5 – Data Sources
# coder4gov.com — Gov Demo Environment
#
# Common data sources used across multiple files in this layer.
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI (FIPS-capable, x86_64)
# GL-002: AL2023 with FIPS kernel
# ---------------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
