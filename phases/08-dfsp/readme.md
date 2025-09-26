
## Install the DFSP

```bash
./ml-perf-whitepaper-ws/phases/08-dfsp/deploy.bash
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

## Provisioning

*provide the ttk collection to provision the simulators and mojaloop*