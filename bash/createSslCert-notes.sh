# === Enough for a self signed cert without any special prerequisites ====
# Create self signed certificate in a single command (interactive)
openssl req -new -newkey rsa:4096 -x509 -sha256 \
    -nodes \
    -days 30 \
    -keyout key.pem \
    -out cert.pem


# ======== Full procedure ==============

# Create a key and a request in a signle command
openssl req -newkey rsa:2048 -keyout domain.key -out domain.csr
# With unencrypted key
openssl req -newkey rsa:2048 -noenc -keyout domain.key -out domain.csr

# Create a Self-Signed Root CA
openssl req -x509 -sha256 -days 360 -newkey rsa:2048 -keyout rootCA.key -out rootCA.crt

# Create and use extension file to follow SAN standards
cat << EOF > domain.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = mydomain.com
DNS.2 = myotherdomain.com
IP.1 = 10.0.10.5
IP.1 = 10.0.12.6
EOF

# Create a cert using the key, the request and the extension file previously create, signed by the authority created above
openssl x509 -req -CA rootCA.crt -CAkey rootCA.key -in domain.csr -out domain.crt -days 365 -CAcreateserial -extfile domain.ext

# Create a cert using the key and request previously created, signed by the authority created above
openssl x509 -req -CA rootCA.crt -CAkey rootCA.key -in domain.csr -out domain.crt -days 180 -CAcreateserial

# View certificate info
openssl x509 -text -noout -in domain.crt

# Convert certificates
    # Convert PEM to DER
    openssl x509 -in domain.crt -outform der -out domain.der
    # Convert PEM to PKCS12
    openssl pkcs12 -inkey domain.key -in domain.crt -export -out domain.pfx
