username=''
password=''
sshKey=''

useradd -m -s /bin/bash $username
mkdir -p /home/$username/.ssh/
chmod 0700 /home/$username/.ssh/
echo $sshKey > /home/$username/.ssh/authorized_keys
chmod 0600  /home/$username/.ssh/authorized_keys
chown -R "$(id -u $username)":"$(id -g $username)" /home/$username/.ssh/
usermod --password $(echo "$password" | openssl passwd -1 -stdin) $username
echo "$username ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-$username-user && chmod 0640 /etc/sudoers.d/99-$username-user


#  -----------------------------------
# Add to group
usermod -aG wheel $username # or sudo

# modify sshd setting and sudo settings
sudo vim /etc/ssh/sshd_config
sudo visudo

# Delete any user if necessary
userName=
sudo userdel -r $userName # -r flag deletes home directory