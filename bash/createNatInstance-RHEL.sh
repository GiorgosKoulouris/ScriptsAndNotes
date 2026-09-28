#!/bin/bash

# https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html

yum install iptables-services -y && \
systemctl enable iptables && \
systemctl start iptables

tee /etc/sysctl.d/custom-ip-forwarding.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

# This is to make the instance NAT from sourceIPs to the internet
sourceIPs="10.0.10.0/24"
mainInterface=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
/sbin/iptables -t nat -A POSTROUTING -s "$sourceIPs" -o "$mainInterface" -j MASQUERADE
/sbin/iptables -F FORWARD
service iptables save

# These are to perform DNAT to access multiple hosts via 'JUMP' (EXAMPLES)
iptables -t nat -A PREROUTING -p tcp --dport 10022 -j DNAT --to-destination 10.0.10.27:22
iptables -t nat -A POSTROUTING -p tcp --dport 22 -j MASQUERADE

iptables -t nat -A PREROUTING -p tcp --dport 33389 -j DNAT --to-destination 10.0.10.24:3389
iptables -t nat -A POSTROUTING -p tcp --dport 3389 -j MASQUERADE

