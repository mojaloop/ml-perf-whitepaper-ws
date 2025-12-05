
## Create the infra

```bash
# create infra
cd terraform
terraform init
terraform plan
terraform apply
cd ..

```


## Connect

```bash
ssh -J ubuntu@jump-host-ip ubuntu@targer-host-ip -i ~/.ssh/private-key

# local port forward through the bastion to access k8s. To improve
ssh -N -L 8080:localhost:80 -L 8443:localhost:443 k8s-node
```