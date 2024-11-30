# LDAP Server

## Overview
Scripts for implementing an LDAP server on a Linux VM that will sync the directory structrure (users and groups) of an EntraID tenant.
This is to avoid having Domain Controllers syncing with Entra, which requires usually bigger and more expensive VMs as well as a paid version of EntraID.

## Intructions
- Execute the following to install the dependecnies (if you need a virtual python environment, proceed accordingly): 

    ```bash
    python -m pip install -r requirements.txt
    ```
- Follow the steps on serverConfig.sh file. These will install an LDAP server and create a user to use for all replicating actions.
- Then schedule a job to execute sync_entra_with_ldap.py according to your frequency needs.
- Execute the cleanup_ldap_dir to delete any user on your LDAP server. This is helpful to reset the local LDAP server state and resync from the begginng during toubleshooting.