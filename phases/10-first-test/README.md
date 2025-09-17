

## How to access the services from PC

### DNS config

Setup the PC DNS host file and restart the service

```bash
vi /etc/hosts
```

```txt
127.0.0.1      prometheus.local grafana.local ml-api-adapter.local central-ledger.local account-lookup-service.local account-lookup-service-admin.local quoting-service.local central-settlement-service.local transaction-request-service.local central-settlement.local bulk-api-adapter.local moja-simulator.local sim-payerfsp.local sim-payeefsp.local sim-testfsp1.local sim-testfsp2.local sim-testfsp3.local sim-testfsp4.local mojaloop-simulators.local finance-portal.local operator-settlement.local settlement-management.local testing-toolkit.local testing-toolkit-specapi.local
```


### port forward

```bash
export KUBECONFIG=~/.kube/perf-test-202509041315-sw

kubectl port-forward -n ingress daemonset/nginx-ingress-microk8s-controller 80:80 443:443 --address 0.0.0.0
```

### Access services

