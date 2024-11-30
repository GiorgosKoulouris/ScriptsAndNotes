# Create V3 Read-Only user
net-snmp-create-v3-user -ro -A snmppass -X snmppass -a SHA-256 -x AES snmpuser

# Perform SNMP walk
snmpwalk -v3 -u snmpuser -l authPriv -a SHA-256 -A snmppass -x AES -X snmppass 10.0.10.23 .1.3.6.1.4.1.2021.4.3