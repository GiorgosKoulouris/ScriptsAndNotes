# To check
crm configure property notification-agent="/scripts/pacemaker_notifications.sh"

# To check
crm configure primitive alert-script ocf:pacemaker:SysInfo \
        path="/scripts/pacemaker_notifications.sh"

# To check
crm configure alert my-alert path="/scripts/pacemaker_notifications.sh"

# Check
crm configure primitive alert_script ocf:pacemaker:ClusterMon \
    params user=root update=30 extra_options="--watch-fencing -E /scripts/pacemaker_notifications.sh"
crm configure clone alert_script_cl alert_script
crm configure clone nginx_cl nginx
