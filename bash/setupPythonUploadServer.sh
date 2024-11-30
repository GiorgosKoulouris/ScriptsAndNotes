#!/bin/bash

# Desription
#   Execute the script to create a quick python file server (http) in order to serve and receive files
#
# Usage - Execute the following to get instructions
#   ./setupPythonUploadServer.sh --help

usage() {
    echo "Usage:"
    echo "  $0 <folder> <port>  Starts an upload server that will receive files on <folder> and listen on <port>"
    echo "  $0 -h               Prints usage info"
    echo "  $0 --help           Prints usage info"
}

check_args() {
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            usage
            exit
        fi
    done

    [ $# -ne 2 ] && {
        echo 'Invalid number of arguments. Exiting...'
        usage
        exit 1
    }

    serverFolder="$(realpath $1)"
    port="$2"

    # Setting the temp folder to be the directory where the script resides
    relTempFolder="$(dirname "${BASH_SOURCE[0]}")"
    tempFolder="$(realpath $relTempFolder)"
    [ ! -d "$tempFolder" ] && {
        echo "Could not locate the parent directory of this script. Exiting..."
        exit 1
    }

    [ ! -d "$serverFolder" ] && {
        echo "Directory $serverFolder does not exist. Exiting..."
        exit 1
    }
}

setup_venv() {
    # Create temp python venv, activate and install uploadserver
    echo "Setting up the python environment..."

    cd "$tempFolder"

    venvFolder="tempVenv$RANDOM"
    venvFolderFull="$(realpath $venvFolder)"
    python3 -m venv "$venvFolder"
    source "${venvFolder}/bin/activate"
    echo "Installing dependancies..."
    python3 -m pip install uploadserver
}

start_server() {
    # Start server in the folder provided
    cd "$serverFolder"
    python3 -m uploadserver $port
}

cleanup() {
    # Perform cleanup
    while true; do
        read -rp "Delete venv ($venvFolderFull)? " yn
        case $yn in
        [Yy]*)
            echo "Cleaning up..."
            rm -r "$venvFolderFull"
            break
            ;;
        [Nn]*)
            echo "No cleanup performed..."
            break
            ;;
        *)
            echo "Please answer y or n."
            ;;
        esac
    done
}

print_post_message() {
    echo "Files uploaded are located at: $serverFolder"
    echo "Bye..."
}

check_args $@
setup_venv
start_server
cleanup
print_post_message
