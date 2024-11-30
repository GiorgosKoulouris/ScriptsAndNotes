# 
# Description
#   These are the core steps to configure an LDAP server on a Linux VM
#   Packages and config file location may vary based on the flavor used

# Install packaged -- RHEL Based
yum install openldap openldap-servers openldap-clients

# Modify URI and BASE options
vi /etc/openldap/ldap.conf

# Retrieve a hashed pw for your root user
slappwd

# Root password modification -- Modify olcRootPW value with the hashed password from the previous step
cat << EOF > rootpw.ldif
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}XXXXXXX
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f rootpw.ldif
rm -f rootpw.ldif

# Apply core configs -- Paths may be different
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/openldap.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/dyngroup.ldif

# Retrieve a hashed pw for your admin user
slappwd # to retrieve hashed pw

# Create the suffix and the admin user for the automated operations
#   Modify olcRootPW value with the hashed pw
#   Modify olcSuffix and olcRootDN accordingly
cat << EOF > ldapadmin.ldif
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=mydomain,dc=local

dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=ldapadmin,dc=mydomain,dc=local

dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}XXXXXXX
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f ldapadmin.ldif
rm -f ldapadmin.ldif

# Create the Org and necessary OUs
#   Modify any DN accordingly
cat << EOF > org.ldif
dn: dc=mydomain,dc=local
objectClass: top
objectClass: dcObject
objectclass: organization
o: The Can Opener

dn: cn=ldapadmin,dc=mydomain,dc=local
objectClass: organizationalRole
cn: ldapadmin
description: LDAP Admin

dn: ou=users,dc=mydomain,dc=local
objectClass: organizationalUnit
ou: users

dn: ou=groups,dc=mydomain,dc=local
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D cn=ldapadmin,dc=mydomain,dc=local -W -f org.ldif
rm -f org.ldif


# ------- AdHoc localmands for troubleshooting ---------
# Search in the users OU all UIDs
ldapsearch -Y EXTERNAL -H ldapi:/// -b 'ou=users,dc=mydomain,dc=local' uid=*
# Search in the groups OU all groupOfNames
ldapsearch -Y EXTERNAL -H ldapi:/// -b 'ou=groups,dc=mydomain,dc=local' objectclass=groupOfNames

