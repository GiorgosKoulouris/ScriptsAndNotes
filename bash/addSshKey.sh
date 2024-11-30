#!/bin/bash

#
# Execute the script with one IP as argument. This will add the host-ssh-key of the target server in the known host of your user.
# It will remove any other entries of this host before adding this one
#
# By default, it fetches ecdsa keys. Modify this option to fetch other formats if necessary
#   Possible values: ecdsa, ed25519, ecdsa-sk, ed25519-sk, or rsa
#   Multiple types can be fetched if you specify multiple comma-separated algorithms
# 

privateIPs=("$1")
algorithm=ecdsa

for ip in "${privateIPs[@]}"
do
    echo "Fetching $algorithm keys for $ip."
    newKeys=`(ssh-keyscan -t $algorithm $ip)`
    if [ $? -eq 0 ]; then
        newRsaKey=`(echo $newKeys | grep ecdsa-sha2)`
        if [ $? -eq 0 ]; then
            grep -vE "^$ip " ~/.ssh/known_hosts > ./tmpfile && mv ./tmpfile ~/.ssh/known_hosts && \
                echo "Deleted old $algorithm keys for $ip."
            echo $newRsaKey | tee -a ~/.ssh/known_hosts && \
                echo "Added new $algorithm keys for $ip."
        else
            echo "No keys with $algorithm encryption for $ip."
        fi
    else
        echo "Could not connect to $ip."
    fi
    echo
done
