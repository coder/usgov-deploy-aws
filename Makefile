# =============================================================================
# usgov-deploy-aws — Terraform Orchestration
# =============================================================================
#
# Layers (applied in order):
#   0-state     — S3 backend + DynamoDB lock table (local state bootstrap)
#   1-network   — VPC, subnets, DNS, ACM
#   2-data      — RDS, ECR, KMS, Secrets Manager, CI/CD IAM
#   3-eks       — EKS cluster, IRSA, storage classes
#   4-bootstrap — Karpenter, ALB controller, external-secrets
#
# Usage:
#   make help
#   make init
#   make plan
#   make apply TFVARS=govcloud.tfvars
#   make destroy
# =============================================================================

.DEFAULT_GOAL := help

# Optional tfvars file — resolved to an absolute path so it works after
# cd-ing into layer directories.
#   make apply TFVARS=govcloud.tfvars
TFVARS ?=
TF_VAR_FLAG := $(if $(TFVARS),-var-file=$(abspath $(TFVARS)),)

# Base directory for all Terraform layers.
TF_DIR := infra/terraform

# Remote layers (require S3 backend from layer 0).
REMOTE_LAYERS := 1-network 2-data 3-eks 4-bootstrap

# All layers in apply order.
LAYERS := 0-state $(REMOTE_LAYERS)

# Reverse order for destroy (4 → 0).
LAYERS_REV := 4-bootstrap 3-eks 2-data 1-network 0-state

# Shared tflint config at the repo root.
TFLINT_CONFIG := $(CURDIR)/.tflint.hcl

# =============================================================================
# Phony targets
# =============================================================================
.PHONY: help init plan apply destroy fmt validate lint inject-outputs deploy

# =============================================================================
# help
# =============================================================================
help: ## Show available commands.
	@echo ""
	@echo "usgov-deploy-aws — Terraform orchestration"
	@echo ""
	@echo "Usage:  make <target> [TFVARS=filename.tfvars]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# init
# =============================================================================
init: ## Run terraform init in every layer (0→4). Applies layer 0 first if S3 bucket missing.
	@echo "==> Initializing layer 0-state (local backend)..."
	@( cd $(TF_DIR)/0-state && terraform init )
	@echo "==> Applying layer 0-state to ensure S3 backend exists..."
	@( cd $(TF_DIR)/0-state && terraform apply -auto-approve $(TF_VAR_FLAG) )
	@for layer in $(REMOTE_LAYERS); do \
		echo "==> Initializing layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform init ) || exit 1; \
	done

# =============================================================================
# plan
# =============================================================================
plan: ## Run terraform plan in every layer (0→4).
	@for layer in $(LAYERS); do \
		echo "==> Planning layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform plan $(TF_VAR_FLAG) ) || exit 1; \
	done

# =============================================================================
# apply
# =============================================================================
apply: ## Run terraform apply -auto-approve in every layer (0→4).
	@for layer in $(LAYERS); do \
		echo "==> Applying layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform init ) || exit 1; \
		if [ "$$layer" = "1-network" ]; then \
			echo "    (targeting ACM certs first to resolve for_each)"; \
			( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform apply -auto-approve -target=aws_acm_certificate.wildcard $(TF_VAR_FLAG) ) || exit 1; \
		fi; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform apply -auto-approve $(TF_VAR_FLAG) ) || exit 1; \
	done

# =============================================================================
# destroy
# =============================================================================
destroy: ## Run terraform destroy -auto-approve in reverse order (4→0).
	@for layer in $(LAYERS_REV); do \
		echo "==> Destroying layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform destroy -auto-approve $(TF_VAR_FLAG) ) || exit 1; \
	done

# =============================================================================
# fmt
# =============================================================================
fmt: ## Run terraform fmt -recursive across all layers.
	@echo "==> Formatting all Terraform files..."
	@terraform fmt -recursive $(TF_DIR)

# =============================================================================
# validate
# =============================================================================
validate: ## Run terraform validate in every layer.
	@for layer in $(LAYERS); do \
		echo "==> Validating layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && terraform validate ) || exit 1; \
	done

# =============================================================================
# lint
# =============================================================================
lint: ## Run tflint in every layer (shared .tflint.hcl config).
	@for layer in $(LAYERS); do \
		echo "==> Linting layer $$layer..."; \
		( cd $(CURDIR)/$(TF_DIR)/$$layer && tflint --config=$(TFLINT_CONFIG) ) || exit 1; \
	done

# =============================================================================
# inject-outputs
# =============================================================================
inject-outputs: ## Run scripts/inject-outputs.sh to wire layer outputs.
	@echo "==> Injecting Terraform outputs..."
	@./scripts/inject-outputs.sh

# =============================================================================
# deploy
# =============================================================================
deploy: apply inject-outputs ## Apply all layers, inject outputs, then print next steps.
	@echo ""
	@echo "============================================"
	@echo " usgov-deploy-aws deploy complete."
	@echo ""
	@echo " Next steps:"
	@echo "   1. Verify the cluster:  kubectl get nodes"
	@echo "   2. Seed secrets:        ./scripts/seed-secrets.sh"
	@echo "   3. Deploy usgov-env-demo:"
	@echo "        cd ../usgov-env-demo && make apply"
	@echo "============================================"
