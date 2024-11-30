from msgraph import GraphServiceClient
from azure.identity import ClientSecretCredential
from ldap3 import Server, Connection, ALL, MODIFY_REPLACE, MODIFY_ADD, MODIFY_DELETE
import asyncio

# Azure AD Configuration
tenant_id = 'XXX-XXX'
client_id = 'XXX-XXX'
client_secret = 'XXXXX~XXX'

# LDAP Configuration -- DC does not need to be the same with EntraID domain
ldap_server = 'ldap://localhost:389'
ldap_user_dn = 'cn=ldapadmin,dc=mydomain,dc=local'
ldap_password = 'XXXXXXXX'

userBaseDn = 'ou=users,dc=mydomain,dc=local'
groupBaseDn = 'ou=groups,dc=mydomain,dc=local'

async def initClient():
    # Set up the credentials and Graph client
    credential = ClientSecretCredential(tenant_id, client_id, client_secret)
    client = GraphServiceClient(credential)
    return client

async def getUsers(client):
    res = await client.users.get()
    users = res.value
    return users

async def getGroups(client):
    res = await client.groups.get()
    groups = res.value
    return groups

async def getMemberhips(client, userID):
    res = await client.users.by_user_id(userID).member_of.get()
    memberships = res.value
    return memberships

async def getUserData(users, client): 
    user_group_data = []

    for user in users:
        user_info = {
            'id': user.id,
            'displayName': user.display_name,
            'surname': user.surname,
            'userPrincipalName': user.user_principal_name,
            'groups': []
        }
        
        # Fetch groups for each user
        userGroups = await getMemberhips(client, user.id)
        user_info['groups'] = [group.display_name for group in userGroups]
        user_group_data.append(user_info)

    return user_group_data

async def initLdapConnection():
    server = Server(ldap_server, get_info=ALL)
    conn = Connection(server, ldap_user_dn, ldap_password, auto_bind=True)
    return conn

async def terminateLdapConnection(conn):
    conn.unbind()
    
async def syncLdapUsers(conn, userData):
    # Sync Users
    existing_users = {}
    conn.search(userBaseDn, '(objectClass=inetOrgPerson)', attributes=['uid'])
    for entry in conn.entries:
        existing_users[entry.uid.value] = entry.entry_dn
        
    for user in userData:
        uid = user['userPrincipalName']
        user_dn = f'uid={uid},{userBaseDn}'
        
        if uid not in existing_users:
            conn.add(user_dn, attributes={
                'objectClass': ['inetOrgPerson', 'organizationalPerson', 'person', 'top'],
                'sn': user['surname'],
                'cn': user['displayName'],
                'uid': uid
            })
        else:
            conn.modify(existing_users[uid], {
                'sn': [(MODIFY_REPLACE, [user['surname']])]
            })

    # Delete users that are no longer in Azure AD
    for uid, user_dn in existing_users.items():         
        if uid not in [user['userPrincipalName'] for user in userData]:
            conn.delete(user_dn)

async def syncLdapGroups(conn, groups):
    # Add the dummyUser
    dummyUserDn = f'uid=dummyUser,{userBaseDn}'
    conn.add(dummyUserDn, attributes={
                    'objectClass': ['inetOrgPerson', 'organizationalPerson', 'person', 'top'],
                    'sn': 'DummyUser',
                    'cn': 'Dummy User',
                    'uid': 'dummyUser'
                })
    existing_groups = {}
    conn.search(groupBaseDn, '(objectClass=groupOfNames)', attributes=['cn'])
    for entry in conn.entries:
        existing_groups[entry.cn.value] = entry.entry_dn
    
    for group in groups:
        groupName = group.display_name
        group_dn = f'cn={groupName},{groupBaseDn}'
        if groupName not in existing_groups:
            # Add the dummy user because groupOfNames must have at least 1 member
            conn.add(group_dn, attributes={
                'objectClass': ['groupOfNames', 'top'],
                'cn': groupName,
                'member': dummyUserDn
            })
            
    # Delete groups that are no longer in Azure AD
    for groupName, group_dn in existing_groups.items():         
        if groupName not in [group.display_name for group in groups]:
            conn.delete(group_dn)

async def syncLdapMemberships(conn, userData, groups):
    for user in userData:
        user_uid = user['userPrincipalName']
        user_dn = f'uid={user_uid},{userBaseDn}'
        desiredGroups = user["groups"]
        
        conn.search(groupBaseDn, '(member=%s)' % user_dn, attributes=['cn'])
        current_groups = [entry.cn.value for entry in conn.entries] if conn.entries else []
       
        # Determine groups to add and remove
        groups_to_add = set(desiredGroups) - set(current_groups)
        groups_to_remove = set(current_groups) - set(desiredGroups)
        
        # Add user to new groups
        for group in groups_to_add:
            group_dn = f'cn={group},{groupBaseDn}'
            conn.modify(group_dn, { 'member': [(MODIFY_ADD, [user_dn])] })

        # Remove user from groups they shouldn't be in
        for group in groups_to_remove:
            group_dn = f'cn={group},{groupBaseDn}'
            conn.modify(group_dn, { 'member': [(MODIFY_DELETE, [user_dn])] })

async def main():
    client = await initClient()
    users = await getUsers(client)
    groups = await getGroups(client)
    userData = await getUserData(users, client)
    conn = await initLdapConnection()
    await syncLdapUsers(conn, userData)
    await syncLdapGroups(conn, groups)
    await syncLdapMemberships(conn, userData, groups)
    await terminateLdapConnection(conn)
    
asyncio.run(main())

