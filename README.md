# Mojaloop Performance Testing Workstream

End-to-end perf lab: Terraform on AWS → Ansible deploys MicroK8s + Mojaloop
+ 8 DFSP simulators with mTLS → k6 drives load. Per-scenario configs target
500 / 1000 / 2000 TPS.

Each `make` stage is idempotent — re-run any failing stage in place.

## Prerequisites

- AWS account; profile `<AWS_PROFILE>` in `~/.aws/credentials`
- SSH key pair in AWS named `<SSH_KEY_NAME>`; private key at
  `~/.ssh/<SSH_KEY_NAME>.pem` (mode 0600)
- Local: `terraform`, `ansible`, `kubectl`, `helm`, `make`, `ssh`

## Setup once

```bash
cp .env.example .env
# edit .env: set AWS_PROFILE, AWS_DEFAULT_REGION, SSH_KEY_NAME,
#            DOCKERHUB_{USERNAME,TOKEN,EMAIL}, MYSQL_ROOT_PASSWORD
```

## Run the 500 TPS scenario from scratch

```bash
make terraform-init
make terraform-apply  SCENARIO=500tps      # ~10 min   AWS infra
make tunnel           SCENARIO=500tps      # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s              SCENARIO=500tps      # ~15 min   MicroK8s + kubeconfigs

make backend          SCENARIO=500tps      # ~5 min    Kafka/MySQL/MongoDB/Redis
make switch           SCENARIO=500tps      # ~3 min    Mojaloop core
make mtls             SCENARIO=500tps      # ~2 min    Istio + egress gateway
make dfsp             SCENARIO=500tps      # ~5 min    8 sims + mTLS Phase 1B
make k6               SCENARIO=500tps      #          k6-operator + CoreDNS

make onboard          SCENARIO=500tps      # ~1 min    TTK Jobs (see onboard.yaml below)
make provision        SCENARIO=500tps      # ~1 min    1000 MSISDNs/FSP

make smoke            SCENARIO=500tps      # MUST PASS — single transfer COMPLETED
make load             SCENARIO=500tps      # k6 TestRun; logs in scenarios/500tps/results/<UTC-stamp>/
```

Compress steps 4–6 into one: `make deploy SCENARIO=500tps` runs
`backend → switch → mtls → dfsp → k6 → onboard → provision → smoke`.

`make help` lists every target. `make terraform-destroy SCENARIO=500tps`
tears it all down.

## Per-scenario customization

`scenarios/<scenario>/`:
- `overrides/<chart>.yaml` — diffs against `common/<chart>.yaml`
- `configmaps/*.json` — per-service Mojaloop configmap patches
- `onboard.yaml` — manifest of TTK collection files to run during `make onboard`
- `artifacts/` — generated (kubeconfigs, plans, inventory)
- `results/<UTC-stamp>/` — per-load-test pod logs

## Documentation

- [docs/architecture.md](docs/architecture.md) — topology + components
- [docs/mtls.md](docs/mtls.md) — cert chain + both mTLS legs
- [docs/parameter-tuning.md](docs/parameter-tuning.md) — per-TPS sizing
- [docs/cheatsheet.md](docs/cheatsheet.md) — ad-hoc ops

## License

[LICENSE.md](LICENSE.md)
