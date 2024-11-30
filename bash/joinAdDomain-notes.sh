# 
# Description
#   Follow these steps to join a linux server on an Active Directory domain
# 

# Fix DNS settings
#   DNS Servers
#   Search Domains
# 
# Debian/Ubuntu 
#   https://repost.aws/knowledge-center/ec2-static-dns-ubuntu-debian
# AmazonLinux2023
#   Edit /etc/systemd/resolved.conf and modify DNS and Domain values 
# RHEL
#   Use nmcli (example)
cat /etc/resolv.conf # Check current config
nmcli con # Get the connections
nmcli con mod "System eth0" ipv4.dns "10.0.10.30" # Modify the DNS servers
nmcli con mod "System eth0" ipv4.dns-search "testdomain.local" # Modify search domains
systemctl restart NetworkManager # Apply
cat /etc/resolv.conf # Verify

# --------------- Install packages - AmazonLinux ----------------
# https://docs.aws.amazon.com/directoryservice/latest/admin-guide/join_linux_instance.html
yum install samba-common-tools realmd oddjob oddjob-mkhomedir sssd adcli krb5-workstation

# -------------- Install packages - RHEL Based -----------------
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/integrating_rhel_systems_directly_with_windows_active_directory/index
yum install samba-common-tools realmd oddjob oddjob-mkhomedir sssd adcli krb5-workstation

# -------------- Install packages - Ubuntu/Debian -----------------
# https://ubuntu.com/server/docs/how-to-set-up-sssd-with-active-directory
apt install sssd-ad sssd-tools realmd adcli

# -------------- Install packages - SLES -----------------
# https://www.suse.com/support/kb/doc/?id=000021263
zypper in realmd adcli sssd sssd-tools sssd-ad samba-client

# Verify that the domain is resolvable
nslookup testdomain.local
realm -v discover testdomain.local

# Set the FQDN of the server based on its hostname
hostnamectl set-hostname hostname.testdomain.local
hostname -f # verify
hostname -s # verify

# Join the domain
realm join --user=domainadmin testdomain.local
realm list # To verify

# Modify sssd config to match your needs - modify accordingly
cat << EOF > /etc/sssd/sssd.conf
[sssd]
domains = testdomain.local
config_file_version = 2
services = nss, pam

[domain/testdomain.local]
ad_domain = testdomain.local
krb5_realm = TESTDOMAIN.LOCAL
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = True
fallback_homedir = /home/%u
access_provider = ad
EOF

# Restart sssd service and verify
systemctl restart sssd
systemctl status sssd

# Verify Kerberos functionality using a domain user
kinit testuser
klist

# Configure logins - Permit a group to login
realm permit -g groupName
# Configure logins - Permit a user to login
realm permit myuser
# Verify by printing sssd conf
cat /etc/sssd/sssd.conf

# Leave the domain
realm leave testdomain.local --user=domainadmin
realm list