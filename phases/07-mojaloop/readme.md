

## Deploy

```bash
# deploy backend
#helm repo add mojaloop http://mojaloop.io/helm/repo/
# helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 -f ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml -f ml-perf-whitepaper-ws/phases/07-mojaloop/values-override-200.yaml

## Used for getting 500 TPS
# helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 -f ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml -f ml-perf-whitepaper-ws/phases/07-mojaloop/values-override-500.yaml

## Used for getting 1000 TPS
# helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 -f ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml -f ml-perf-whitepaper-ws/phases/07-mojaloop/values-override-1000-replication.yaml

## Used for getting 2000 TPS
helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 -f ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml -f ml-perf-whitepaper-ws/phases/07-mojaloop/values-override-2000.yaml

# # to fix
# kubectl apply -f ml-perf-whitepaper-ws/phases/07-mojaloop/network-policy.yaml # allow monitoring to scrap in ml ns

kubectl patch deployment moja-quoting-service-handler \
  --namespace mojaloop \
  --type='strategic' \
  --patch='{
    "spec": {
      "template": {
        "spec": {
          "hostAliases": [
            {
              "ip": "10.112.2.132",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.112.2.103",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.112.2.59",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.112.2.150",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.112.2.53",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.112.2.219",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.112.2.244",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.112.2.172",
              "hostnames": ["sim-fsp208.local"]
            }
          ]
        }
      }
    }
  }'


kubectl patch deployment moja-account-lookup-service \
  --namespace mojaloop \
  --type='strategic' \
  --patch='{
    "spec": {
      "template": {
        "spec": {
          "hostAliases": [
            {
              "ip": "10.112.2.132",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.112.2.103",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.112.2.59",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.112.2.150",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.112.2.53",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.112.2.219",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.112.2.244",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.112.2.172",
              "hostnames": ["sim-fsp208.local"]
            }
          ]
        }
      }
    }
  }'


kubectl patch deployment moja-ml-api-adapter-handler-notification \
  --namespace mojaloop \
  --type='strategic' \
  --patch='{
    "spec": {
      "template": {
        "spec": {
          "hostAliases": [
            {
              "ip": "10.112.2.132",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.112.2.103",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.112.2.59",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.112.2.150",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.112.2.53",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.112.2.219",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.112.2.244",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.112.2.172",
              "hostnames": ["sim-fsp208.local"]
            }
          ]
        }
      }
    }
  }'




kubectl patch statefulset.apps/moja-ml-testing-toolkit-backend \
  --namespace mojaloop \
  --type='strategic' \
  --patch='{
    "spec": {
      "template": {
        "spec": {
          "hostAliases": [
            {
              "ip": "10.112.2.132",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.112.2.103",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.112.2.59",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.112.2.150",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.112.2.53",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.112.2.219",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.112.2.244",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.112.2.172",
              "hostnames": ["sim-fsp208.local"]
            }
          ]
        }
      }
    }
  }'


```

## Set DNS

No public domain name is used. So CoreDNS must be set resolve the local domain names of each sim-fsp

```json
    hosts {
      3.8.122.104 sim-sim-fsp201.local
      18.130.31.179 sim-sim-fsp202.local
      fallthrough
    }
```

<!-- ```bash
sudo systemctl restart systemd-resolved
getent hosts account-lookup-service.local
``` -->

## Provision

*provision mojaloop*


ml-api-adapter
quoting-service
account-lookup-service

