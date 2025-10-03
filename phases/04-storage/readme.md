



```bash
#
sudo apt update
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid



#
helm repo add longhorn https://charts.longhorn.io
helm repo update

kubectl create namespace longhorn-system


kubectl create secret docker-registry dockerhub-secret \
--docker-server=https://index.docker.io/v1/ \
--docker-username=${DOCKERHUB_USERNAME} \
--docker-password=${DOCKERHUB_TOKEN} \
--docker-email=ndelma@gmail.com \
-n longhorn-system
kubectl patch serviceaccount default \
    -n longhorn-system \
    -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'



# Install with values file that includes tolerations for tainted nodes
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --values ml-perf-whitepaper-ws/phases/04-storage/values.yaml


kubectl get storageclass
# kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'


```
