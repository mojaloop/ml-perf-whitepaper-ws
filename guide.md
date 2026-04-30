

1. Terraform provisioning — AWS infra (VPC, bastion, instances, NLB)
```bash
cd infrastructure/provisioning/terraform
make init && make plan && make apply
cd ../../..
```

3. SOCKS5 proxy — required for all subsequent kubectl/helm commands
```bash
# from terminal 1 (keep it open to not kill the SOCKS5 proxy)
ssh -D 1080 perf-jump-host -N 
```

2. Kubernetes clusters (Ansible) — MicroK8s on all nodes
```bash
cd infrastructure/kubernetes/ansible
make deploy   # runs all 4 playbooks: install, switch-cluster, fsp-clusters, kubeconfig
cd ../../..
```

4. k8s and helm access
```bash
# from terminal 2
export HTTPS_PROXY=socks5://127.0.0.1:1080
export KUBECONFIG=~/Workspace/mojaloop/ml-iac3/legacy/ml-perf/ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
```


<!-- 5. Monitoring — infrastructure/monitoring/ (Prometheus + Grafana) -->

6. Backend — infrastructure/backend/ (Kafka, MySQL, MongoDB, Redis)
```bash

kubectl create ns mojaloop
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend \
  --version 17.1.0 \
  -f performance-tests/results/500tps/config-override/backend.yaml


```

7. Mojaloop switch — infrastructure/mojaloop/ (Helm chart + per-TPS overrides + hostAliases patches)

8. DFSP simulators — infrastructure/dfsp/deploy.bash (fsp201–fsp208, update SWITCH_IP and REPLICAS first)

9. k6 infrastructure — infrastructure/k6-infrastructure/setup-k6-infra.bash (k6 Operator + CoreDNS patches)

10. DFSP onboarding — via Testing Toolkit at http://testing-toolkit.local/admin/outbound_request

11. MSISDN registration — run the two scripts in performance-tests/src/utils/

12. Test execution — performance-tests/src/scripts/trigger-tests.sh
