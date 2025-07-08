# Diagrams to Copy from Documentation Repository

Copy these diagrams from the documentation repository to this directory:

1. **p2p-transfer-complete-flow.svg**
   - Source: `/documentation/docs/technical/api/assets/diagrams/sequence/figure1.svg`
   - Description: Complete P2P transfer flow (payer-initiated)

2. **8-dfsp-test-architecture.svg**
   - Create custom diagram showing:
     - 8 DFSPs (perffsp-1 through perffsp-8)
     - Load distribution (40%, 25%, 20%, 15%)
     - K6 workers generating load
     - Mojaloop switch in the center

## Custom Diagram Template for 8-DFSP Architecture:

```plantuml
@startuml 8-dfsp-test-architecture
!theme plain
skinparam backgroundColor #FEFEFE

package "K6 Load Testing Cluster" {
    [K6 Workers] as K6
}

package "Mojaloop Switch" {
    [Account Lookup] as ALS
    [Quoting Service] as QS
    [ML API Adapter] as MLAPI
    [Central Ledger] as CL
}

package "Sending DFSPs" {
    [perffsp-1\n40% load] as FSP1
    [perffsp-2\n25% load] as FSP2
    [perffsp-3\n20% load] as FSP3
    [perffsp-4\n15% load] as FSP4
}

package "Receiving DFSPs" {
    [perffsp-5] as FSP5
    [perffsp-6] as FSP6
    [perffsp-7] as FSP7
    [perffsp-8] as FSP8
}

K6 --> FSP1 : 400 TPS
K6 --> FSP2 : 250 TPS
K6 --> FSP3 : 200 TPS
K6 --> FSP4 : 150 TPS

FSP1 --> MLAPI : Transfers
FSP2 --> MLAPI : Transfers
FSP3 --> MLAPI : Transfers
FSP4 --> MLAPI : Transfers

MLAPI --> ALS : Lookup
MLAPI --> QS : Quote
MLAPI --> CL : Transfer

CL --> FSP5 : Notifications
CL --> FSP6 : Notifications
CL --> FSP7 : Notifications
CL --> FSP8 : Notifications

@enduml
```