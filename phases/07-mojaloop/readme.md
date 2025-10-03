

## Deploy

```bash
# deploy backend
#helm repo add mojaloop http://mojaloop.io/helm/repo/
helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/07-mojaloop/values.yaml

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
              "ip": "10.110.2.83",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.110.2.8",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.110.2.166",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.110.2.131",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.110.2.193",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.110.2.199",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.110.2.126",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.110.2.184",
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
              "ip": "10.110.2.83",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.110.2.8",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.110.2.166",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.110.2.131",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.110.2.193",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.110.2.199",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.110.2.126",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.110.2.184",
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
              "ip": "10.110.2.83",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.110.2.8",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.110.2.166",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.110.2.131",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.110.2.193",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.110.2.199",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.110.2.126",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.110.2.184",
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
              "ip": "10.110.2.83",
              "hostnames": ["sim-fsp201.local"]
            },
            {
              "ip": "10.110.2.8",
              "hostnames": ["sim-fsp202.local"]
            },
            {
              "ip": "10.110.2.166",
              "hostnames": ["sim-fsp203.local"]
            },
            {
              "ip": "10.110.2.131",
              "hostnames": ["sim-fsp204.local"]
            },
            {
              "ip": "10.110.2.193",
              "hostnames": ["sim-fsp205.local"]
            },
            {
              "ip": "10.110.2.199",
              "hostnames": ["sim-fsp206.local"]
            },
            {
              "ip": "10.110.2.126",
              "hostnames": ["sim-fsp207.local"]
            },
            {
              "ip": "10.110.2.184",
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


10.110.2.126 sim-sim-fsp201.local
10.110.2.10 sim-sim-fsp202.local
10.110.2.241 sim-sim-fsp203.local
10.110.2.55 sim-sim-fsp204.local
10.110.2.98 sim-sim-fsp205.local
10.110.2.210 sim-sim-fsp206.local
10.110.2.198 sim-sim-fsp207.local
10.110.2.196 sim-sim-fsp208.local

