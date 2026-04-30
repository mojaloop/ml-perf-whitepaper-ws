



```mermaid
graph 
    subgraph dfsp
        sdk
        backend
        nginx-ingress
    end

    subgraph switch
        istio-outbound
        istio-inbound
        nginx-ingress
        switch-services
    end
    
    sdk --mtls:443--> istio-inbound --> switch-services
    istio-outbound --mtl:443--> nginx-ingress --mtls:4000--> sdk
    ops --http:80--> nginx-ingress --http:4001--> sdk
    nginx-ingress --http--> backend
```