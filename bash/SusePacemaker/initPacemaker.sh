#!/bin/bash

crm configure
primitive apache_service systemd:apache2 \
    op monitor interval=10s timeout=20s \
    op start timeout=40s \
    op stop timeout=60s

group cups_group cups_service
property resource-stickiness=100
colocation cups_on_one_node inf: cups_service
order cups_order inf: cups_service:start
commit
exit

crm status