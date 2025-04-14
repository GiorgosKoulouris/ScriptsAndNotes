#!/bin/bash

# Install
yum install postfix
systemctl start postfix
systemctl enable postfix
yum remove sendmail
yum install s-nail
alternatives --set mta /usr/sbin/sendmail.postfix

# --------------- AZURE ----------------------
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

# This is for Azure size, to add a new 'From Address' on a domain in email Comm
az communication email domain sender-username create --email-service-name "TST-ECS" --resource-group "CS-TST-RG" --domain-name "mydomain" --sender-username "newUserName" --username "NewEmail"

# --------------- AWS ----------------------
mv /etc/postfix/main.cf /etc/postfix/main.cf.bak

tee /etc/postfix/main.cf > /dev/null <<EOF
# Basic configuration for relay
smtp_tls_security_level = secure
smtp_use_tls = yes
smtp_tls_note_starttls_offer = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
relayhost = [email-smtp.eu-central-1.amazonaws.com]:587

# Set hostname
myhostname = myhostname
mydomain = tillsilencebreaks.com
myorigin = \$mydomain
EOF

# Comment '-o smtp_fallback_relay=' from /etc/postfix/master.cf

tee /etc/postfix/sasl_passwd > /dev/null <<EOF
[email-smtp.eu-central-1.amazonaws.com]:587 AKIAXXXXXX:<SecretKey>
EOF

chmod 600 /etc/postfix/sasl_passwd
postmap hash:/etc/postfix/sasl_passwd

# Depends on distro, check AWS docs
postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt'
# Ubuntu
postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt'
systemctl restart postfix

# under smtp-amavis unix add > -o smtp_tls_security_level=none
# This is if you see amavis related tls errors


# based on https://access.redhat.com/solutions/1591423
# remove anhy ipv6 references in /etc/hosts if ipv6 is disabled

# ----------------------------------------------------
# This is to append a suffix on the email sender (custom mapping)
tee -a /etc/postfix/sender_canonical > /dev/null <<EOF
IF !/^.*SAP@.*$/
/^([^@]+)@(.*)$/    \${1}SAP@\${2}
ENDIF
EOF

echo "sender_canonical_maps = regexp:/etc/postfix/sender_canonical" >> /etc/postfix/main.cf 

postmap /etc/postfix/sender_canonical
systemctl restart postfix

# ----------------------------------------------------
echo "Test" | mail -s "Test Sender ReWrite" -r "from@mydomain.com" tosomeone@domain.com


# set hostname fqdn and short, also check /etc/hostname
wget https://github.com/iredmail/iRedMail/archive/1.7.2.tar.gz
tar xvf 1.7.2.tar.gz
