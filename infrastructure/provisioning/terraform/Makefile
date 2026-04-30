# Makefile for Terraform operations

.PHONY: infra-init infra-plan infra-apply infra-destroy infra-clean

# Scenario selection (empty = base config)
SCENARIO ?=

# Map scenario to config file path and artifacts directory
ifeq ($(SCENARIO),)
  CONFIG_PATH = ../config.yaml
  ARTIFACTS_DIR = ../../../performance-tests/results/base/artifacts
else
  CONFIG_PATH = ../../../performance-tests/results/$(SCENARIO)/config-override/aws-config.yaml
  ARTIFACTS_DIR = ../../../performance-tests/results/$(SCENARIO)/artifacts
endif

# Auto-discover scenarios: any dir under performance-tests/results that has a config-override/aws-config.yaml
SCENARIOS = $(sort $(patsubst ../../../performance-tests/results/%/config-override/aws-config.yaml,%,$(wildcard ../../../performance-tests/results/*/config-override/aws-config.yaml)))

# Terraform variables
TF_VARS = -var="config_file_path=$(CONFIG_PATH)" -var="artifacts_dir=$(ARTIFACTS_DIR)"

# Backend configuration for scenario-specific state
BACKEND_CONFIG = -backend-config="path=$(ARTIFACTS_DIR)/terraform.tfstate"

# Create artifacts directory if it doesn't exist
artifacts:
	@mkdir -p $(ARTIFACTS_DIR)
	@if [ -n "$(SCENARIO)" ]; then \
		echo "Using scenario: $(SCENARIO)"; \
		echo "Config: $(CONFIG_PATH)"; \
		echo "State: $(ARTIFACTS_DIR)/terraform.tfstate"; \
	else \
		echo "Using base configuration"; \
		echo "Config: $(CONFIG_PATH)"; \
	fi

# Initialize Terraform (creates artifacts directory first)
infra-init: artifacts
	terraform init $(BACKEND_CONFIG) -reconfigure

# Run terraform plan
infra-plan: artifacts
	terraform plan $(TF_VARS) -out=$(ARTIFACTS_DIR)/terraform.plan

# Apply the infrastructure
infra-apply: artifacts
	terraform apply $(ARTIFACTS_DIR)/terraform.plan

# Apply without plan file (interactive)
infra-apply-auto: artifacts
	terraform apply $(TF_VARS) -auto-approve

# Destroy infrastructure
infra-destroy:
	terraform destroy $(TF_VARS)

# Clean all generated files
infra-clean:
ifeq ($(SCENARIO),)
	rm -rf .terraform/
	rm -rf ../artifacts/
	rm -f .terraform.lock.hcl
else
	@echo "Cleaning scenario: $(SCENARIO)"
	rm -rf $(ARTIFACTS_DIR)/
endif

# Show current state
infra-show:
	terraform show $(ARTIFACTS_DIR)/terraform.tfstate

# List resources in state
infra-list:
	terraform state list

# Validate configuration
infra-validate:
	terraform validate

# Format terraform files
infra-fmt:
	terraform fmt -recursive

help:
	@echo "Available targets:"
	@echo "  make infra-init        - Initialize Terraform"
	@echo "  make infra-plan        - Create execution plan"
	@echo "  make infra-apply       - Apply the plan"
	@echo "  make infra-apply-auto  - Apply without plan file"
	@echo "  make infra-destroy     - Destroy infrastructure"
	@echo "  make infra-clean       - Remove all generated files"
	@echo "  make infra-show        - Show current state"
	@echo "  make infra-list        - List resources in state"
	@echo "  make infra-validate    - Validate configuration"
	@echo "  make infra-fmt         - Format terraform files"
	@echo ""
	@echo "Scenario selection:"
	@echo "  SCENARIO=            Use base config (default)"
	@$(foreach s,$(SCENARIOS),echo "  SCENARIO=$(s)";)
	@echo ""
	@echo "Examples:"
	@$(if $(SCENARIOS),echo "  make infra-plan SCENARIO=$(lastword $(SCENARIOS))"; echo "  make infra-apply SCENARIO=$(lastword $(SCENARIOS))";)