mkdir -p /usr/lib/ocf/resource.d/custom/

crm configure primitive dummy2 ocf:custom:promotable \
        op start interval=0s timeout=60s \
        op stop interval=0s timeout=40s \
        op monitor interval=10s timeout=10s role=Master \
        op monitor interval=11s timeout=10s role=Slave

crm configure clone promotable_cl promotable \
        promotable=true