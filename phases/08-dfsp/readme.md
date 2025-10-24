
## Install the DFSP

### default installation
```bash
./ml-perf-whitepaper-ws/phases/08-dfsp/deploy.bash
```
### with 16 replicas of sdk-scheme-adapter ( used for 1000 tps)
```bash
./ml-perf-whitepaper-ws/phases/08-dfsp/deploy-1000.bash
```

## Set DNS on each FSP

No public domain name is used. So CoreDNS must be set resolve the local domain names of the switch

```json
# Set DFS core DNS
    hosts {
      10.110.2.48 account-lookup-service.local quoting-service.local ml-api-adapter.local
      fallthrough
    }
```

```bash
sudo systemctl restart systemd-resolved
getent hosts account-lookup-service.local
```

## Provisioning

*provide the ttk collection to provision the simulators and mojaloop*