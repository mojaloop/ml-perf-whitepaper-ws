# mTLS — switch ↔ DFSPs

Optional edge-mTLS layer between the Mojaloop switch and the 8 DFSP
simulators, enabled via `make mtls` (see the root
[README.md](../README.md#run-a-benchmark-scenario-from-scratch)). Single
shared CA + leaf cert (lab only — no PKI, no per-entity identities).

- **Leg A** (DFSP → switch, inbound): terminated by the Istio ingress
  gateway.
- **Leg B** (switch → DFSP, egress): originated by a per-pod Envoy
  sidecar injected into the switch's outbound-calling deployments —
  there is no centralized egress gateway.

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
| `certs/switch-tls-secret.yaml` | Secret `switch-mtls-creds` (`istio-system`). Generated, git-ignored (private key material). Mounted by the Istio ingress gateway and copied into `mojaloop` for the egress sidecars to file-mount. |
| `certs/dfsp-tls-secret.yaml` | Secret `mtls-shared-creds` (`dfsps`). Generated, git-ignored. Applied on all 8 DFSP clusters. Mounted by each `sdk-scheme-adapter`. |
| `certs/jws/jwtRS256.{key,key.pub}` | JWS signing keypair used by the SDKs (separate from mTLS but kept alongside). |

**The two generated Secret manifests are git-ignored, not committed** —
private key material shouldn't live in a public repo, even a lab-only
self-signed one. Run `certs/regen-certs.sh` once per clone before your
first `make mtls`; it writes both manifests to the fixed paths above
(`mtls_switch_tls_secret` / `dfsp_tls_secret` in the `mtls_switch`/
`mtls_dfsp` role defaults — there's nowhere else to place them). Re-run
the same script any time to rotate, or to change the SAN list (e.g. add
a 9th DFSP, in the `[alt_names]` block) — see
[Generating / rotating certs](#generating--rotating-certs) below.

## Leg A — DFSP → switch (inbound on the switch)

Istio `istio-ingressgateway` terminates DFSP→switch mTLS on `:443`
(exposed as NodePort 30443, since Cilium's `kubeProxyReplacement=false`
doesn't program hostPort) and routes to `moja-*` services on `:80`. nginx
keeps `:80` for plaintext ingress.

Driven by `ansible/roles/mtls_switch/`:

1. Frees `:443` on nginx (JSON-patch removes the `https` named port).
2. Installs Gateway API CRDs + `istio-base` + `istiod` +
   `istio-ingressgateway` (helm, version pinned in `chart_versions.istio`).
   If the target namespace runs Istio ambient, `istiod` gets the ambient
   profile overlay so sidecar↔ztunnel interop survives reinstalls.
3. Applies `manifests/mtls/switch-inbound.yaml` — `Gateway` (`:443`,
   `mode: MUTUAL`, `credentialName: switch-mtls-creds`) + 3 ×
   `VirtualService` routing the three switch hostnames to their `:80`
   services.
4. Applies upstream connection-pool `DestinationRule`s for the three
   switch services the gateway routes to (bounds Envoy's upstream pool,
   preventing an EMFILE storm under sustained load).

Verification (post-deploy):

```bash
GPOD=$(kubectl -n istio-system get pod -l app=istio-ingressgateway -o name | head -1 | cut -d/ -f2)
kubectl -n istio-system exec ${GPOD} -- pilot-agent request GET config_dump \
  | jq '.configs[] | select(."@type"|contains("ListenersConfigDump"))' \
  | grep -i 'require_client_certificate'
# expect: "require_client_certificate": true
```

## Leg B — switch → DFSP (egress from the switch)

mTLS origination happens in each calling pod's own Envoy sidecar rather
than a centralized gateway — this removes an extra in-cluster hop
(pod → gateway pod → DFSP) that cost kernel softirq under sustained load.

Driven by `ansible/roles/mtls_switch/` (Leg B section), after the guard
that the switch's egress deployments already exist (created by the
`switch` role):

1. Copies the `switch-mtls-creds` Secret into the `mojaloop` namespace
   (sidecar SDS doesn't load a `DestinationRule` `credentialName` secret
   the way gateways do, so the cert is file-mounted into `istio-proxy`
   instead).
2. Renders `ServiceEntry` / `VirtualService` / `DestinationRule` ×8 from
   `ansible/roles/mtls_switch/templates/switch-outbound-sidecar.yaml.j2`,
   using the live DFSP node IPs (from the hostAliases JSON emitted during
   `make k8s`) — always in sync, no stale IPs to maintain by hand.
3. Injects an `istio-proxy` sidecar into the three outbound deployments
   (`moja-account-lookup-service`, `moja-quoting-service-handler`,
   `moja-ml-api-adapter-handler-notification`) via pod-template
   annotations: outbound interception scoped to the DFSP `/32` ranges
   (or widened to all outbound, minus datastore ports, if the namespace
   runs Istio ambient — see below), the cert volume mount, and
   `holdApplicationUntilProxyStarts`.
4. Re-points those deployments' `hostAliases` at the real DFSP node IPs
   (dropping any leftover indirection from an older config).
5. Waits for the rollout and verifies each pod is `2/2` with certs mounted.

Path: switch pod → `http://sim-fspNNN.local/sim/fspNNN/inbound/...`
(plain HTTP `:80`) → hostAliases resolves to the real DFSP node IP → the
pod's own sidecar intercepts → `VirtualService` rewrites the path → the
`DestinationRule` originates MUTUAL TLS on `:443` using the file-mounted
certs → DFSP nginx `ssl-passthrough` → scheme-adapter (validates client
cert).

The DFSP side of Leg B is in `ansible/roles/mtls_dfsp/` (run after
`dfsp`, since it patches the already-deployed sims): enables
`--enable-ssl-passthrough` on nginx, applies the shared DFSP TLS secret,
helm-upgrades the scheme-adapter with an mTLS values overlay, applies
the per-DFSP passthrough Ingress, and re-applies the scheme-adapter
replica count (the mTLS helm upgrade runs with `--reuse-values
--take-ownership`, which resets `.spec.replicas` to the chart default).

### Istio ambient interop

If the namespace also runs Istio ambient (`make ambient`, optional —
see each scenario's own README for when it's used), sidecar-scoped DFSP
interception would deliver the switch's *internal* app↔app calls (e.g.
health/endpoint lookups) plaintext to STRICT-enrolled peers, which
reject them. Both the `mtls_switch` and `ambient` roles detect this and
widen the sidecar's outbound interception to all outbound traffic
(datastore ports still excluded, so they stay direct/PERMISSIVE) — this
converges correctly regardless of which role runs last.

### Retired: egress gateway pattern

An earlier iteration used a centralized `istio-egressgateway` Deployment
with a pinned ClusterIP as the single Leg B origination point. It's
superseded by the sidecar pattern above (removes the extra hop, no pinned
IP to keep in sync). The `mtls_switch` role still uninstalls any prior
egress-gateway install it finds (`mtls_cleanup_egressgateway`, default
`true`); its manifests are no longer kept in the repo.

## Known gotchas

- **`istio/gateway` chart has no `service.clusterIP` field.** If you ever
  need a standalone gateway Service with a pinned IP again (e.g. the
  retired egress-gateway path), set `service.type: None` in the chart
  values and ship your own Service manifest — `--set service.clusterIP=…`
  is silently dropped.
- **CoreDNS Corefile multi-line block syntax.** `health { lameduck 5s }`
  on a single line crashes CoreDNS at startup. Each `block { ... }`
  directive must be on its own multi-line block. Both
  `ansible/roles/mtls_switch/templates/coredns-corefile.j2` and the
  per-DFSP equivalent already match the right layout.
- **The DFSP-side inbound mTLS flip must land before Leg B traffic
  arrives.** If the SDK hasn't flipped to TLS-serving on `:4000`, nginx
  ssl-passthrough hands TLS bytes to a non-TLS server and the caller's
  TLS handshake fails with `OPENSSL_internal:WRONG_VERSION_NUMBER`. This
  is why `mtls_dfsp` must run after `dfsp` but is applied consistently
  across both switch and DFSP sides in the same `make mtls` invocation.
- **Helm 4 SSA conflicts with `kubectl scale` / `kubectl set image`.**
  Once a Deployment has fields owned by `kubectl-scale` or
  `kubectl-set`, `helm upgrade` fails with `Apply failed with N
  conflicts`. The deploy roles sidestep by patching directly via
  `kubectl set env` / `kubectl patch` instead of re-running
  `helm upgrade` after the initial install, or by passing
  `--force-conflicts --take-ownership` when a helm upgrade is required
  (e.g. the mTLS values overlay).
- **Never sort nginx `args` array** (`jq … | unique`). It moves
  `/nginx-ingress-controller` off `args[0]` and the container dies
  trying to exec a literal space. Use JSON-patch `add`/`remove` at an
  explicit index — both the `dfsp` and `mtls_switch` roles already do.
- **Strategic-merge cannot delete array items** when the merge key
  matches. Removing `:443` from the nginx DaemonSet via a
  patch-array-by-name approach silently re-adds it. Use JSON-patch
  `remove` at a computed index.

## Generating / rotating certs

Same command whether this is the first run after a clone or a later
rotation — it always regenerates from scratch and overwrites both
(git-ignored) manifests in place:

```bash
# Edit alt_names in certs/regen-certs.sh first, if you need to (e.g. a 9th DFSP)
./certs/regen-certs.sh
make mtls SCENARIO=<scenario>     # applies both the switch and DFSP secrets
```

(The `mtls_switch` and `mtls_dfsp` roles' apply steps are idempotent —
they update existing Secrets in-place.)
