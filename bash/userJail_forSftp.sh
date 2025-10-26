# ========= System config =========
# Backup SSHD config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Check that the following exist on /etc/ssh/sshd_config
:'
Subsystem sftp internal-sftp

Match Group sftpusers
    ForceCommand internal-sftp
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    PasswordAuthentication yes
'

# Restart sshd
systemctl restart sshd

# Create the group
groupadd sftpusers

# Create the home parent dir
mkdir /sftp/users
# Creatw the data dir
mkdir /sftp/data
chmod 700 /sftp/data

# ========= User creation =========
# Create the user and set password
home_parent_dir=/sftp/users
new_username=gkoulouris
sftp_groupname=sftpusers
useradd -g $sftp_groupname -s /sbin/nologin -d $home_parent_dir/$new_username -m $new_username
passwd $new_username
mkdir $home_parent_dir/$new_username/files
chown root:root $home_parent_dir/$new_username
chmod 755 $home_parent_dir/$new_username
chown $new_username:$sftp_groupname $home_parent_dir/$new_username/files
chmod 755 $home_parent_dir/$new_username/files

# ======= Create folders for binding =======
sftp_groupname=sftpusers
data_dir=/sftp/data
target_folder_name=mynewfolder
mkdir $data_dir/$target_folder_name
chown root:$sftp_groupname $data_dir/$target_folder_name
chmod 775 $data_dir/$target_folder_name

# ======= Bind folders =======
home_parent_dir=/sftp/users
new_username=gkoulouris
data_dir=/sftp/data
target_folder_name=mynewfolder

mkdir $home_parent_dir/$new_username/files/$target_folder_name
echo "$data_dir/$target_folder_name $home_parent_dir/$new_username/files/$target_folder_name none  bind  0  0" >> /etc/fstab
mount $home_parent_dir/$new_username/files/$target_folder_name 
# With mount : mount --bind $data_dir/$target_folder_name $home_parent_dir/$new_username/files/$target_folder_name


