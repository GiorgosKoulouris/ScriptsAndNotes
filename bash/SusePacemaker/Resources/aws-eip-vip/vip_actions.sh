#!/bin/bash

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --action)
        action="$2"
        shift 2
        ;;
    --eni-id)
        eni_id="$2"
        shift 2
        ;;
    *)
        echo "Unknown parameter: $1"
        echo "Usage: $0 --eni-id <eni_id> --action <attach|detach>"
        exit 1
        ;;
    esac
done

cd "$(dirname "$0")"
source venv/bin/activate
python vip_actions.py --eni-id "$eni_id" --action "$action"