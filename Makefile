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

# ANSIBLE invocation defaults — every play uses scenarios/<scenario>/artifacts/inventory.yaml
ANS_INV := -i $(ARTIFACTS_DIR)/inventory.yaml
ANS_EXTRA := -e scenario=$(SCENARIO)
ANS := cd $(ANS_DIR) && SCENARIO=$(SCENARIO) ansible-playbook $(ANS_INV) $(ANS_EXTRA)

# Auto-discover scenario list (directories only).
SCENARIOS := $(shell find scenarios -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

# ---- env loader ------------------------------------------------------------
# Sources scenarios/<scenario>/.env if present so DOCKERHUB_*, MYSQL_*, etc.
# get into the sub-process environment.
ENV_FILE := scenarios/$(SCENARIO)/.env
ifneq ("$(wildcard $(ENV_FILE))","")
include $(ENV_FILE)
export
endif

.PHONY: help tunnel \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        k8s backend switch mtls dfsp k6 onboard provision smoke load \
        deploy clean

# ===========================================================================
# 1. Tunnel
# ===========================================================================
tunnel: ## Open SOCKS5 tunnel via bastion (background, scenario-aware)
	@if lsof -iTCP:1080 -sTCP:LISTEN >/dev/null 2>&1; then \
	  echo "==> SOCKS tunnel already up on :1080"; \
	else \
	  ssh -F $(ARTIFACTS_DIR)/ssh-config -D 1080 perf-jump-host -N & \
	  sleep 2 && echo "==> SOCKS tunnel started (PID $$!)"; \
	fi

# ===========================================================================
# 2-5. Terraform (4 atomic targets)
# ===========================================================================
terraform-init: ## Initialize terraform providers
	cd $(TF_DIR) && terraform init -upgrade

terraform-plan: ## Plan AWS infra (writes plan to scenarios/<scenario>/artifacts/)
	@mkdir -p $(ARTIFACTS_DIR)
	cd $(TF_DIR) && terraform plan -var "scenario=$(SCENARIO)" \
	  -out ../$(ARTIFACTS_DIR)/terraform.plan

terraform-apply: ## Apply the saved plan (or create+apply if missing)
	@if [ -f $(ARTIFACTS_DIR)/terraform.plan ]; then \
	  cd $(TF_DIR) && terraform apply ../$(ARTIFACTS_DIR)/terraform.plan; \
	else \
	  cd $(TF_DIR) && terraform apply -auto-approve -var "scenario=$(SCENARIO)"; \
	fi

terraform-destroy: ## Destroy AWS infra for the active scenario
	cd $(TF_DIR) && terraform destroy -var "scenario=$(SCENARIO)"

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
