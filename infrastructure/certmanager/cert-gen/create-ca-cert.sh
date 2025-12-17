openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
  -keyout ca.key -out ca.crt -subj "/CN=mojaloop-internal-ca"


kubectl create secret tls internal-root-ca \
  --cert=ca.crt --key=ca.key -n cert-manager
