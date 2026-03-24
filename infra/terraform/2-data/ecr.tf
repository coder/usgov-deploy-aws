################################################################################
# ECR Repositories – FIPS container images
################################################################################

locals {
  ecr_repositories = {
    "coder"        = "${var.project_name}/coder"
    "base-fips"    = "${var.project_name}/base-fips"
    "desktop-fips" = "${var.project_name}/desktop-fips"
  }

  # Lifecycle policy: keep last 30 tagged images, expire untagged after 7 days
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

resource "aws_ecr_repository" "repos" {
  for_each = local.ecr_repositories

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  tags = {
    Name = each.value
  }
}

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name
  policy     = local.ecr_lifecycle_policy
}
