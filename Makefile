# Mojaloop Perf Lab — root Makefile
#
# Atomic stages (each callable independently); `deploy` chains them all
# in order. SCENARIO selects per-scenario overrides under
# scenarios/<scenario>/overrides/; defaults to "base".
#
# Usage:
#   make tunnel SCENARIO=500tps        # one-shot: open the bastion SOCKS tunnel
#   make terraform-apply SCENARIO=500tps
#   make k8s SCENARIO=500tps
#   make deploy SCENARIO=500tps        # backend -> switch -> mtls -> dfsp -> k6 -> onboard -> provision
#   make smoke SCENARIO=500tps
#   make load  SCENARIO=500tps

.DEFAULT_GOAL := help

SCENARIO ?= base
TF_DIR   := terraform
ANS_DIR  := ansible
ARTIFACTS_DIR := scenarios/$(SCENARIO)/artifacts

# ANSIBLE invocation defaults. The Makefile `cd ansible &&` first, so
# inventory path must be ../-relative to that.
ANS_INV := -i ../$(ARTIFACTS_DIR)/inventory.yaml
ANS_EXTRA := -e scenario=$(SCENARIO)
ANS := cd $(ANS_DIR) && SCENARIO=$(SCENARIO) ansible-playbook $(ANS_INV) $(ANS_EXTRA)

# Auto-discover scenario list (directories only).
SCENARIOS := $(shell find scenarios -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

# ---- env loader ------------------------------------------------------------
# Single root .env (scenario-agnostic). Template at .env.example.
# Loads: AWS_PROFILE, AWS_DEFAULT_REGION, SSH_KEY_NAME, DOCKERHUB_*, MYSQL_*.
ENV_FILE := .env
ifneq ("$(wildcard $(ENV_FILE))","")
include $(ENV_FILE)
export
endif

# Derived: where ansible looks for the SSH private key, and the TF var
# that the AWS key-pair lookup uses. Both follow ~/.ssh/<name>.pem.
ifneq ($(strip $(SSH_KEY_NAME)),)
export ANSIBLE_PRIVATE_KEY_FILE := $(HOME)/.ssh/$(SSH_KEY_NAME).pem
export TF_VAR_ssh_key_name      := $(SSH_KEY_NAME)
endif

# Terraform consumes a single config file; pick scenario override if it
# exists, else fall back to common/aws.yaml. Path is relative to the
# terraform/ working directory (where `cd terraform &&` runs).
SCENARIO_AWS_YAML := scenarios/$(SCENARIO)/overrides/aws.yaml
ifneq ("$(wildcard $(SCENARIO_AWS_YAML))","")
  export TF_VAR_config_file_path := ../$(SCENARIO_AWS_YAML)
else
  export TF_VAR_config_file_path := ../common/aws.yaml
endif

# Per-scenario terraform state isolation via workspaces. Each scenario
# gets its own state under terraform/terraform.tfstate.d/<scenario>/.
export TF_WORKSPACE := $(SCENARIO)

# Where terraform writes inventory.yaml + ssh-config + kubeconfigs.
export TF_VAR_artifacts_dir := ../$(ARTIFACTS_DIR)

# Tell ansible's ssh connection plugin to use the terraform-emitted
# ssh-config (so hostnames like sw1-n1, fsp201 resolve via ProxyJump).
# Must include the ControlMaster opts that ansible.cfg's ssh_args
# normally supplies — this env var REPLACES that setting.
export ANSIBLE_SSH_ARGS := -o ControlMaster=auto -o ControlPersist=30m -o ServerAliveInterval=60 -F $(CURDIR)/$(ARTIFACTS_DIR)/ssh-config

.PHONY: help tunnel \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        k8s backend monitoring switch mtls dfsp k6 onboard provision smoke load \
        deploy clean

# ===========================================================================
# 1. Tunnel
# ===========================================================================
tunnel: ## Open SOCKS5 tunnel via bastion (background, scenario-aware)
	@if lsof -iTCP:1080 -sTCP:LISTEN >/dev/null 2>&1; then \
	  echo "==> SOCKS tunnel already up on :1080"; \
	else \
	  ssh -F $(ARTIFACTS_DIR)/ssh-config -D 1080 -N -f perf-jump-host && \
	    echo "==> SOCKS tunnel started"; \
	fi

# ===========================================================================
# 2-5. Terraform (4 atomic targets)
# ===========================================================================
# Workspace selection — ensures the scenario-named workspace exists.
# TF_WORKSPACE must be UNSET for `terraform workspace` subcommands;
# downstream plan/apply pick it up from the environment-level export.
_tf-workspace:
	@cd $(TF_DIR) && unset TF_WORKSPACE && \
	  (terraform workspace select $(SCENARIO) 2>/dev/null \
	   || terraform workspace new $(SCENARIO)) >/dev/null

terraform-init: ## Initialize terraform providers
	cd $(TF_DIR) && TF_WORKSPACE= terraform init -upgrade

terraform-plan: _tf-workspace ## Plan AWS infra (writes plan to scenarios/<scenario>/artifacts/)
	@mkdir -p $(ARTIFACTS_DIR)
	cd $(TF_DIR) && terraform plan -out ../$(ARTIFACTS_DIR)/terraform.plan

terraform-apply: _tf-workspace ## Apply the saved plan (or create+apply if missing)
	@if [ -f $(ARTIFACTS_DIR)/terraform.plan ]; then \
	  cd $(TF_DIR) && terraform apply ../$(ARTIFACTS_DIR)/terraform.plan; \
	else \
	  cd $(TF_DIR) && terraform apply -auto-approve; \
	fi

terraform-destroy: _tf-workspace ## Destroy AWS infra for the active scenario
	cd $(TF_DIR) && terraform destroy

# ===========================================================================
# 6. k8s — bootstrap MicroK8s clusters (existing playbooks 01-06)
# ===========================================================================
k8s: ## Install MicroK8s, form clusters, generate kubeconfigs + hostaliases
	$(ANS) playbooks/deploy-k8s.yml

# ===========================================================================
# 7-13. App-layer deployment (one role per stage)
# ===========================================================================
backend: ## Deploy mojaloop backend (Kafka, MySQL, MongoDB, Redis)
	$(ANS) playbooks/backend.yml

monitoring: ## Deploy promfana stack (prometheus + grafana + alertmanager)
	$(ANS) playbooks/monitoring.yml

switch: ## Deploy mojaloop switch + per-scenario configmap patches
	$(ANS) playbooks/switch.yml

mtls: ## Switch-side mTLS (Istio install + Leg A inbound + Leg B egress gateway)
	$(ANS) playbooks/mtls-switch.yml

dfsp: ## Deploy 8 DFSP simulators with mTLS Phase 1B + scaling
	$(ANS) playbooks/dfsp.yml

k6: ## Set up k6 cluster (operator + dockerhub secret + CoreDNS)
	$(ANS) playbooks/k6.yml

onboard: ## Hub setup + DFSP onboarding (TTK collections, two stages)
	$(ANS) playbooks/switch-onboard.yml
	$(ANS) playbooks/dfsp-onboard.yml

provision: ## Insert MSISDNs into ALS DB + register parties on each sim
	$(ANS) playbooks/als-provision.yml
	$(ANS) playbooks/sim-provision.yml

# ===========================================================================
# 14. smoke + load
# ===========================================================================
smoke: ## Single end-to-end transfer (validates whole stack)
	$(ANS) playbooks/smoke-test.yml

load: ## Run k6 TestRun for the active scenario
	$(ANS) playbooks/load-test.yml

# ===========================================================================
# Composite — full app deploy after k8s is up
# ===========================================================================
deploy: backend switch mtls dfsp k6 onboard provision smoke ## Backend -> switch -> mtls -> dfsp -> k6 -> onboard -> provision -> smoke

# ===========================================================================
# Cleanup
# ===========================================================================
clean: ## Remove scenario artifacts (NOT terraform state — use terraform-destroy first)
	rm -rf $(ARTIFACTS_DIR)/coredns-*.yaml \
	       $(ARTIFACTS_DIR)/dfsp-fsp*.yaml \
	       $(ARTIFACTS_DIR)/k6-coredns.yaml \
	       $(ARTIFACTS_DIR)/ttk-* \
	       $(ARTIFACTS_DIR)/terraform.plan

# ===========================================================================
# Help
# ===========================================================================
help: ## Show this help
	@printf '\nMojaloop Perf Lab — root Makefile\n'
	@printf 'Usage: make <target> [SCENARIO=<scenario>]\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort \
	  | awk -F ':.*?## ' 'BEGIN {FS = ":.*?## "} {printf "  %-22s %s\n", $$1, $$2}'
	@printf '\nKnown scenarios: $(SCENARIOS)\n'
	@printf 'Active SCENARIO: $(SCENARIO)\n\n'
