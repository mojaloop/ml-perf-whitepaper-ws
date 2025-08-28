# Deploy mojaloop

```bash
helm repo add stable https://charts.helm.sh/stable
helm repo add incubator https://charts.helm.sh/incubator
helm repo add kiwigrid https://kiwigrid.github.io
helm repo add kokuwa https://kokuwaio.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo add codecentric https://codecentric.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add mojaloop-charts https://mojaloop.github.io/charts/repo 
helm repo add redpanda https://charts.redpanda.com
#
helm repo add mojaloop https://mojaloop.io/helm/repo/
helm repo update


helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --create-namespace
helm -n mojaloop upgrade --install moja mojaloop/mojaloop --version 17.0.0
helm -n mojaloop test moja --logs


helm -n monitoring upgrade --install promfana mojaloop/promfana --create-namespace
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: NetworkPolicy
metadata:
    name: hn-nodes-custom
    namespace: mojaloop # mojaloop namespace
spec:
    ingress:
    - from:
    - ipBlock:
        cidr: 10.1.26.0/24 # pods CIDR
    podSelector: {}
    policyTypes:
    - Ingress
    EOF

```