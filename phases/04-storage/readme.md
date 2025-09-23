



```bash
#
sudo apt update
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid



#
helm repo add longhorn https://charts.longhorn.io
helm repo update

kubectl create namespace longhorn-system


helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --set csi.kubeletRootDir="/var/snap/microk8s/common/var/lib/kubelet" \
  --set defaultSettings.createDefaultDiskLabeledNodesOnly=false \
  --set defaultSettings.replicaSoftAntiAffinity=true \
  --set defaultSettings.defaultReplicaCount=1 \
  --set defaultSettings.nodeDownPodDeletionPolicy="delete-both-statefulset-and-deployment-pod"


kubectl get storageclass
# kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'


```
