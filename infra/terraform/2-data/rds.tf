################################################################################
# RDS – PostgreSQL 15 (Multi-AZ)
#
# Hosts THREE logical databases on a single instance:
#   • coder       – Coder control plane
#   • litellm     – LiteLLM proxy
#   • keycloak    – Keycloak IAM
#
# Database/schema creation is handled at application deploy time by Helm
# charts. This layer provisions only the instance + master credentials.
################################################################################

# ---------------------------------------------------------------------------
# Random master password (stored in Secrets Manager – see secrets.tf)
# ---------------------------------------------------------------------------
resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

# ---------------------------------------------------------------------------
# DB Subnet Group – private subnets from Layer 1
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ---------------------------------------------------------------------------
# Security Group – PostgreSQL (5432) from VPC CIDR only
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Allow PostgreSQL access from within the VPC"
  vpc_id      = local.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# RDS Parameter Group
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "postgres15" {
  name_prefix = "${var.project_name}-pg15-"
  family      = "postgres15"
  description = "Custom parameters for ${var.project_name} PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-pg15-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# RDS Instance – PostgreSQL 15
# ---------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "15"

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_name  = "coder4gov"
  username = var.db_master_username
  password = random_password.rds_master.result

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres15.name
  publicly_accessible    = false
  port                   = 5432

  backup_retention_period   = var.db_backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot     = true
  final_snapshot_identifier = "${var.project_name}-postgres-final"
  skip_final_snapshot       = false
  deletion_protection       = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.main.arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
