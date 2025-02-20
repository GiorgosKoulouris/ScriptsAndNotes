# Docs
# https://www.redhat.com/en/blog/creating-gpg-keypairs

# Notes:
#   gpg encrypts data using the public key
#   The recipient decrypts the data using the private key (and the passphrase)
#   Passphrase is only needed on decryption
#   When creating a key, you specify an ID (Name, email). This is part of the key.
#   When encrypting a file, you specify a recipient. This is the ID of the key (name, email)
#   In order to encrypt and decrypt files, keys (public or private) need to be already imported on the system
#   When decrypting a file, you dont need to specify the private key. The encrypted file contains info about the recipient. You just need the private key with this ID imported on the system

# NOTE: gpg and gpg-agent come with gnupg2 (maybe gnupg, to check)
yum install gnupg2

# To start the gpg-agent:
eval $(gpg-agent --daemon)

# NOTE: On AL2023, gpg-agent is not available. To make it available:
yum swap gnupg2-minimal gnupg2-full

# Generate key
gpg --full-generate-key
# OR
gpg --default-new-key-algo rsa4096 --gen-key

# List keys
gpg --list-secret-keys --keyid-format=long

# List public keys
gpg --list-keys

# Export the public key | Omit --output flag to just print the public key
gpg --export --armor --output gpgKey.pub keyID

# Export the public key using the recipient ID
gpg --export --armor youremail@example.com > mypubkey.asc

# Export the private key (user ID or recipient)
gpg --export-secret-key --armor --output private.pgp keyID

# Export the fingerprint
gpg --fingerprint keyID

# Import others public keys
gpg --import pubkey.asc

# Import your own private
gpg --import privatekey.asc

# Encrypt (use email or name of recipient) | Omit armor flag if you dont want armor formatting
gpg --encrypt --armor --recipient 'youremail@example.com' filename.txt

# Decrypt file
gpg --decrypt filename.txt.gpg

# Edit key (Use Name, email or ID) | then type ? to show options
gpg --edit-key keyID
# Example
trust # to edit the owner trust
passwd # to change the passphrase
save # save and quit

# Check various files
ls -la .gnupg/