# Makefile for K8s deployment with Ansible

.PHONY: all install configure kubeconfig clean help check

# Scenario selection (pass to Ansible via environment variable)
SCENARIO ?=
export SCENARIO

# Map scenario to inventory and config paths
ifeq ($(SCENARIO),)
  INVENTORY_PATH = ../../../performance-tests/results/base/artifacts/inventory.yaml
  CONFIG_PATH = ../../provisioning/config.yaml
else
  INVENTORY_PATH = ../../../performance-tests/results/$(SCENARIO)/artifacts/inventory.yaml
  CONFIG_PATH = ../../../performance-tests/results/$(SCENARIO)/config-override/aws-config.yaml
endif

# Auto-discover scenarios: any dir under performance-tests/results that has a config-override/aws-config.yaml
SCENARIOS = $(sort $(patsubst ../../../performance-tests/results/%/config-override/aws-config.yaml,%,$(wildcard ../../../performance-tests/results/*/config-override/aws-config.yaml)))

# Export as environment variable so Ansible uses it automatically (overrides ansible.cfg)
export ANSIBLE_INVENTORY := $(INVENTORY_PATH)

# Default target
all: deploy

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@test -f $(INVENTORY_PATH) || (echo "ERROR: Inventory not found at $(INVENTORY_PATH). Run Terraform first." && exit 1)
	@test -f $(CONFIG_PATH) || (echo "ERROR: Config file not found at $(CONFIG_PATH)." && exit 1)
	@ansible --version > /dev/null 2>&1 || (echo "ERROR: Ansible not installed." && exit 1)
	@echo "✓ All prerequisites met"
	@if [ -n "$(SCENARIO)" ]; then echo "Using scenario: $(SCENARIO)"; echo "Config: $(CONFIG_PATH)"; fi

# Deploy everything
deploy: check
	ansible-playbook playbooks/deploy-k8s.yml -e "scenario=$(SCENARIO)"

# Install MicroK8s only
install: check
	ansible-playbook playbooks/01-install-microk8s.yml -e "scenario=$(SCENARIO)"

# Configure Switch cluster only
switch-cluster: check
	ansible-playbook playbooks/02-configure-switch-cluster.yml -e "scenario=$(SCENARIO)"

# Configure FSP clusters only
fsp-clusters: check
	ansible-playbook playbooks/03-configure-fsp-clusters.yml -e "scenario=$(SCENARIO)"

# Generate kubeconfigs only
kubeconfig: check
	ansible-playbook playbooks/04-generate-kubeconfigs.yml -e "scenario=$(SCENARIO)"

# Generate hostaliases.json only (switch <-> DFSP DNS patch payload)
hostaliases: check
	ansible-playbook playbooks/06-generate-hostaliases.yml -e "scenario=$(SCENARIO)"

# Run specific playbook with tags
install-only: check
	ansible-playbook playbooks/deploy-k8s.yml --tags install -e "scenario=$(SCENARIO)"

configure-only: check
	ansible-playbook playbooks/deploy-k8s.yml --tags configure -e "scenario=$(SCENARIO)"

# Test connectivity
ping: check
	ansible all -m ping

# Check cluster status
status: check
	@echo "Checking Switch cluster status..."
	@ansible switch -m shell -a "microk8s kubectl get nodes" --become
	@echo "\nChecking FSP clusters status..."
	@ansible dfsps -m shell -a "microk8s kubectl get nodes" --become

# Clean up (be careful!)
uninstall:
	@echo "WARNING: This will remove MicroK8s from all nodes!"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible switch:dfsps -m shell -a "snap remove microk8s" --become

# Help
help:
	@echo "Available targets:"
	@echo "  make deploy        - Full deployment (install + configure + kubeconfig)"
	@echo "  make install       - Install MicroK8s on all nodes"
	@echo "  make switch-cluster - Configure switch cluster only"
	@echo "  make fsp-clusters  - Configure FSP clusters only"
	@echo "  make kubeconfig    - Generate kubeconfig files"
	@echo "  make hostaliases   - Generate hostaliases.json (switch <-> DFSP DNS)"
	@echo "  make ping          - Test Ansible connectivity"
	@echo "  make status        - Check cluster status"
	@echo "  make uninstall     - Remove MicroK8s (DESTRUCTIVE)"
	@echo ""
	@echo "Configuration files:"
	@echo "  Config: $(CONFIG_PATH)"
	@echo "  Inventory: $(INVENTORY_PATH)"
	@echo ""
	@echo "Scenario selection:"
	@echo "  SCENARIO=            Use base config (default)"
	@$(foreach s,$(SCENARIOS),echo "  SCENARIO=$(s)";)
	@echo ""
	@echo "Output (scenario-specific):"
	@echo "  Kubeconfigs: ../../../performance-tests/results/<scenario>/artifacts/kubeconfigs/"