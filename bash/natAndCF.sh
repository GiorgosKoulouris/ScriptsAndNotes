#!/bin/bash
sudo -i
username='vmadmin'
password='XXXXX'
sourceIPs="10.0.10.0/24"
newHostname="XXXXX"
sshKey=''
cfToken=''

hostnamectl set-hostname "$newHostname"

useradd -m -s /bin/bash $username
mkdir -p /home/$username/.ssh/
chmod 0700 /home/$username/.ssh/
echo $sshKey > /home/$username/.ssh/authorized_keys
chmod 0600  /home/$username/.ssh/authorized_keys
chown -R "$(id -u $username)":"$(id -g $username)" /home/$username/.ssh/
usermod --password $(echo "$password" | openssl passwd -1 -stdin) $username
echo "$username ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-$username-user && chmod 0640 /etc/sudoers.d/99-$username-user


grep -i ubuntu /etc/*release
if [ "$?" -eq 0 ]; then
	curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
	dpkg -i cloudflared.deb && 
	cloudflared service install "$cfToken"
	rm -rf cloudflared.deb
else
	curl -L --output cloudflared.rpm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
	yum localinstall -y cloudflared.rpm
	cloudflared service install "$cfToken"
	rm -rf cloudflared.rpm
fi

yum install iptables-services -y && \
systemctl enable iptables && \
systemctl start iptables

tee /etc/sysctl.d/custom-ip-forwarding.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

# Get the primary interface
mainInterface=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
/sbin/iptables -t nat -A POSTROUTING -s "$sourceIPs" -o "$mainInterface" -j MASQUERADE
/sbin/iptables -F FORWARD
service iptables save

