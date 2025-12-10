


```bash

# start SOCK and keep it running
ssh -D 1080 perf-jump-host -N

# tell kubectl to use the proxy
export HTTPS_PROXY=socks5://127.0.0.1:1080

# select the target cluster
export KUBECONFIG=/Users/ndelma/Workspace/mojaloop/perf/ml-perf-whitepaper-ws/phases/02-infrastructure/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml

kubectl get nodes

```

------------------

## Deploy K8s

```bash
export K8S_VERSION="1.30/stable"

# sudo apt update && sudo apt upgrade -y && sudo reboot

sudo snap install microk8s --classic --channel=$K8S_VERSION

sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube || true

sudo microk8s status --wait-ready

sudo microk8s enable dns
sudo microk8s enable storage
sudo microk8s enable ingress
sudo microk8s enable helm3
sudo microk8s enable metrics-server

# # Configure firewall if ufw is active
# if sudo ufw status | grep -q "Status: active"; then
#     echo "Configuring firewall..."
#     sudo ufw allow 16443/tcp  # API server
#     sudo ufw allow 10443/tcp  # Dashboard
#     sudo ufw allow 30000:32767/tcp  # NodePort range
# fi

echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
echo "alias helm='microk8s helm3'" >> ~/.bashrc

source ~/.bashrc
newgrp microk8s

mkdir -p ~/.kube
sudo microk8s config > ~/.kube/config
chmod 600 ~/.kube/config

```

## form the cluster


## () 

### Allow kubeapi on public IP
```bash
echo "--bind-address=0.0.0.0" >> /var/snap/microk8s/current/args/kube-apiserver

add IP.* in /var/snap/microk8s/current/certs/csr.conf.template
sudo microk8s refresh-certs --cert server.crt

sudo microk8s stop
sudo microk8s start

microk8s config > ~/.kube/microk8s.config
```