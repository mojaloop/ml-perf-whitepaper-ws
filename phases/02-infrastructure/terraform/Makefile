# Makefile for Terraform operations

.PHONY: init plan apply destroy clean

# Create artifacts directory if it doesn't exist
artifacts:
	@mkdir -p ../artifacts

# Initialize Terraform (creates artifacts directory first)
init: artifacts
	terraform init

# Run terraform plan
plan: artifacts
	terraform plan -out=../artifacts/terraform.plan

# Apply the infrastructure
apply: artifacts
	terraform apply ../artifacts/terraform.plan

# Apply without plan file (interactive)
apply-auto: artifacts
	terraform apply -auto-approve

# Destroy infrastructure
destroy:
	terraform destroy

# Clean all generated files
clean:
	rm -rf .terraform/
	rm -rf ../artifacts/
	rm -f .terraform.lock.hcl

# Show current state
show:
	terraform show ../artifacts/terraform.tfstate

# List resources in state
list:
	terraform state list

# Validate configuration
validate:
	terraform validate

# Format terraform files
fmt:
	terraform fmt -recursive

help:
	@echo "Available targets:"
	@echo "  make init        - Initialize Terraform"
	@echo "  make plan        - Create execution plan"
	@echo "  make apply       - Apply the plan"
	@echo "  make apply-auto  - Apply without plan file"
	@echo "  make destroy     - Destroy infrastructure"
	@echo "  make clean       - Remove all generated files"
	@echo "  make show        - Show current state"
	@echo "  make list        - List resources in state"
	@echo "  make validate    - Validate configuration"
	@echo "  make fmt         - Format terraform files"