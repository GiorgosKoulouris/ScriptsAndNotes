from msgraph import GraphServiceClient
from azure.identity import ClientSecretCredential
from ldap3 import Server, Connection, ALL, MODIFY_REPLACE
import asyncio
import json

# Azure AD Configuration
tenant_id = 'XXXXXXX'
client_id = 'XXXXXXX'
client_secret = 'XXXXXXX'

# LDAP Configuration
ldap_server = 'ldap://localhost:389'
ldap_user_dn = 'cn=ldapadmin,dc=thecanopener,dc=com'
ldap_password = 'XXXXXXX'

userBaseDn = 'ou=users,dc=thecanopener,dc=com'
groupBaseDn = 'ou=groups,dc=thecanopener,dc=com'

server = Server(ldap_server, get_info=ALL)
conn = Connection(server, ldap_user_dn, ldap_password, auto_bind=True)

def cleanup():
    # Clean up users
    existing_users = {}
    conn.search(userBaseDn, '(objectClass=inetOrgPerson)', attributes=['uid'])
    for entry in conn.entries:
        existing_users[entry.uid.value] = entry.entry_dn

    for uid, user_dn in existing_users.items():
        conn.delete(user_dn)

    # Clean up groups
    existing_groups = {}
    conn.search(groupBaseDn, '(objectClass=groupOfNames)', attributes=['cn'])
    for entry in conn.entries:
        existing_groups[entry.cn.value] = entry.entry_dn

    for cn, group_dn in existing_groups.items():
        conn.delete(group_dn)

    conn.unbind()

async def main():
    cleanup()

asyncio.run(main())
