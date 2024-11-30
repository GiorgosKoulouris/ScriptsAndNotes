# Man page
#   https://man7.org/linux/man-pages/man1/ssh.1.html

# Connect with password
ssh username@host
# Connect with ssh key
ssh -i key.pem username@host

# Check configuration
ssh -G username@host

# Connect forcing pseudo-terminal allocation
ssh -i key.pem -t username@host

# Create SSH key
ssh-keygen -t ed25519 -b 4096 -C "comment" -f mykey
