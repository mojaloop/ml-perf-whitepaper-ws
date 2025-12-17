# rejected because not symetric
# openssl rsa -in jwtRS256.key -pubout -outform PEM -out jwtRS256.key.pub

# Generate private key
openssl genpkey -algorithm RSA -out jwtRS256.key -pkeyopt rsa_keygen_bits:2048
# Extract public key
openssl rsa -in jwtRS256.key -pubout -out jwtRS256.key.pub

