# Terraform

Provisions the AWS infrastructure for one scenario: a VPC (single AZ), a
bastion host, the switch cluster's EC2 instances, each DFSP's EC2 instance,
security groups, and (optionally) an NLB in front of the switch cluster.
Always invoked through the root `Makefile`'s four atomic targets
(`terraform-init`/`-plan`/`-apply`/`-destroy`); see
[Run a benchmark scenario from scratch](../README.md#run-a-benchmark-scenario-from-scratch)
in the root README for the actual command sequence, including the
`unset HTTPS_PROXY` and saved-plan gotchas.

## Layout

- `main.tf` — provider, decodes the config YAML, common tags, placement group
- `network.tf` — VPC, subnets, NAT gateway, route tables
- `instances.tf` — bastion, switch, and DFSP EC2 instances
- `security.tf` — security groups, built from the config file's rule lists
- `load_balancer.tf` — the switch cluster's NLB (only if the config enables it)
- `outputs.tf` — outputs, plus the `local_file` resources that render
  `templates/*.tpl` into the scenario's `artifacts/` dir (inventory,
  ssh-config, hosts, connection-info)
- `variables.tf` — the handful of variables not sourced from the config YAML

## Configuration

Everything instance/network/security-shaped is read from one YAML file at
plan time (`local.config_file = yamldecode(file(var.config_file_path))`):
`common/aws.yaml`, or a scenario's own `overrides/aws.yaml` if one exists.
The Makefile resolves which one and passes it as `TF_VAR_config_file_path`
— see [Optional security layers](../README.md#optional-security-layers) and
the `overrides/aws.yaml` row in
[Creating a new scenario](../README.md#creating-a-new-scenario) for what
goes in that file.

The Makefile also sets, per invocation:
- `TF_VAR_ssh_key_name` — from `SSH_KEY_NAME` in the root `.env`
- `TF_VAR_artifacts_dir` — the active scenario's `artifacts/` directory

A `terraform.tfvars` (see `terraform.tfvars.example`) is only relevant for a
manual `terraform plan`/`apply` run outside the Makefile.

## State

One Terraform workspace per scenario (`TF_WORKSPACE=<slug>`, e.g.
`v17.1.0-mtls-off-500tps`) — state lives under `terraform.tfstate.d/<slug>/`.
The Makefile's `terraform-init`/`-plan`/`-apply`/`-destroy` targets select or
create the workspace automatically; running `terraform` directly without
selecting a workspace first operates on `default`, which nothing else uses.

## Generated artifacts

`terraform-apply` writes these into the scenario's `artifacts/` directory
(via the `local_file` resources in `outputs.tf`):

| File | Content |
|---|---|
| `inventory.yaml` | Ansible inventory (`switch`, `dfsps`, `bastion` groups) |
| `ssh-config` | SSH client config — bastion jump host + one `Host` entry per node |
| `hosts` | Flat `/etc/hosts`-style node list |
| `connection-info.txt` | Human-readable summary (SSH commands, NLB DNS, node IPs) |
| `terraform.plan` | Saved plan from `terraform-plan`, applied by `terraform-apply` if present |

Append `artifacts/ssh-config` to your local `~/.ssh/config` to reach any
node by name (`ssh sw1-n1`, `ssh fsp201`, ...) through the bastion.
