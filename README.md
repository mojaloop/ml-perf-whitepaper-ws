# Mojaloop Performance Testing Workstream

End-to-end perf lab for the Mojaloop financial switch — Terraform provisions
AWS infra, Ansible deploys MicroK8s + the Mojaloop stack on top, k6 drives
load through 8 DFSP simulators with mTLS on both legs, and per-scenario
configs target 500 / 1000 / 2000 TPS.

Single root `Makefile` chains 14 atomic stages. Each stage is callable on
its own — re-runnable mid-deploy without restarting from scratch.

## Quick start (500 TPS scenario, fresh AWS account)

```bash
# 0. Once: drop AWS creds + DOCKERHUB_* + MYSQL_ROOT_PASSWORD into
#    scenarios/500tps/.env (gitignored)

# 1. AWS infra (~10 min): VPC, bastion, switch nodes (3), DFSP nodes (8), k6 node
make terraform-init
make terraform-apply  SCENARIO=500tps

# 2. SOCKS tunnel through bastion (every shell session)
make tunnel           SCENARIO=500tps

# 3. MicroK8s on all 12 nodes, form clusters, write kubeconfigs +
#    hostaliases.json (~15 min)
make k8s              SCENARIO=500tps

# 4. App layer — each is one playbook, each idempotent
make backend          SCENARIO=500tps   # Kafka/MySQL/MongoDB/Redis on switch
make switch           SCENARIO=500tps   # Mojaloop core helm + configmap patches
make mtls             SCENARIO=500tps   # Istio install + Leg A inbound + Leg B egress gateway
make dfsp             SCENARIO=500tps   # 8 sims, mTLS Phase 1B baked in, scaled
make k6               SCENARIO=500tps   # k6-operator + cluster CoreDNS

# 5. Wire data (TTK collections + MSISDN seed)
make onboard          SCENARIO=500tps   # TTK hub setup + DFSP onboarding (Jobs)
make provision        SCENARIO=500tps   # 1000 MSISDNs/FSP into ALS DB + sim repos

# 6. Validate
make smoke            SCENARIO=500tps   # single transfer reaches COMPLETED

# 7. Run the load test
make load             SCENARIO=500tps   # k6 TestRun; per-pod logs land in scenarios/500tps/results/<UTC-stamp>/
```

Or compress steps 4–6 into one: `make deploy SCENARIO=500tps` chains
`backend → switch → mtls → dfsp → k6 → onboard → provision → smoke`.

Total wall-clock from a fresh AWS account: **~45–60 min**, dominated by
terraform (10 min) + k8s bootstrap (15 min) + backend Helm wait
(5–10 min). The app-layer roles each take 1–3 min once their
dependencies are up. `dfsp` is the slowest (8× helm install + per-FSP
mTLS plumbing).

If anything fails mid-chain, just re-run the failing target — every
role drift-corrects.

`make help` lists every stage with a one-line description.

## Repository layout

```
ansible/                Roles + playbooks (one role per Make stage)
  roles/                _common, backend, switch, mtls_switch, dfsp, k6,
                         monitoring, switch_onboard, dfsp_onboard,
                         als_provision, sim_provision, smoke_test, load_test
  playbooks/            One per role + the legacy 01-06 cluster bootstrap
                         (called by `make k8s`)

certs/                  Lab CA + leaf material (Kubernetes Secret manifests)
  regen-certs.sh        Rotate the shared CA + SAN leaf
  jws/                  JWS signing keypair used by the SDK adapters

charts/k6/              Local Helm chart that wraps the k6 TestRun CR

common/                 Default values consumed by every scenario
  aws.yaml              Terraform/Ansible cluster topology
  backend.yaml          example-mojaloop-backend chart values
  mojaloop.yaml         mojaloop chart values
  istio-{ingress,egress}gateway.yaml
  monitoring.yaml       promfana chart values
  k6.yaml               k6 TestRun config
  dfsp/                 Per-FSP simulator values (values-fsp201..208.yaml)

docs/
  architecture.md       Topology + component layout
  mtls.md               Cert chain, Istio install, both mTLS legs
  parameter-tuning.md   Per-TPS sizing rationale (kafka partitions, replicas)
  cheatsheet.md         Ad-hoc ops (SOCKS, scale, kafka, mTLS probes)

manifests/              Static k8s manifests (mTLS Istio resources, hostAliases)
scenarios/<scenario>/
  overrides/            Per-scenario file pairs that override common/*.yaml
  configmaps/           Per-scenario service configmap JSONs
  artifacts/            Generated: kubeconfigs/, inventory.yaml, plans, ...
  results/<UTC-stamp>/  Per-load-test pod logs

terraform/              AWS provisioning (VPC, EC2, NLB, bastion, IAM)
tools/                  Debug pods (curl, kafka-ui)
ttk-collections/        Testing-Toolkit JSON collections (hub setup + sim onboarding)
```

## What changed vs the original layout

The repo was reorganised from a `infrastructure/<service>/{README.md, deploy.bash}`
+ `performance-tests/results/<tps>/config-override/*` layout into the structure
above. Drivers:

- **Single Make orchestrator** at the root replaces three sub-Makefiles.
- **Common-vs-overrides** for every helm chart: `common/<chart>.yaml` is the
  base, `scenarios/<x>/overrides/<chart>.yaml` is the diff. No more copying
  full values files between scenarios.
- **Ansible roles, not bash scripts** for every deploy step (idempotent,
  re-runnable), driven by per-role playbooks under `ansible/playbooks/`.
- **mTLS on by default** — the dfsp role flips OUTBOUND/INBOUND mTLS env
  vars and mounts the shared cert during initial install, instead of a
  multi-phase post-install ritual.

See `docs/architecture.md` for the full topology and `docs/mtls.md` for the
mTLS chain of trust.

## License

[LICENSE.md](LICENSE.md).
