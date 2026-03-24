###############################################################################
# Layer 5 – EC2 Launch Template & ASG for GitLab CE
# coder4gov.com — Gov Demo Environment
#
# Creates:
#   - Launch template with AL2023 AMI, FIPS, user data (GL-001, GL-002)
#   - Auto Scaling Group (min=1, max=1) for self-healing (GL-014)
#
# Requirements:
#   - GL-001: m7a.2xlarge (8 vCPU / 32 GiB AMD)
#   - GL-002: AL2023 with FIPS kernel
#   - GL-014: ASG min=1, max=1 for self-healing
#   - INFRA-004: EBS encrypted with KMS
###############################################################################

locals {
  # Subnets from Layer 1 — place GitLab in private subnets
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  # KMS key from Layer 2 — data encryption
  kms_key_arn = data.terraform_remote_state.data.outputs.kms_key_arn

  # S3 bucket names from Layer 2
  s3_backup_bucket    = "${var.project_name}-gitlab-backups"
  s3_artifacts_bucket = "${var.project_name}-gitlab-artifacts"
  s3_lfs_bucket       = "${var.project_name}-gitlab-lfs"
  s3_uploads_bucket   = "${var.project_name}-gitlab-uploads"
  s3_packages_bucket  = "${var.project_name}-gitlab-packages"
  s3_registry_bucket  = "${var.project_name}-gitlab-registry"

  # SES endpoint for the region
  ses_endpoint = "email-smtp.${var.aws_region}.amazonaws.com"

  # Data volume device name
  data_device = "/dev/xvdf"
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------

resource "aws_launch_template" "gitlab" {
  name_prefix   = "${var.project_name}-gitlab-"
  description   = "GitLab CE Omnibus on AL2023 with FIPS (GL-001, GL-002)"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.gitlab_instance_type

  # IAM instance profile — no static keys (SEC-004)
  iam_instance_profile {
    arn = aws_iam_instance_profile.gitlab.arn
  }

  # Security group
  vpc_security_group_ids = [aws_security_group.gitlab_instance.id]

  # SSH key pair (optional, for initial setup only)
  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  # IMDSv2 required (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Root volume — OS (INFRA-004: KMS encrypted)
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.gitlab_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = local.kms_key_arn
      delete_on_termination = true
      iops                  = 3000
      throughput            = 250
    }
  }

  # Data volume — git repos, PostgreSQL data, etc. (INFRA-004: KMS encrypted)
  block_device_mappings {
    device_name = local.data_device

    ebs {
      volume_size           = var.gitlab_data_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = local.kms_key_arn
      delete_on_termination = false  # Preserve data on instance replacement
      iops                  = 3000
      throughput            = 250
    }
  }

  # Monitoring
  monitoring {
    enabled = true
  }

  # User data — installs and configures GitLab, Docker, Runner
  user_data = base64encode(templatefile(
    "${path.module}/templates/userdata.sh.tftpl",
    {
      aws_region           = var.aws_region
      project_name         = var.project_name
      domain_name          = var.domain_name
      s3_backup_bucket     = local.s3_backup_bucket
      s3_artifacts_bucket  = local.s3_artifacts_bucket
      s3_lfs_bucket        = local.s3_lfs_bucket
      s3_uploads_bucket    = local.s3_uploads_bucket
      s3_packages_bucket   = local.s3_packages_bucket
      s3_registry_bucket   = local.s3_registry_bucket
      ses_endpoint         = local.ses_endpoint
      data_device          = local.data_device
      data_aws_account_id  = data.aws_caller_identity.current.account_id
    }
  ))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-gitlab"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.project_name}-gitlab-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group — Self-healing (GL-014)
# min=1, max=1, desired=1 — ensures exactly one GitLab instance
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "gitlab" {
  name_prefix = "${var.project_name}-gitlab-"

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  # Place in private subnets across AZs
  vpc_zone_identifier = local.private_subnet_ids

  # Health check via ALB target group
  health_check_type         = "ELB"
  health_check_grace_period = 600  # GitLab takes ~5-10 min to start

  # Use latest launch template version
  launch_template {
    id      = aws_launch_template.gitlab.id
    version = "$Latest"
  }

  # ALB target group attachment
  target_group_arns = [aws_lb_target_group.gitlab.arn]

  # Instance refresh for zero-downtime updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0  # min=1,max=1 means we must allow 0 during refresh
    }
  }

  # Wait for instance to pass ELB health check
  wait_for_elb_capacity = 1

  tag {
    key                 = "Name"
    value               = "${var.project_name}-gitlab"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
