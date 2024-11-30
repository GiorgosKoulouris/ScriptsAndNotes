yum install openldap openldap-servers openldap-clients

# fix URI and BASE
vi /etc/openldap/ldap.conf

slappwd # to retrieve hashed pw

# Root PW + config (REPLACE olcRootPW value with the hashed pw)
cat << EOF > rootpw.ldif
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}XXXXXXX
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f rootpw.ldif

# Paths may be different
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/openldap.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/dyngroup.ldif

# ldapadmin user config (local operations and FW bind user)
slappwd # to retrieve hashed pw

# suffix + ldapadmin entity (REPLACE olcRootPW value with the hashed pw)
cat << EOF > ldapadmin.ldif
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=thecanopener,dc=com

dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=ldapadmin,dc=thecanopener,dc=com

dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}XXXXXXX
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f ldapadmin.ldif

# ORG and necessary OUs
cat << EOF > org.ldif
dn: dc=thecanopener,dc=com
objectClass: top
objectClass: dcObject
objectclass: organization
o: The Can Opener

dn: cn=ldapadmin,dc=thecanopener,dc=com
objectClass: organizationalRole
cn: ldapadmin
description: LDAP Admin

dn: ou=users,dc=thecanopener,dc=com
objectClass: organizationalUnit
ou: users

dn: ou=groups,dc=thecanopener,dc=com
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D cn=ldapadmin,dc=thecanopener,dc=com -W -f org.ldif

ldapdelete -x -D "cn=ldapadmin,dc=thecanopener,dc=com" -W -r dc=thecanopener,dc=com

ldapsearch -Y EXTERNAL -H ldapi:/// -b 'ou=users,dc=thecanopener,dc=com' uid=*
ldapsearch -Y EXTERNAL -H ldapi:/// -b 'ou=groups,dc=thecanopener,dc=com' objectclass=groupOfNames

# Add dummy user
cat << EOF > user.ldif
dn: cn=dummyGroup,ou=groups,dc=thecanopener,dc=com
objectClass: groupOfNames
objectClass: top
cn: dummyGroup
member: uid=dummyUser,ou=users,dc=thecanopener
EOF

ldapadd -x -D cn=ldapadmin,dc=thecanopener,dc=com -W -f user.ldif
