
## Install the DFSP

```bash
export KUBECONFIG=~/.kube/perf-fsp201
helm -n dfsps upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=values-fsp201.yaml

export KUBECONFIG=~/.kube/perf-fsp202
helm -n dfsps upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=values-fsp202.yaml
```

## Set DNS on each FSP

No public domain name is used. So CoreDNS must be set resolve the local domain names of the switch

```json
# Set DFS core DNS
    hosts {
      18.134.155.127 account-lookup-service.local quoting-service.local ml-api-adapter.local
      fallthrough
    }
```

```bash
sudo systemctl restart systemd-resolved
getent hosts account-lookup-service.local
```
