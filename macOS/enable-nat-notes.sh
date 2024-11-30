# On pf.conf, replace the IP with any IP/CIDR you want to accept NAT
# On pf.conf, replace en1 with the interface you will receive the traffic from

# -------- Enable nat ---------

vi /etc/pf.conf

# Add these
nat pass on utun2 from 10.24.24.55 to any -> (utun2)
pass in on en1 from 10.24.24.55 to any keep state
pass out on utun2 from 10.24.24.55 to any keep state

# Enable forwarding
sysctl -w net.inet.ip.forwarding=1

# Run these to update config
pfctl -d && pfctl -f /etc/pf.conf && pfctl -e && pfctl -sr

# -------- Disable nat ---------
vi /etc/pf.conf

# Comment these
nat pass on utun2 from 10.24.24.55 to any -> (utun2)
pass in on en1 from 10.24.24.55 to any keep state
pass out on utun2 from 10.24.24.55 to any keep state

# Disable forwarding
sysctl -w net.inet.ip.forwarding=0

# Run these to update config
pfctl -d && pfctl -f /etc/pf.conf && pfctl -e && pfctl -sr
