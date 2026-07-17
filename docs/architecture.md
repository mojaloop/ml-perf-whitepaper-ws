# Architecture

## Cluster topology

Three logical cluster groups on a single AWS VPC, all in a private subnet
behind one bastion. Each group is its own MicroK8s control plane — there's
no inter-cluster control-plane federation.

| Group | Nodes | Role |
|-------|-------|------|
| switch | Sized per scenario in `overrides/aws.yaml` (generic app nodes + dedicated Kafka node(s) + dedicated MySQL node(s) + a monitoring node) | Mojaloop core: ALS, quoting, ML-API-adapter, central-ledger handlers, settlement, TTK; backend pods (Kafka, MySQL, MongoDB, Redis); Istio ingress gateway. NLB exposes the switch nodes on `:80`/`:443` (NodePort 30080/30443). |
| dfsps | 8 single-node | One MicroK8s per simulator: `fsp201`..`fsp208`. Each runs `mojaloop-simulator` (backend + cache + scheme-adapter). |
| k6 | 1 | k6-operator + load-driver pods. |

The switch cluster uses node labels (`workload-class.mojaloop.io/*`) and
taints to isolate Kafka, MySQL, and the application handlers from each
other, plus `topologySpreadConstraints` so multi-replica services spread
evenly across the generic nodes.

## Network

- **Within a cluster** — pod-to-pod via the cluster CNI (Cilium eBPF).
  Encryption is optional and layered independently: Cilium WireGuard
  (transparent, all cross-node pod traffic) or Istio ambient mesh (SPIFFE
  mTLS for enrolled namespaces) or per-pod Envoy sidecars (edge mTLS
  origination on specific deployments). See [mtls.md](mtls.md).
- **Across clusters** — over the VPC's private subnet on physical IPs.
  DNS is wired with CoreDNS `hosts{}` blocks programmed by the deploy
  roles (k6 → DFSP node IPs; switch → switch services + DFSP node IPs;
  each DFSP → switch services), plus pod-level `hostAliases` on the
  switch's callback Deployments pointing at the real DFSP node IPs.

## Mojaloop stack on the switch

Two helm releases:

- `backend` (`mojaloop/example-mojaloop-backend`): Kafka, MySQL, MongoDB,
  Redis. Ephemeral storage for throughput; replication mode (Rancher
  local-path provisioner) optional per scenario.
- `moja` (`mojaloop/mojaloop`): the central application chart — ALS,
  quoting service, central-ledger handlers, settlement, TTK
  (frontend + backend + cli).

Base values are version-specific: `common/{backend,mojaloop}/<version>.yaml`.
A scenario's `overrides/{backend,mojaloop}.yaml` diffs on top. Per-service
ConfigMap JSON overrides in the scenario's `configmaps/` get merged onto
running ConfigMaps via `kubectl patch`, and the affected Deployments cycle
to pick up the changes.

## DFSPs

Each DFSP cluster runs the `mojaloop/mojaloop-simulator` chart via the
`dfsp` role (`ansible/roles/dfsp/`), looping over fsp201..fsp208. The role
is deliberately plain-HTTP — mTLS is a separate, optional layer (see
below). Per FSP it:

1. Creates the `dfsps` namespace + dockerhub-secret.
2. Tunes the nginx ingress ConfigMap for high throughput.
3. Helm-installs the simulator (`common/dfsp/values-fsp{N}.yaml` +
   the scenario's `overrides/dfsp.yaml`, if any).
4. Scales scheme-adapter and backend replicas independently
   (`dfsp_sdk_replicas` / `dfsp_backend_replicas`, per-FSP, from the
   scenario's `overrides/dfsp.yaml`) — the chart's `replicaCount`
   applies to all components at once, so this is imperative.
5. Patches `hostAliases` (switch services) and relaxes probe timing.
6. Tunes the Redis cache (maxmemory + no-persistence).
7. Programs the local CoreDNS `hosts{}` for switch service hostnames.

All steps are idempotent — re-running the role on a healthy cluster mostly
no-ops, except it **restarts the simulator backend**, which wipes its
in-memory party registrations (re-run `onboard` → `provision` → `smoke`
afterward).

mTLS (edge origination + DFSP-side certs) is applied separately by the
`mtls_dfsp` role, run after `dfsp` — see [mtls.md](mtls.md).

## Test execution

The k6 cluster runs:

- `k6-operator` in the `k6-operator` namespace (helm-installed by the k6
  role).
- `curl-k6-test` debug pod in the `k6-test` namespace (used by the
  `smoke_test` role).
- A `TestRun` CR from `charts/k6/`, parameterised by `common/k6.yaml`
  and the scenario's `overrides/k6.yaml`.

The k6 script (`charts/k6/scripts/tests.js`) runs the full FSPIOP
lifecycle per iteration: discovery → quote → transfer.

## Stages and dependencies

The authoritative command sequence — including which stages are optional
(mTLS, ambient, WireGuard) and why order matters — lives in the root
[README.md § Run a benchmark scenario from scratch](../README.md#run-a-benchmark-scenario-from-scratch).
Don't duplicate it here; it changes as roles are added.
