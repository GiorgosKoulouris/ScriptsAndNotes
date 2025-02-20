#!/bin/bash

# Install
yum install postfix
systemctl start postfix
systemctl enable postfix
yum remove sendmail
yum install s-nail
alternatives --set mta /usr/sbin/sendmail.postfix

# Configure (This is to 'relay' to Azure)
mv /etc/postfix/main.cf /etc/postfix/main.cf.bak

tee /etc/postfix/main.cf > /dev/null <<EOF
# Basic configuration for relay
relayhost = [smtp.azurecomm.net]:587
smtp_use_tls = yes
smtp_tls_security_level = encrypt
smtp_tls_ciphers = high
smtp_tls_note_starttls_offer = yes

# Authentication credentials
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/azure_sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous

# Ensure that emails use the static "From" address
sender_canonical_maps = regexp:/etc/postfix/sender_canonical

# Set hostname
myhostname = myhostname
mydomain = mydomain.com
myorigin = \$mydomain
EOF

tee /etc/postfix/azure_sasl_passwd > /dev/null <<EOF
[smtp.azurecomm.net]:587 <comServiceName>.<appID>.<tenantID>:<secretValue>
EOF

chmod 600 /etc/postfix/azure_sasl_passwd
postmap /etc/postfix/azure_sasl_passwd
systemctl restart postfix

# based on https://access.redhat.com/solutions/1591423
# remove anhy ipv6 references in /etc/hosts if ipv6 is disabled

# This is to append a suffix on the email sender (custom mapping)
tee -a /etc/postfix/sender_canonical > /dev/null <<EOF
IF !/^.*SAP@.*$/
/^([^@]+)@(.*)$/    \${1}SAP@\${2}
ENDIF
EOF

echo "sender_canonical_maps = regexp:/etc/postfix/sender_canonical" >> /etc/postfix/main.cf 

postmap /etc/postfix/sender_canonical
systemctl restart postfix

# This is for Azure size, to add a new 'From Address' on a domain in email Comm
az communication email domain sender-username create --email-service-name "TST-ECS" --resource-group "CS-TST-RG" --domain-name "mydomain" --sender-username "newUserName" --username "NewEmail"

echo "Test" | mail -s "Test Sender ReWrite" -r "sender@mydomain.com" to-someone@google.com
