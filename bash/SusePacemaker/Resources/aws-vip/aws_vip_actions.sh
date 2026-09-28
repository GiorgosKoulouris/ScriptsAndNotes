#!/bin/bash
# Location: /scripts/pacemaker/helpers/aws_vip_actions.sh

. /usr/lib/ocf/resource.d/heartbeat/.ocf-shellfuncs

# INIT
ENI_ID=""
REGION=""
action=""
ip_address=""

get_metadata() {
    TOKEN=`curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 30"`
    ENI_MAC="$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/)"
    ENI_ID="$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$ENI_MAC/interface-id)"
    REGION="$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)"
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --action)
            action="$2"
            shift 2
            ;;
        --ip-address)
            ip_address="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 --ip-address <ip> --action <attach|detach|monitor>"
            exit 1
            ;;
        esac
    done
}

assign_ip() {
    aws ec2 assign-private-ip-addresses \
        --network-interface-id "$ENI_ID" \
        --private-ip-addresses "$IP" \
        --allow-reassignment \
        --region "$REGION"
}

unassign_ip() {
    aws ec2 unassign-private-ip-addresses \
        --network-interface-id "$ENI_ID" \
        --private-ip-addresses "$IP" \
        --region "$REGION"
}

monitor_status() {
    aws ec2 describe-network-interfaces \
        --network-interface-ids "$ENI_ID" \
        --region "$REGION" \
        --query "NetworkInterfaces[0].PrivateIpAddresses[?PrivateIpAddress=='$target_ip']" \
        --output text | grep -q "$target_ip"

    [ $? -ne 0 ] && exit $OCF_NOT_RUNNING
}

main() {
    parse_args "$@"
    get_metadata

    case "$action" in
        attach)
            assign_ip
            exit $OCF_SUCCESS
            ;;
        detach)
            unassign_ip
            exit $OCF_SUCCESS
            ;;
        monitor)
            monitor_status
            exit $OCF_SUCCESS
            ;;
        *)
            echo "Usage: $0 {attach|detach|monitor}"
            exit $OCF_ERR_GENERIC
    esac
}

main "$@"
