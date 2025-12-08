# Generate CA key and certificate
openssl genrsa -out ca-key.pem 4096
# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=TestCA"

# Generate shared key and certificate
openssl genrsa -out shared-key.pem 4096
# Generate shared certificate signing request
openssl req -new -key shared-key.pem -out shared.csr -subj "/CN=test-dfsp"
# Generate shared certificate
openssl x509 -req -days 365 -in shared.csr \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out shared-cert.pem

# use shared-cert.pem, shared-key.pem, and ca-cert.pem 