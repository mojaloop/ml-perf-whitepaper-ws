# Infrastructure high level architecture

## 1. Overview

The infrastructure reproduces a real worl design of a Mojaloop implemenation. 

The control center provide the Gitops environment to deploy, modify, destroy the mojaloop switch and the payment manager. The control center is not directly involved in transactions.

The Mojaloop switch is deployed from the control center in its dedicated infrastructure

The mayment manager is deployed from the control center on its dedicated infrastructure. The same payment manager provide distinct namespace for each DFSP SDK resources.

Each DFSP resources including the core banking simulator and the K6 are deployed in the payment manager cluster in a dedeicated namespace


```mermaid
graph LR
  cc[Control center]
  sw[Mojaloop switch]
  

  subgraph pm [Payment manager]
    
    subgraph dfsp-501
      dfsp-501-sdk+TTK
      dfsp-501-k6
    end 

    subgraph dfsp-502
      dfsp-502-sdk+TTK
      dfsp-502-k6
    end 

    subgraph dfsp-503
      dfsp-503-sdk+TTK
      dfsp-503-k6
    end 
  
      subgraph dfsp-504
      dfsp-504-sdk+TTK
      dfsp-504-k6
    end 

    subgraph dfsp-505
      dfsp-505-sdk+TTK
      dfsp-505-k6
    end 

    subgraph dfsp-506
      dfsp-506-sdk+TTK
      dfsp-506-k6
    end 

    subgraph dfsp-507
      dfsp-507-sdk+TTK
      dfsp-507-k6
    end 

    subgraph dfsp-508
      dfsp-508-sdk+TTK
      dfsp-508-k6
    end 

  end



  cc .-> sw
  cc .-> pm

  sw <--> dfsp-501-sdk+TTK
  dfsp-501-sdk+TTK <--> dfsp-501-k6

  sw <--> dfsp-502-sdk+TTK
  dfsp-502-sdk+TTK <-->  dfsp-502-k6

  sw <--> dfsp-503-sdk+TTK
  dfsp-503-sdk+TTK <--> dfsp-503-k6

    sw <--> dfsp-504-sdk+TTK
  dfsp-504-sdk+TTK <--> dfsp-504-k6

  sw <--> dfsp-505-sdk+TTK
  dfsp-505-sdk+TTK <-->  dfsp-505-k6

  sw <--> dfsp-506-sdk+TTK
  dfsp-506-sdk+TTK <--> dfsp-506-k6

  sw <--> dfsp-507-sdk+TTK
  dfsp-507-sdk+TTK <-->  dfsp-507-k6

  sw <--> dfsp-508-sdk+TTK
  dfsp-508-sdk+TTK <--> dfsp-508-k6
```


## 2. Control center

## 3. Mojaloop switch

### 3.1. HLD

|      Layer           |     Components       |
|----------------------|----------------------|
| Applications| Mojaloop, MCM, finance portal ....
| Plateform| argocd, gitlab
| K8s-cluster| provider: microk8s <br> each node runs both a control plan and worker
| VMs| OS: Ubuntu 24.04LTS <br> size: m5.4xlarge <br> Count: 3
| Infrastructure|  AWS





### 3.2. Main components
The switch environement have below components:
- Mojaloop switch
- Finance portal
- MCM
- Stateful resources: Mysql, Mongodb, Kafka, Redis
- Monitoring stack: Grafana, prometheus, Loki
- Other tools: Vault, Keycloak, ory, external-dns, certmanager, minio, valero, longhorn
- ISTIO

## 4. Payment manager

### 4.1 HLD

|      Layer           |     Components       |
|----------------------|----------------------|
| Applications| PM$ML, dfsp-*-sim ....
| Plateform| argocd, gitlab
| K8s-cluster| provider: microk8s <br> each node runs both a control plan and worker
| VMs| OS: Ubuntu 24.04LTS <br> size: m5.4xlarge <br> Count: 3
| Infrastructure|  AWS


## DFSP simulator