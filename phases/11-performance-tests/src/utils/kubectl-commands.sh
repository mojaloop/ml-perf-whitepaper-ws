
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-fulfil --replicas=0
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-prepare --replicas=0
kubectl -n mojaloop scale deployment moja-handler-pos-batch --replicas=0
kubectl -n mojaloop scale deployment moja-ml-api-adapter-handler-notification --replicas=0
kubectl -n mojaloop scale deployment moja-ml-api-adapter-service --replicas=0
kubectl -n mojaloop scale deployment moja-quoting-service --replicas=0
kubectl -n mojaloop scale deployment moja-quoting-service-handler --replicas=0


kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-fulfil --replicas=12
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-prepare --replicas=12
kubectl -n mojaloop scale deployment moja-handler-pos-batch --replicas=8
kubectl -n mojaloop scale deployment moja-ml-api-adapter-handler-notification --replicas=18
kubectl -n mojaloop scale deployment moja-ml-api-adapter-service --replicas=12
kubectl -n mojaloop scale deployment moja-quoting-service --replicas=12
kubectl -n mojaloop scale deployment moja-quoting-service-handler --replicas=12