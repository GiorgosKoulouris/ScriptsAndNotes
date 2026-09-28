#!/bin/bash
echo "$(date +"%Y-%m-%d %H:%M:%S") - ${CRM_notify_node} ${CRM_notify_rsc} \
${CRM_notify_task} ${CRM_notify_desc} ${CRM_notify_rc} \
${CRM_notify_target_rc} ${CRM_notify_status}" >> /scripts/pacemaker_events.log
