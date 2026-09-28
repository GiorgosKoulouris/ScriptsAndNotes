mkdir -p /usr/lib/ocf/resource.d/custom/

vi /usr/lib/ocf/resource.d/custom/test_nginx
chmod +x /usr/lib/ocf/resource.d/custom/test_nginx

crm configure primitive nginx ocf:custom:test_nginx \
        op start interval=0s timeout=60s \
        op stop interval=0s timeout=40s \
        op monitor interval=10s timeout=10s \
        meta target-role=Started
crm configure clone nginx_cl nginx

crm resource refresh
crm ra info ocf:custom:test_nginx

crm configure order server-after-ip Mandatory: aws_vip nginx
crm configure colocation web_server inf: aws_vip:Started nginx:Started