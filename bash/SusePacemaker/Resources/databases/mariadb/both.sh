# RHEL
dnf install -y mariadb-server galera rsync policycoreutils-python-utils mariadb-server-galera
# SLES
zypper addrepo --gpgcheck --refresh https://yum.mariadb.org/11.8/sles/15/x86_64 mariadb
zypper --gpg-auto-import-keys refresh
zypper install MariaDB-server galera-4 MariaDB-client MariaDB-shared MariaDB-backup MariaDB-common
mkdir -p /data/mysql
chown mysql:mysql /data/mysql

sed -i 's|^datadir=.*|datadir=/data/mysql|' /etc/my.cnf.d/mariadb-server.cnf
sed -i 's|^socket=.*|socket=/data/mysql/mysql.sock|' /etc/my.cnf.d/mariadb-server.cnf
sed -i 's|^bind-address=.*|bind-address=0.0.0.0|' /etc/my.cnf.d/mariadb-server.cnf
sed -i 's|^log-error=.*|log-error=/var/log/mariadb/mariadb.log|' /etc/my.cnf.d/mariadb-server.cnf
sed -i 's|^pid-file=.*|pid-file=/run/mariadb/mariadb.pid|' /etc/my.cnf.d/mariadb-server.cnf

cat <<EOF > /etc/my.cnf.d/client-custom.cnf
[client]
socket=/data/mysql/mysql.sock
EOF

# tcoptcls00
cat <<EOF > /etc/my.cnf.d/galera.cnf
# MariaDB Galera Cluster config for tcoptcls00
# /etc/my.cnf.d/galera.cnf for tcoptcls00
[mysqld]
wsrep_on=ON
datadir=/data/mysql
socket=/data/mysql/mysql.sock
bind-address=0.0.0.0
log-error=/var/log/mariadb/mariadb.log
pid-file=/run/mariadb/mariadb.pid
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_cluster_name="tcoptcls"
wsrep_cluster_address="gcomm://tcoptcls00,tcoptcls01"
wsrep_node_name="tcoptcls00"
wsrep_node_address="tcoptcls00"
EOF

# tcoptcls01
cat <<EOF > /etc/my.cnf.d/galera.cnf
# MariaDB Galera Cluster config for tcoptcls01
# /etc/my.cnf.d/galera.cnf for tcoptcls01
[mysqld]
wsrep_on=ON
datadir=/data/mysql
socket=/data/mysql/mysql.sock
bind-address=0.0.0.0
log-error=/var/log/mariadb/mariadb.log
pid-file=/run/mariadb/mariadb.pid
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_cluster_name="tcoptcls"
wsrep_cluster_address="gcomm://tcoptcls00,tcoptcls01"
wsrep_node_name="tcoptcls01"
wsrep_node_address="tcoptcls01"
EOF

# ----- tcoptcls00 -------
systemctl set-environment _WSREP_NEW_CLUSTER='--wsrep-new-cluster' && \
systemctl start mariadb && \
systemctl unset-environment _WSREP_NEW_CLUSTER && \
systemctl status mariadb
mysql_secure_installation --socket=/data/mysql/mysql.sock

mysql -u root -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
mysql -u root -e "SHOW STATUS LIKE 'wsrep_cluster_status';"

# to restart cluster bootstrap
rm -f /data/mysql/grastate.dat /data/mysql/gvwstate.dat


# ----- tcoptcls01 -------
systemctl start mariadb
mysql -u root -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
mysql -u root -e "SHOW STATUS LIKE 'wsrep_cluster_status';"
mysql -u root -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"

# Check replication
mysql -u root -e "CREATE DATABASE galera_test;"
mysql -u root -e "SHOW DATABASES;"
mysql -u root -e "DROP DATABASE galera_test;"

# Cluster stop-starts
# Cluster should be started from the node that was the last that stopped
# If you want to force it to go otherwise, on the non-last node run: 
#   sed -i 's|^safe_to_bootstrap:.*|safe_to_bootstrap: 1|' /data/mysql/grastate.dat
#   systemctl set-environment _WSREP_NEW_CLUSTER='--wsrep-new-cluster'
#   systemctl start mariadb
#   systemctl unset-environment _WSREP_NEW_CLUSTER

# Make it cluster-managed
[ -f /usr/lib/ocf/resource.d/heartbeat/galera ] || yum install resource-agents

pcs resource create tcopdb ocf:heartbeat:galera \
    binary=/usr/bin/mysqld_safe \
    config=/etc/my.cnf.d/galera.cnf \
    datadir=/data/mysql \
    enable_creation=false \
    pid=/run/mariadb/mariadb.pid \
    socket=/data/mysql/mysql.sock \
    wsrep_cluster_address=gcomm://tcoptcls00,tcoptcls01 \
    op start timeout=120s \
    op stop timeout=120s \
    op monitor interval=20s role=Master \
    op monitor interval=30s role=Slave \
    meta allow-migrate=true target-role=Started


pcs resource promotable tcopdb \
  meta master-max=2 master-node-max=1 \
       clone-max=2 clone-node-max=1 \
       notify=true


pcs resource cleanup

# Until here should be ok

# To check logs that prevent DB from starting
pcs resource debug-start tcopdb
pcs resource debug-promote tcopdb


# stop/start
pcs resource enable tcopdb
pcs resource disable tcopdb

# To update property
pcs resource update fence-aws-tcoptcls01 power_timeout=300

pcs resource move tcopdb-clone tcoptcls00

pcs resource clear tcopdb-clone

pcs resource move-with-constraint tcopdb-clone tcoptcls00
pcs constraint location tcopdb-clone prefers tcoptcls00=100

pcs constraint remove tcopdb

pcs property set maintenance-mode=true
pcs property set maintenance-mode=false

pcs constraint colocation add vip-db with tcopdb-clone INFINITY