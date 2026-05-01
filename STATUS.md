# Restructure status

Branch `feat/restructure` (off `feat/mtls`), 17 commits, all local.

## What got done

| # | Commit | Description |
|---|---|---|
| C1  | `2296982` | terraform/ to project root |
| C2  | `e2039a3` | ansible/ to project root |
| C3  | `4714337` | common/ for base config + helm values |
| C4  | `1f0157f` | scenarios/ to root + rename `config-override` → `overrides` |
| C5  | `c60572c` | charts/k6/ for the local k6 helm chart |
| C6  | `c01a495` | manifests/ for static k8s manifests |
| C7  | `f643b40` | certs/ for lab TLS secrets |
| C8  | `102a69c` | ttk-collections/ for TTK JSON collections |
| C9  | `549b4f4` | tools/ + docs/cheatsheet.md (consolidates kubectl/kafka commands) |
| C10 | `ab11731`+`388b18d` | drop infrastructure/ + performance-tests/ + 3 stray .md files; relocate keepers (monitoring, regen-certs, jws); add monitoring role |
| C11a | `bbe7954` | ansible roles: backend, switch, mtls_switch + _common scaffold |
| C11b | `bb9d60e` | ansible roles: dfsp (per-FSP loop with mTLS Phase 1B), k6 |
| C11c | `f9e8eb9` | ansible roles: switch_onboard, dfsp_onboard (TTK), als_provision, sim_provision |
| C11d | `fc81038` | ansible roles: smoke_test, load_test |
| C12 | `7b144b2` | root Makefile rewritten around 14 atomic stages |
| C13 | `441da5e` | README rewrite + docs/{architecture,mtls,parameter-tuning}.md |

Final tree at the root: `ansible/ certs/ charts/ common/ docs/ manifests/
scenarios/ terraform/ tools/ ttk-collections/` + `Makefile` + `README.md`
+ `CLAUDE.md` + `LICENSE.md` + `CHANGELOG.md` + `CODEOWNERS`.

## Autonomous decisions made (pre-approved by user)

1. **TTK runner approach: in-cluster Job (path A)** with the
   `mojaloop/ml-testing-toolkit-client-lib:13.4.4` image. Per-collection
   ConfigMap built from local files; Job runs `node /opt/app/cli.js -e
   env.json -i master.json`. **Verify on real deploy** that the CLI
   args + image entrypoint are still correct — fall back to
   `ansible.builtin.uri` loops (path B) if the image is broken.
2. **JWS-fix image kept in `ansible/roles/dfsp/defaults/main.yml`** as
   `dfsp_sdk_image_override: kirgene/sdk-scheme-adapter:jws-fix` with
   a TODO comment to drop when upstream ships the fix.
3. **Per-FSP values in `common/dfsp/values-fsp{201..208}.yaml`**
   (transient location). The dfsp role consumes them via
   `dfsp_values_dir: "{{ common_dir }}/dfsp"`. If you'd rather keep
   per-FSP files alongside the dfsp role, move them under
   `ansible/roles/dfsp/files/per_fsp/` and update the default.
4. **Scenarios split into `overrides/` (helm values) + `configmaps/`
   (per-service JSON)**. The `switch` role auto-detects
   `scenarios/<x>/configmaps/` and patches matching ConfigMaps if the
   directory exists.
5. **Test results in `scenarios/<x>/results/<UTC-timestamp>/`** as
   per-pod log files (k6 doesn't easily yield a single JSON dump
   without operator-side annotations).
6. **TTK collections kept as a flat-ish tree under `ttk-collections/`**
   (preserves `master.json` cross-references). Roles target subdirs:
   `hub/provisioning/for_golden_path/MojaloopHub_Setup` for
   switch_onboard; `MojaloopSims_Onboarding` + `CGS_Specific` for
   dfsp_onboard. **Did not split** into hub-setup/ + dfsp-onboarding/.
7. **`monitoring` role added** with `mojaloop/promfana` chart pinned
   to whatever `helm repo update` returns. The user said "monitoring
   is planned and must be kept" — but the original README pointed at a
   feature branch. **Verify on real deploy** that the upstream chart
   is published.

## What needs live-deploy verification

Each of these is shaped correctly but hasn't run end-to-end:

- All ansible roles syntax-check clean. None has been *executed* against
  a real cluster — every role assumes the kubeconfig + `inventory.yaml`
  + `hostaliases.json` from the existing playbooks 01-06 are present
  under `scenarios/<scenario>/artifacts/`.
- The TTK CLI command line (`node /opt/app/cli.js -e env.json -i
  master.json`) is the documented invocation pattern but not verified
  against image `mojaloop/ml-testing-toolkit-client-lib:13.4.4`. If
  the image's entrypoint is different, the Job will fail; check pod
  logs and adjust `command:` in
  `ansible/roles/{switch_onboard,dfsp_onboard}/templates/ttk-job.yaml.j2`.
- The `switch` role's `mojaloop_configmap_patches` map maps
  ConfigMap names to scenario JSON files. **Verify the names match**
  the ConfigMaps actually shipped by the mojaloop chart at v17.1.0.
- The `als_provision` role uses selector
  `app.kubernetes.io/name=mysql` to find the mysql pod — **may need
  adjustment** depending on what `example-mojaloop-backend` v17.1.0
  ships (some scenarios use `mysql-operator`'s selector).
- `als_provision` calls `MYSQL_ROOT_PASSWORD` from env. The Makefile
  loads `scenarios/<scenario>/.env` automatically — make sure that
  file has the right value for the running cluster.
- The `mtls_switch` role's CoreDNS patch reads
  `scenarios/<scenario>/artifacts/hostaliases.json` and parses
  `.spec.template.spec.hostAliases[]`. **Confirm playbook 06 still
  emits that exact shape.** If it changed during the restructure, the
  template will silently produce wrong host entries.
- `tools/curl-pod.yaml` is referenced by `sim_provision` and
  `smoke_test`. The roles `kubectl apply` it; verify the namespace
  in the manifest (`k6-test`) matches `sim_curl_ns` /
  `smoke_curl_ns`.
- `manifests/mtls/dfsp-passthrough.yaml.j2` is applied via shell `sed
  s/fspNNN/fspXXX/g` in the dfsp role. **Verify** the template still
  has the `fspNNN` placeholder (it was originally a `.template` file
  renamed in C6 — confirm the placeholder string survived).
- `infrastructure/dfsp/generate-tls/` was dropped in C10. If anyone
  was using `generate-tls/generate.sh` as their cert-rotation script
  (instead of `certs/regen-certs.sh`), they'll need to switch.

## Known unknowns

- The `monitoring` role assumes `mojaloop/promfana` is on
  `https://mojaloop.io/helm/repo/`. The original README mentioned a
  branch (`fix/grafana-promteheus-upgrade`) — if the chart isn't
  upstream yet, set `monitoring_chart` to a local path or vendored
  copy. Currently no `make deploy` chains monitoring; you have to
  call `make monitoring` separately.
- The `load_test` role polls `TestRun.status.stage` until
  `"finished"`. If your scenario uses an older k6-operator that
  exposes a different status field, the `wait` loop will spin until
  `load_test_wait_timeout`. Adjust the jsonpath if needed.
- `make terraform-plan` writes the plan to
  `scenarios/<scenario>/artifacts/terraform.plan` and
  `terraform-apply` consumes it from there. The path is hardcoded —
  if you're calling terraform directly outside the Makefile, the plan
  file convention is: artifacts/ for terraform state-adjacent things.
- The `_common` role's pre-flight tries to `wait_for` SOCKS on
  127.0.0.1:1080 with a 2-second timeout. If you skip `make tunnel`
  and the tunnel happens to be up via some other means (e.g. an
  always-on autossh), it'll still pass. If you use a different SOCKS
  port, override `https_proxy` in your inventory.

## How to verify it actually deploys

```bash
make terraform-init
make terraform-apply  SCENARIO=500tps      # provision AWS
make tunnel           SCENARIO=500tps
make k8s              SCENARIO=500tps      # microk8s + kubeconfigs
# Then go through the chain individually for first run, watching for failures:
make backend          SCENARIO=500tps
make switch           SCENARIO=500tps
make mtls             SCENARIO=500tps
make dfsp             SCENARIO=500tps
make k6               SCENARIO=500tps
make onboard          SCENARIO=500tps      # TTK Jobs — most likely place to fail
make provision        SCENARIO=500tps
make smoke            SCENARIO=500tps      # MUST PASS before make load
make load             SCENARIO=500tps
```

If any stage fails, the role is idempotent — fix and re-run.
