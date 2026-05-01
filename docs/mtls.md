# mTLS — switch ↔ DFSPs

mTLS is enabled on **both** legs between the Mojaloop switch and the 8
DFSP simulators. Single shared CA + leaf cert (lab only — no PKI, no
per-entity identities). The whole pipeline is wired into the deploy
roles, so a fresh `make deploy` brings up a fully mTLS-enforced lab.

## Cert chain

One CA (`mojaloop-perf-lab-ca`) signs one leaf (`CN=mojaloop-perf-mtls`)
with SANs covering the 3 switch hostnames + 8 DFSP hostnames:

```
account-lookup-service.local
quoting-service.local
ml-api-adapter.local
sim-fsp201.local … sim-fsp208.local
```

The same bundle serves as **server cert** (terminating side) and
**client cert** (originating side) on both ends.

Files (in this repo):

| Path | Purpose |
|---|---|
| `certs/regen-certs.sh` | Regenerates the CA + SAN leaf, emits the two Secret manifests below. Re-run to rotate. |
| `certs/switch-tls-secret.yaml` | Secret `switch-mtls-creds` (`istio-system`). Generated. Mounted by the Istio gateways. |
| `certs/dfsp-tls-secret.yaml` | Secret `mtls-shared-creds` (`dfsps`). Applied on all 8 DFSP clusters. Mounted by each `sdk-scheme-adapter`. |
| `certs/jws/jwtRS256.{key,key.pub}` | JWS signing keypair used by the SDKs (separate from mTLS but kept alongside). |

To change the SAN list (e.g. add a 9th DFSP), edit the `[alt_names]`
block in `certs/regen-certs.sh` and re-run. Commit the regenerated
Secret manifests.

## Leg A — DFSP → switch (inbound on the switch)

`Istio 1.24.1` `istio-ingressgateway` (DaemonSet on `CORE-API-ADAPTERS`
nodes) terminates DFSP→switch mTLS on `:443` and routes to `moja-*`
services on `:80`. nginx keeps `:80`.

Driven by `ansible/roles/mtls_switch/`:

1. Frees `:443` on nginx (JSON-patch removes the `https` named port).
2. Installs Gateway API CRDs + `istio-base` + `istiod` +
   `istio-ingressgateway` (helm, version pinned in
   `chart_versions.istio`).
3. Patches `:443` host/container port onto the ingress DaemonSet
   (the chart doesn't ship that port).
4. Applies `manifests/mtls/switch-inbound.yaml` — `Gateway` (`:443`,
   `mode: MUTUAL`, `credentialName: switch-mtls-creds`) + 3 ×
   `VirtualService` routing the three switch hostnames to their `:80`
   services.

Verification (post-deploy):

```bash
GPOD=$(kubectl -n istio-system get pod -l app=istio-ingressgateway -o name | head -1 | cut -d/ -f2)
kubectl -n istio-system exec ${GPOD} -- pilot-agent request GET config_dump \
  | jq '.configs[] | select(."@type"|contains("ListenersConfigDump"))' \
  | grep -i 'require_client_certificate'
# expect: "require_client_certificate": true
```

## Leg B — switch → DFSP (egress from the switch)

The harder leg. We use the **Istio egress gateway pattern**:

- A second Istio Deployment (`istio-egressgateway`) in `istio-system`
  with a **pinned ClusterIP `10.152.183.254`** originates switch→DFSP
  mTLS.
- The four switch callback Deployments
  (`moja-ml-api-adapter-handler-notification`,
  `moja-account-lookup-service`, `moja-quoting-service`,
  `moja-quoting-service-handler`) carry `hostAliases` mapping
  `sim-fsp*.local` → the egress gateway IP.
- They send plain HTTP `:80` to the gateway; the gateway resolves the
  real DFSP IP via switch CoreDNS (the `hosts{}` block lists DFSP node
  IPs) and opens mTLS `:443`.
- DFSP nginx ssl-passthrough hands `:443` to the SDK on `:4000`,
  which terminates mTLS.

Why this and not ambient/waypoint: a 2026-04-30 attempt with
`PILOT_ENABLE_IP_AUTOALLOCATE=true` + waypoint hit two intrinsic
blockers in this lab — Node.js dialed the v6 synthetic VIP that ztunnel
didn't intercept (ALS calls timed out), and Bitnami Kafka's
NetworkPolicy refused HBONE `:15008` from ambient-labelled handler
pods (consumers connected but never got partition assignment). The
egress gateway pattern keeps app pods out of the mesh entirely, so
neither blocker applies.

Resources (in this repo):

| Path | Purpose |
|---|---|
| `common/istio-egressgateway.yaml` | Helm values for the egress gateway. `service.type: None` so the chart skips its own Service (it has no `service.clusterIP` field). |
| `manifests/mtls/egressgateway-service.yaml` | Standalone Service with the **pinned ClusterIP `10.152.183.254`**. Must agree with `manifests/mojaloop/hostaliases-mtls.json`. |
| `manifests/mtls/switch-outbound.yaml` | `Gateway` (port 80, hosts `sim-fsp*.local`) + 8× `ServiceEntry` (`resolution: DNS`) + 8× `VirtualService` (URI prefix `/sim/fspNNN/inbound/` rewritten to `/`) + 8× `DestinationRule` (`MUTUAL` origination on `:443`, SNI = DFSP host). |
| `manifests/mojaloop/hostaliases-mtls.json` | The strategic-merge patch applied to the four callback Deployments. |
| `manifests/mtls/dfsp-passthrough.yaml.j2` | Per-DFSP passthrough Ingress (`:443` → SDK `:4000`); `fspNNN` substituted at apply time. |

Driven by `ansible/roles/mtls_switch/` (Phase 3 section): installs the
egress gateway, applies the standalone Service + Leg B resources,
patches switch CoreDNS with a `hosts{}` block listing the DFSP node IPs
(read from `scenarios/<scenario>/artifacts/hostaliases.json` — emitted
by `playbooks/06-generate-hostaliases.yml` during `make k8s`), and
re-points the four callback Deployments' `hostAliases`.

The DFSP side of Leg B is in `ansible/roles/dfsp/` — it enables
`--enable-ssl-passthrough` on nginx, applies the per-DFSP passthrough
Ingress, swaps the SDK volumes to `mtls-shared-creds`, and sets
`INBOUND_MUTUAL_TLS_ENABLED=true` on the SDK env.

## Pinned ClusterIP

`10.152.183.254` is the egress gateway's pinned ClusterIP, picked from
the MicroK8s default service CIDR `10.152.183.0/24`. **Two files must
agree on this IP**:

- `manifests/mtls/egressgateway-service.yaml`  → `spec.clusterIP`
- `manifests/mojaloop/hostaliases-mtls.json`   → `hostAliases[0].ip`

If a fresh cluster reports the IP taken (`Error from server: services
"..." already exists` or `ip already allocated`), pick another free
address in the high range and update both files together.

## Known gotchas

- **`istio/gateway` chart has no `service.clusterIP` field.** That's
  why we ship our own Service. Don't try `--set service.clusterIP=…` —
  it's silently dropped and you'll get a random ClusterIP.
- **CoreDNS Corefile multi-line block syntax.** `health { lameduck 5s }`
  on a single line crashes CoreDNS at startup. Each `block { ... }`
  directive must be on its own multi-line block. Both
  `ansible/roles/mtls_switch/templates/coredns-corefile.j2` and the
  per-DFSP equivalent already match the right layout.
- **Phase 3 ordering: INBOUND mTLS flip is required.** If the SDK
  hasn't flipped to TLS-serving on `:4000`, nginx ssl-passthrough hands
  TLS bytes to a non-TLS server and the gateway's TLS handshake fails
  with `OPENSSL_internal:WRONG_VERSION_NUMBER`. The dfsp role flips
  this at install time; the mtls role applies CoreDNS + egress gateway
  before that — order matters in `make deploy`.
- **Helm 4 SSA conflicts with `kubectl scale` / `kubectl set image`.**
  Once a Deployment has fields owned by `kubectl-scale` or
  `kubectl-set`, `helm upgrade` fails with `Apply failed with N
  conflicts`. The deploy roles sidestep by patching directly via
  `kubectl set env` / `kubectl patch` instead of re-running
  `helm upgrade` after the initial install. To re-take ownership for a
  helm-driven upgrade later: `helm upgrade --force-conflicts --take-ownership`.
- **Never sort nginx `args` array** (`jq … | unique`). It moves
  `/nginx-ingress-controller` off `args[0]` and the container dies
  trying to exec a literal space. Use JSON-patch `add`/`remove` at an
  explicit index — both the dfsp and mtls_switch roles already do.
- **Strategic-merge cannot delete array items** when the merge key
  matches. Removing `:443` from the nginx DaemonSet via a
  patch-array-by-name approach silently re-adds it. Use JSON-patch
  `remove` at a computed index.

## Rotation

```bash
# Edit alt_names in certs/regen-certs.sh if needed, then:
./certs/regen-certs.sh
git add certs/{switch,dfsp}-tls-secret.yaml
git commit -m "rotate mTLS certs"
make mtls SCENARIO=<scenario>     # re-applies the new switch secret
make dfsp SCENARIO=<scenario>     # re-applies the new dfsp secret
```

(The `mtls` and `dfsp` roles' `apply` steps are idempotent — they
update existing Secrets in-place.)
