

## Deploy

```bash
kubectl create ns mojaloop
# deploy backend
#helm repo add mojaloop http://mojaloop.io/helm/repo/
helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml

kubectl apply -f network-policy.yaml # allow monitoring to scrap in ml ns
```

## Set DNS

No public domain name is used. So CoreDNS must be set resolve the local domain names of each FSP

```json
    hosts {
      3.8.122.104 sim-fsp201.local
      18.130.31.179 sim-fsp202.local
      fallthrough
    }
```

<!-- ```bash
sudo systemctl restart systemd-resolved
getent hosts account-lookup-service.local
``` -->

## Provision

*provision mojaloop*
