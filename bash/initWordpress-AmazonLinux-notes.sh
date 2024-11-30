wpDirectory=/var/www/wordpress
wpConfFile=/etc/httpd/conf.d/wordpress.conf

yum update

dnf install wget php-mysqlnd httpd php-fpm php-mysqli mariadb105-server php-json php php-devel -y

wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
[ ! -f ./wordpress/wp-config.php ] && echo "Creating wp-config.php..." && touch ./wordpress/wp-config.php || echo "wp-config.php exists..."
mkdir "$wpDirectory"
cp -r wordpress/* "$wpDirectory"
rm -rf wordpress/ latest.tar.gz

systemctl start mariadb
systemctl start httpd

# In MYSQL
mysql -e 'create database wpDatabase;'
mysql -e 'create user ''@'localhost' identified by "";'
mysql -e 'grant all privileges ON wpDatabase.* TO ''@'localhost';'

mysql -e 'create user @'localhost' identified by "";'
mysql -e 'grant all privileges ON *.* TO ''@'localhost' with grant option;'
mysql -e 'create user @'10.0.10.10' identified by "";'
mysql -e 'grant all privileges ON *.* TO ''@'' with grant option;'
mysql -e 'flush privileges;'

# Fix file ownership and perimissions
find "$wpDirectory" -type f -exec chmod 644 {} + && \
find "$wpDirectory" -type d -exec chmod 755 {} + && \
chmod 600 "$wpDirectory"/wp-config.php && \
chown -R apache:apache /var/www

tee -a /etc/httpd/conf/httpd.conf <<EOF
<Directory "$wpDirectory">
    Require all granted
    AllowOverride ALL
</Directory>
EOF

touch "$wpConfFile"
tee -a "$wpConfFile" <<EOF
<VirtualHost *:80>
    ServerName test.com
    DocumentRoot "$wpDirectory"

    # ErrorLog ${APACHE_LOG_DIR}/error.log
    # CustomLog ${APACHE_LOG_DIR}/access.log combined

    # SSLEngine on
    # SSLCertificateFile /etc/apache2/certs/tsbr.pem
    # SSLCertificateKeyFile /etc/apache2/certs/tsbr-key.pem
</VirtualHost>

<VirtualHost *:80>
    ServerName www.test.com
    Redirect 301 / http://test.com/
</VirtualHost>
EOF

# Disable SELinux if necessary
getenforce | grep -iq Permissive && { 
    echo "SELinux already in Permissive mode..." 
} || {
    echo "Setting SELinux to Permissive..."
    setenforce 0
    echo "Modify /etc/selinux/config and reboot to verify"
}

systemctl enable httpd mariadb
systemctl restart httpd