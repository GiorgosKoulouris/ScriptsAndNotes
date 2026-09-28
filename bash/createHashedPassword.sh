#!/bin/bash

read -s -p "Enter password:" password
echo
ansible all -i localhost, -m debug -a "msg={{ '$password' | password_hash('sha512', 'lefkvhbjekv') }}" | \
 awk -F'"msg": "' '{print $2}' | awk -F'"' '{print $1}' | grep -v "^$"