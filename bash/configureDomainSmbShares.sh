# Install samba

yum install samba-winbind samba-winbind-clients

# Join
realm join --client-software=winbind domain.local --user=domainuser

# Configure Samba with AD
alternatives --display cifs-idmap-plugin
systemctl is-active winbind.service
alternatives --set cifs-idmap-plugin /usr/lib64/cifs-utils/idmapwb.so

# Verify domain info
wbinfo -u        # List AD users
wbinfo -g        # List AD groups
id 'domain\user'      # Should show AD user’s groups
wbinfo --group-info="TCOP\\Linux-Admins"
wbinfo --name-to-sid "TCOP\\Linux-Admins"

# Enable a Custom authselect Profile to restrict logins
#Backup existing settings:
authselect current # get the output
# Create a custom profile (based on winbind):
authselect create-profile tcop-winbind --base-on winbind
# Switch to the custom profile:
authselect select custom/tcop-winbind with-mkhomedir
# Modify allowed logins
vi /etc/authselect/custom/tcop-winbind/system-auth
vi /etc/authselect/custom/tcop-winbind/password-auth
# Find the auth section, and add the following line after the first pam_winbind.so line
auth sufficient pam_winbind.so require_membership_of=S-1-5-21-963892462-206672775-1346962184-1108 # wbinfo --name-to-sid "TCOP\\Linux-Admins"
authselect apply-changes

# To change shown namem from REALM\username to just username
vi /etc/samba/smb.conf # Under global make sure you have: winbind use default domain = true
systemctl restart winbind
systemctl restart smb
# If you do this, domain users/groups on sudoers files must NOT have the @domain.com suffix

# ---- Configure shares -----
# /etc/samba/smb.conf
# Under [global]
:'
vfs objects = acl_xattr
map acl inherit = yes
store dos attributes = yes
'

# For each share
:'
[projects]
   path = /shares/projects
   read only = no
   browsable = yes
   guest ok = no
   inherit acls = yes
   vfs objects = acl_xattr
   create mask = 0660
   directory mask = 0770
'

systemctl restart smb

# Removes ALL ACLs
getfacl /shares/projects
setfacl -bR /shares/projects
getfacl /shares/projects

chgrp -R FSV_Project_Writers /shares/projects
chown -R root:FSV_Project_Writers /shares/projects
chmod -R 2770 /shares/projects
getfacl /shares/projects

# Create SMB user root and set password
smbpasswd -a root

smbcacls //tcoptfsv00/projects / -U tcoptfsv00\\root

smbcacls -a 'ACL:FSV_Project_Readers:ALLOWED/OI|CI/READ' //tcoptfsv00/projects / -U tcoptfsv00\\root
smbcacls -a 'ACL:FSV_Project_Writers:ALLOWED/OI|CI/CHANGE' //tcoptfsv00/projects / -U tcoptfsv00\\root

smbcacls --delete 'ACL:FSV_Project_Writers:ALLOWED/OI|CI/CHANGE' //tcoptfsv00/projects / -U tcoptfsv00\\root

smbclient -L //tcoptfsv00 -U gkoulouris
smbclient //tcoptfsv00/projects -U gkoulouris

# \\tcoptfsv00\projects
