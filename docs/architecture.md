# Architecture

## Cluster topology

Three logical cluster groups on a single AWS VPC (`10.112.0.0/16`), all in
a private subnet behind one bastion. Each group is its own MicroK8s
control plane — there's no inter-cluster control-plane federation.

| Group | Nodes | Role |
|-------|-------|------|
| switch | 3 (HA) | Mojaloop core: ALS, quoting, ML-API-adapter, central-ledger handlers, settlement, TTK; backend pods (Kafka, MySQL, MongoDB, Redis); Istio ingress + egress gateway. NLB exposes the three CORE-API-ADAPTERS nodes on `:443`. |
| dfsps | 8 single-node | One MicroK8s per simulator: `fsp201`..`fsp208`. Each runs `mojaloop-simulator` (backend) + `sdk-scheme-adapter` (FSPIOP+SDK terminator). |
| k6 | 1 | k6-operator + load-driver pods. |

The switch uses node labels (`workload-class.mojaloop.io/*`) and taints to
isolate Kafka, MySQL, and the application handlers from each other.

## Network

- **Within a cluster** — pod-to-pod via the cluster CNI; no service mesh
  on app pods (the egress mTLS pattern keeps ambient/sidecars off them).
- **Across clusters** — over the VPC's private subnet on physical IPs.
  DNS is wired with two parallel mechanisms:
  1. Per-cluster CoreDNS `hosts{}` blocks programmed by the deploy roles
     (k6 → DFSP node IPs; switch → switch services + DFSP node IPs;
     each DFSP → switch services).
  2. Pod-level `hostAliases` overrides for callback Deployments inside
     the switch (after the mTLS role re-points them at the egress
     gateway IP).

## Mojaloop stack on the switch

Two helm releases:

- `backend` (`mojaloop/example-mojaloop-backend`): Kafka, MySQL, MongoDB,
  Redis. Ephemeral storage for throughput; replication mode (Rancher
  local-path provisioner) optional per scenario.
- `moja` (`mojaloop/mojaloop`): the central application chart — ALS,
  quoting service, central-ledger handlers, settlement, TTK
  (frontend + backend + cli).

Per-scenario overrides under `scenarios/<scenario>/overrides/{backend,mojaloop}.yaml`
diff against `common/{backend,mojaloop}.yaml`. Per-service ConfigMap JSON
overrides in `scenarios/<scenario>/configmaps/` get merged onto running
ConfigMaps via `kubectl patch` and the affected Deployments cycle through
0→N replicas to pick up the changes.

## DFSPs

Each DFSP cluster runs the `mojaloop/mojaloop-simulator` chart. The
deploy role (`ansible/roles/dfsp/`) loops 201..208 and:

1. Creates the `dfsps` namespace + dockerhub-secret.
2. Enables nginx `--enable-ssl-passthrough`.
3. Applies the shared TLS Secret (`certs/dfsp-tls-secret.yaml`).
4. Helm-installs the simulator with `common/dfsp/values-fsp{N}.yaml`.
5. Overrides the SDK image to `kirgene/sdk-scheme-adapter:jws-fix`
   (TODO: drop when upstream ships the JWS fix).
6. Patches the SDK volumes to mount `mtls-shared-creds`.
7. Applies the per-DFSP passthrough Ingress (`:443` → SDK `:4000`).
8. Sets `OUTBOUND_MUTUAL_TLS_ENABLED=true` and `INBOUND_MUTUAL_TLS_ENABLED=true`.
9. Patches `hostAliases` (switch services) and probe `periodSeconds: 180`.
10. Programs the local CoreDNS `hosts{}` for switch service hostnames.
11. Scales the SDK to `dfsp_replicas`.

All steps are idempotent — re-running the role on a healthy cluster is a
no-op apart from the helm upgrade dry-run check.

## Test execution

The k6 cluster runs:

- `k6-operator` in the `k6-operator` namespace (helm-installed by the k6
  role).
- `curl-k6-test` debug pod in the `k6-test` namespace (used by the
  smoke + sim_provision roles).
- A `TestRun` CR from `charts/k6/`, parameterised by `common/k6.yaml`
  and the scenario override.

The k6 script (`charts/k6/scripts/tests.js`) runs the full FSPIOP
lifecycle per iteration: discovery → quote → transfer.

## Stages and dependencies

```
terraform-apply  (AWS infra)
    │
    └── k8s          (microk8s + cluster form + kubeconfigs + hostaliases.json)
            │
            ├── backend         (Kafka/MySQL/MongoDB/Redis)
            │      │
            │      └── switch        (mojaloop core helm)
            │             │
            │             └── mtls          (Istio + Leg A inbound + Leg B egress)
            │                    │
            │                    └── dfsp           (8 sims, mTLS Phase 1B baked in)
            │                           │
            ├── monitoring             │   (independent; can run any time after backend)
            │                           │
            └── k6                     │   (independent of switch/dfsp; needs k8s)
                                       │
                                       └── onboard      (TTK hub setup + DFSP onboarding)
                                              │
                                              └── provision    (MSISDNs into ALS DB + sim repos)
                                                     │
                                                     ├── smoke        (single transfer end-to-end)
                                                     │
                                                     └── load         (k6 TestRun)
```

`make deploy` chains backend → smoke; `make load` is intentionally
separate so a load run is an explicit decision.
