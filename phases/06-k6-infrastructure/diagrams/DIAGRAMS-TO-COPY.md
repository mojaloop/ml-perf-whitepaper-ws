# Diagrams to Copy/Create for K6 Infrastructure

## 1. **k6-testing-architecture.svg**

Create a custom diagram showing the K6 testing infrastructure:

```plantuml
@startuml k6-testing-architecture
!theme plain
skinparam backgroundColor #FEFEFE

package "K6 Testing VPC\n10.1.0.0/16" {
    package "K6 EKS Cluster" {
        [K6 Operator] as K6OP
        [K6 Test Jobs] as K6J
        database "Metrics Storage" as MS
        
        K6OP --> K6J : Creates/Manages
        K6J --> MS : Store results
    }
    
    [Network Load Balancer] as NLB
}

package "Mojaloop VPC\n10.0.0.0/16" {
    package "Mojaloop EKS Cluster" {
        [Mojaloop Services] as ML
        [SDK Adapters] as SDK
        [DFSPs] as DFSP
    }
}

cloud "Monitoring Stack" {
    [Prometheus] as PROM
    [Grafana] as GRAF
}

K6J --> NLB : Generate Load
NLB ..> ML : VPC Peering\n1000 TPS
ML --> SDK
SDK --> DFSP

K6J --> PROM : Export Metrics
ML --> PROM : Export Metrics
PROM --> GRAF : Visualize

note right of K6J
  - 8 x t3.2xlarge nodes
  - Isolated from Mojaloop
  - Clean measurements
end note

note left of ML
  - 15 x c5.4xlarge nodes
  - Production configuration
  - Full security enabled
end note

@enduml
```

## 2. **k6-worker-distribution.svg**

Create a diagram showing how K6 workers distribute load:

```plantuml
@startuml k6-worker-distribution
!theme plain

actor "K6 Controller" as KC
box "K6 Workers" #LightBlue
    participant "Worker 1" as W1
    participant "Worker 2" as W2
    participant "Worker 3" as W3
    participant "Worker N" as WN
end box

box "Load Distribution" #LightGreen
    participant "perffsp-1" as FSP1
    participant "perffsp-2" as FSP2
    participant "perffsp-3" as FSP3
    participant "perffsp-4" as FSP4
end box

KC -> W1 : Assign VUs (25%)
KC -> W2 : Assign VUs (25%)
KC -> W3 : Assign VUs (25%)
KC -> WN : Assign VUs (25%)

W1 --> FSP1 : 100 TPS
W1 --> FSP2 : 62.5 TPS
W2 --> FSP3 : 50 TPS
W2 --> FSP4 : 37.5 TPS
W3 --> FSP1 : 100 TPS
W3 --> FSP2 : 62.5 TPS
WN --> FSP1 : 200 TPS
WN --> FSP3 : 150 TPS

note over W1,WN : Total: 1000 TPS distributed\nacross workers and DFSPs

@enduml
```