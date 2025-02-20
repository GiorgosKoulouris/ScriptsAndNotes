#!/bin/bash

# Function to detect OS
patch_linux() {
    if [[ -f /etc/os-release ]]; then
        # Use os-release for modern Linux distros
        . /etc/os-release
        case "$ID" in
            ubuntu)
                patch_apt
                ;;
            rhel|redhat)
                patch_yum
                ;;
            ol)
                patch_yum
                ;;
            sles)
                patch_zypper
                ;;
            opensuse)
                patch_zypper
                ;;
            amzn)
                patch_yum
                ;;
            *)
                exit 1
                ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        patch_yum
    elif [[ -f /etc/SuSE-release ]]; then
        patch_zypper
    elif [[ -f /etc/system-release ]]; then
        # Generic fallback for system-release
        if grep -q "Amazon Linux" /etc/system-release; then
            patch_yum
        fi
    else
        exit 1
    fi
}

patch_apt() {
    apt update && apt upgrade -y || exit 1
}

patch_yum() {
    yum update -y || exit 1
}

patch_zypper() {
    zypper up -y || exit 1
}

# Run the function
patch_linux
