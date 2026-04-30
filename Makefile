# Root Makefile for Mojaloop Performance Testing Infrastructure
# Orchestrates the full deployment workflow across modules

.PHONY: help

# Default target
.DEFAULT_GOAL := help

# Directories
TERRAFORM_DIR := infrastructure/provisioning/terraform
ANSIBLE_DIR := infrastructure/kubernetes/ansible

# Scenario selection (pass to sub-makes)
SCENARIO ?=

# Auto-discover scenarios: any dir under performance-tests/results that has a config-override/aws-config.yaml
SCENARIOS = $(sort $(patsubst performance-tests/results/%/config-override/aws-config.yaml,%,$(wildcard performance-tests/results/*/config-override/aws-config.yaml)))

#=============================================================================
# Infrastructure Provisioning (Terraform)
#=============================================================================

infra-init:
	@echo "==> Initializing Terraform..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-init SCENARIO=$(SCENARIO)

infra-plan:
	@echo "==> Creating Terraform execution plan..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-plan SCENARIO=$(SCENARIO)

infra-apply:
	@echo "==> Applying Terraform plan..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-apply SCENARIO=$(SCENARIO)

infra-apply-auto:
	@echo "==> Applying Terraform (auto-approve)..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-apply-auto SCENARIO=$(SCENARIO)

infra-destroy:
	@echo "==> Destroying infrastructure..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-destroy SCENARIO=$(SCENARIO)

infra-show:
	@echo "==> Showing Terraform state..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-show SCENARIO=$(SCENARIO)

infra-list:
	@echo "==> Listing Terraform resources..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-list SCENARIO=$(SCENARIO)

infra-validate:
	@echo "==> Validating Terraform configuration..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-validate SCENARIO=$(SCENARIO)

infra-fmt:
	@echo "==> Formatting Terraform files..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-fmt SCENARIO=$(SCENARIO)

infra-clean:
	@echo "==> Cleaning Terraform artifacts..."
	$(MAKE) -C $(TERRAFORM_DIR) infra-clean SCENARIO=$(SCENARIO)

#=============================================================================
# Kubernetes Deployment (Ansible)
#=============================================================================

k8s-deploy:
	@echo "==> Deploying Kubernetes clusters..."
	$(MAKE) -C $(ANSIBLE_DIR) deploy SCENARIO=$(SCENARIO)

k8s-install:
	@echo "==> Installing MicroK8s on all nodes..."
	$(MAKE) -C $(ANSIBLE_DIR) install SCENARIO=$(SCENARIO)

k8s-switch-cluster:
	@echo "==> Configuring switch cluster..."
	$(MAKE) -C $(ANSIBLE_DIR) switch-cluster SCENARIO=$(SCENARIO)

k8s-fsp-clusters:
	@echo "==> Configuring FSP clusters..."
	$(MAKE) -C $(ANSIBLE_DIR) fsp-clusters SCENARIO=$(SCENARIO)

k8s-kubeconfig:
	@echo "==> Generating kubeconfig files..."
	$(MAKE) -C $(ANSIBLE_DIR) kubeconfig SCENARIO=$(SCENARIO)

k8s-hostaliases:
	@echo "==> Generating hostaliases.json..."
	$(MAKE) -C $(ANSIBLE_DIR) hostaliases SCENARIO=$(SCENARIO)

k8s-ping:
	@echo "==> Testing Ansible connectivity..."
	$(MAKE) -C $(ANSIBLE_DIR) ping SCENARIO=$(SCENARIO)

k8s-status:
	@echo "==> Checking cluster status..."
	$(MAKE) -C $(ANSIBLE_DIR) status SCENARIO=$(SCENARIO)

k8s-uninstall:
	@echo "==> Uninstalling MicroK8s (DESTRUCTIVE)..."
	$(MAKE) -C $(ANSIBLE_DIR) uninstall SCENARIO=$(SCENARIO)

#=============================================================================
# End-to-End Deployment
#=============================================================================

deploy-all: infra-init infra-plan infra-apply k8s-deploy
	@echo ""
	@echo "=========================================="
	@echo "✓ Full deployment completed successfully!"
	@echo "=========================================="
	@if [ -n "$(SCENARIO)" ]; then \
		echo "Scenario: $(SCENARIO)"; \
	fi
	@echo ""
	@echo "Next steps:"
	@echo "  1. Set up SOCKS5 proxy: ssh -D 1080 perf-jump-host -N &"
	@echo "  2. Export proxy: export HTTPS_PROXY=socks5://127.0.0.1:1080"
	@echo "  3. Deploy platform services (cert-manager, monitoring, backend)"
	@echo "  4. Deploy Mojaloop switch"
	@echo "  5. Deploy DFSP simulators"
	@echo "  6. Run performance tests"
	@echo ""

# Quick deploy (auto-approve terraform)
deploy-all-auto: infra-init infra-apply-auto k8s-deploy
	@echo ""
	@echo "=========================================="
	@echo "✓ Quick deployment completed successfully!"
	@echo "=========================================="
	@if [ -n "$(SCENARIO)" ]; then \
		echo "Scenario: $(SCENARIO)"; \
	fi

#=============================================================================
# Cleanup
#=============================================================================

clean-all: infra-destroy infra-clean
	@echo "==> Cleanup completed"

#=============================================================================
# Help
#=============================================================================

help:
	@echo "Mojaloop Performance Testing Infrastructure"
	@echo ""
	@echo "Usage: make <target> [SCENARIO=<scenario>]"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Infrastructure Provisioning (Terraform)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  infra-init         Initialize Terraform"
	@echo "  infra-plan         Create execution plan"
	@echo "  infra-apply        Apply the saved plan"
	@echo "  infra-apply-auto   Apply with auto-approve (no plan file)"
	@echo "  infra-destroy      Destroy all infrastructure"
	@echo "  infra-show         Show current Terraform state"
	@echo "  infra-list         List resources in state"
	@echo "  infra-validate     Validate Terraform configuration"
	@echo "  infra-fmt          Format Terraform files"
	@echo "  infra-clean        Remove Terraform artifacts and state"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Kubernetes Deployment (Ansible)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  k8s-deploy         Full K8s deployment (install + configure)"
	@echo "  k8s-install        Install MicroK8s on all nodes"
	@echo "  k8s-switch-cluster Configure 3-node HA switch cluster"
	@echo "  k8s-fsp-clusters   Configure DFSP single-node clusters"
	@echo "  k8s-kubeconfig     Generate kubeconfig files"
	@echo "  k8s-hostaliases    Generate hostaliases.json (switch <-> DFSP DNS)"
	@echo "  k8s-ping           Test Ansible connectivity"
	@echo "  k8s-status         Check cluster status"
	@echo "  k8s-uninstall      Uninstall MicroK8s (DESTRUCTIVE)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "End-to-End Deployment"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  deploy-all         Full deployment (infra init + plan + apply + k8s)"
	@echo "  deploy-all-auto    Quick deployment (infra auto-apply + k8s)"
	@echo "  clean-all          Destroy infrastructure and clean artifacts"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Scenario Selection"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  SCENARIO=          Use base config (default)"
	@$(foreach s,$(SCENARIOS),echo "  SCENARIO=$(s)";)
	@echo ""
	@echo "  Scenarios use different instance types, node counts, and sizing."
	@echo "  Each scenario has its own state file in artifacts/<scenario>/"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Typical Workflow"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Base configuration:"
	@echo "    1. make infra-init        # Initialize Terraform"
	@echo "    2. make infra-plan        # Review infrastructure changes"
	@echo "    3. make infra-apply       # Provision AWS infrastructure"
	@echo "    4. make k8s-deploy        # Deploy MicroK8s clusters"
	@echo "    5. make k8s-status        # Verify cluster health"
	@echo ""
	@echo "  Scenario-based (example):"
	@$(if $(SCENARIOS),\
		echo "    1. make infra-init SCENARIO=$(lastword $(SCENARIOS))"; \
		echo "    2. make infra-plan SCENARIO=$(lastword $(SCENARIOS))"; \
		echo "    3. make infra-apply SCENARIO=$(lastword $(SCENARIOS))"; \
		echo "    4. make k8s-deploy SCENARIO=$(lastword $(SCENARIOS))"; \
	)
	@echo ""
	@echo "  Quick deployment:"
	@$(if $(SCENARIOS),echo "    make deploy-all SCENARIO=$(lastword $(SCENARIOS))";)
	@echo ""
	@echo "Configuration:"
	@echo "  Base:        infrastructure/provisioning/config.yaml"
	@echo "  Scenarios:   performance-tests/results/<tps>/config-override/aws-config.yaml"
	@echo ""
	@echo "Artifacts (scenario-specific):"
	@echo "  Base:        performance-tests/results/base/artifacts/"
	@echo "  Scenarios:   performance-tests/results/<tps>/artifacts/"
	@echo "  Contents:    terraform.tfstate, inventory.yaml, kubeconfigs/, ssh-config"
	@echo ""
