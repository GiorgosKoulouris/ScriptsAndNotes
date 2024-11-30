#!/bin/bash

# https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html

yum install iptables-services -y && \
systemctl enable iptables && \
systemctl start iptables

tee /etc/sysctl.d/custom-ip-forwarding.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

# Get the primary interface
sourceIPs="10.0.10.0/24"
mainInterface=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
/sbin/iptables -t nat -A POSTROUTING -s "$sourceIPs" -o "$mainInterface" -j MASQUERADE
/sbin/iptables -F FORWARD
service iptables save
