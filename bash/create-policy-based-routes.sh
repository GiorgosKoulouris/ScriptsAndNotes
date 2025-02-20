#!/bin/bash

#############################################################################################################################
# Overview:                                                                                                                 #
#   This script will create all policy-based routing rules to make all traffic egress from the same                         #
#   interface that ingressed the system from. This is to avoid asymmetric traffic flows.                                    #
#                                                                                                                           #
# Note: The script needs to be executed against all interfaces except the main one                                          #
#                                                                                                                           #
# Usage:                                                                                                                    #
#    ./create-policy-based-routes.sh --interface-name <name> --create-service <true|false>                                  #
# Usage with manual default gateway:                                                                                        #
#    ./create-policy-based-routes.sh --interface-name <name> --create-service <true|false> --default-gateway <ipAddress>    #
#                                                                                                                           #
# If --create-service is set to false, routes will not be persistent between reboots. Usefull for testing.                  #
# If --create-service is set to true, a service will be create to be executed on every boot, making                         #
#   the setup reboot consistent                                                                                             #
#############################################################################################################################


script_log() {
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$current_time] - $1: $2"
    [[ "$1" != 'INF'  &&  "$1" != 'WRN' ]] && exit 1 || {
        echo > /dev/null
    }
}

parse_args() {
    # Initialize variables
    interfaceName=""
    createService=""
    defaultGW=""

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --interface-name)
                interfaceName="$2"
                routeTableName="${interfaceName}_rt"
                shift 2
                ;;
            --create-service)
                createService="$2"
                shift 2
                ;;
            --default-gateway)
                defaultGW="$2"
                shift 2
                ;;
            *)
                script_log WRN "Unknown parameter: $1"
                script_log ERR "Usage: $0 --interface-name <name> --create-service <true|false>"
                ;;
        esac
    done

    # Check if required arguments are provided
    if [[ -z "$interfaceName" || -z "$createService" ]]; then
        script_log ERR "Usage: $0 --interface-name <name> --create-service <true|false>"
    fi

    # Validate CREATE_SERVICE argument
    if [[ "$createService" != "true" && "$createService" != "false" ]]; then
        script_log ERR "Argument Error: --create-service must be either 'true' or 'false'."
    fi
}

perform_prechecks() {

    if [ "$createService" == 'true' ]; then
        [ "$(ps --no-headers -o comm 1)" == 'systemd' ] && {
            script_log INF "System runs with systemd. Proceeding..."
        } || {
            script_log ERR "System does not run with systemd. Exiting..."
        }
    fi

    ipCommand="$(which ip)"
    [ $? -eq 0 ] && {
        script_log INF "ip command is available ($ipCommand). Proceeding..."
    } || {
        script_log ERR "ip command is not available. Exiting..."
    }

    ip link | grep -Eq " $interfaceName:" && {
        script_log INF "Interface exists. Proceeding..."
    } || {
        script_log ERR "Interface $interfaceName does not exist. Exiting..."
    }

    defaultRouteCount=$(ip route | grep -E $interfaceName | grep -E "^default " | wc -l)
    [[ $defaultRouteCount -eq 0 && -z $defaultGW ]] && {
        script_log WRN "No default route was found for interface $interfaceName."
        script_log WRN "Manually specify the gateway to create a default route by running:"
        script_log WRN "    $0 --interface-name <name> --create-service <true|false> --default-gateway <ipAddress>"
        script_log ERR "Exiting..."
    }

    [ ! -d "/etc/iproute2/" ] && {
        mkdir /etc/iproute2/
        script_log INF "Created directory /etc/iproute2/"
    }

    [ ! -f "/etc/iproute2/rt_tables" ] && {
        touch /etc/iproute2/rt_tables
        script_log INF "Created file /etc/iproute2/rt_tables"
    }

    grep -qE " $routeTableName" /etc/iproute2/rt_tables && {
        script_log WRN "A route table with the same name exists. Review the file: /etc/iproute2/rt_tables"
        script_log WRN "If the route table is not needed, delete the entry from the file (table name: $routeTableName)"
        script_log ERR "Exiting..."
    } || {
        script_log INF "No route table with the same name exists. Proceeding..."
    }
    
    ip rule list | grep -q "iif $interfaceName "
    [ $? -eq 0 ] && {
        script_log WRN "A rule related with this interface already exists."
        script_log WRN "Review the rules by running: ip rule list"
        script_log WRN "If the rules are not needed, execute the following and then re-run the script: ip rule del iif $interfaceName"
        script_log ERR "Exiting..."
    }

    if [ "$createService" == 'true' ]; then
        serviceName="policy-routes-$interfaceName.service"
        systemctl list-units | grep -q $serviceName && {
            script_log WRN "A service with the same file already exists ($serviceName). Review the service first."
            script_log ERR "Exiting..."
        } || {
            script_log INF "No service with the same file exists. Proceeding..."
        }

        serviceUnitFile="/etc/systemd/system/$serviceName"
        [ -f $serviceUnitFile ] && {
            script_log WRN "A unit file already exists ($serviceUnitFile). Review its content first."
            script_log ERR "Exiting..."
        } || {
            script_log INF "No related unit files found. Proceeding..."
        }

        startServiceFile="/scripts/addPolicyRoutes-$interfaceName.sh"
        [ -f $startServiceFile ] && {
            script_log WRN "Start script already exists ($startServiceFile). Review its content first."
            script_log ERR "Exiting..."
        } || {
            script_log INF "No script for start procedure found. Proceeding..."
        }

        stopServiceFile="/scripts/removePolicyRoutes-$interfaceName.sh"
        [ -f $stopServiceFile ] && {
            script_log WRN "Stop script already exists ($stopServiceFile). Review its content first."
            script_log ERR "Exiting..."
        } || {
            script_log INF "No script for stop procedure found. Proceeding..."
        }

    fi
}

initServiceFiles() {
    if [ "$createService" == 'true' ]; then
        [ ! -d /scripts ] && mkdir /scripts
        echo "#!/bin/bash" > $startServiceFile
        echo "#!/bin/bash" > $stopServiceFile
        chmod 700 $startServiceFile
        chmod 700 $stopServiceFile
        > $serviceUnitFile

        cat << EOF > $serviceUnitFile
[Unit]
Description=Add policy based routes for $interfaceName
After=network.target

[Service]
ExecStart=/scripts/addPolicyRoutes-$interfaceName.sh
ExecStop=/scripts/removePolicyRoutes-$interfaceName.sh
RemainAfterExit=true
Type=forking

[Install]
WantedBy=multi-user.target
EOF
    fi
}

startService() {
    if [ "$createService" == 'true' ]; then
        systemctl daemon-reload
        systemctl enable $serviceName
        systemctl start $serviceName && {
            script_log INF "Service run successfully"
            script_log INF "Review its status: systemctl status $serviceName"
            script_log INF "Review unit file: $serviceUnitFile"
            script_log INF "Review start commands at: $startServiceFile"
            script_log INF "Review stop commands at: $stopServiceFile"
        } || {
            script_log WRN "Service failed to start: $serviceName"
            script_log WRN "Review its status: systemctl status $serviceName"
            script_log ERR "Review logs: journalctl -xeu $serviceName"
        }
    fi

}

createRouteTableEntry() {
    tableNumber=100
    while grep -qE "^$tableNumber " /etc/iproute2/rt_tables; do
        ((tableNumber++))
    done
    echo "$tableNumber $routeTableName" >> /etc/iproute2/rt_tables
    script_log INF "Route table created..."
}

createRule() {
    addRuleCommand="$ipCommand rule add dev $interfaceName lookup $routeTableName || true"
    deleteRuleCommand="$ipCommand rule del dev $interfaceName lookup $routeTableName || true"

    interfaceIP="$($ipCommand a show $interfaceName | grep inet | awk -F' ' '{print $2}' | awk -F'/' '{print $1}')"
    addFromRuleCommand="$ipCommand rule add from $interfaceIP lookup $routeTableName || true"
    deleteFromRuleCommand="$ipCommand rule del from $interfaceIP lookup $routeTableName || true"
    
    if [ "$createService" == 'true' ]; then
        echo "$addRuleCommand" >> $startServiceFile
        echo "$addFromRuleCommand" >> $startServiceFile
        echo "$deleteRuleCommand" >> $stopServiceFile
        echo "$deleteFromRuleCommand" >> $stopServiceFile
    else
        eval "$addRuleCommand"
        eval "$addFromRuleCommand"
    fi
}

createRoutes(){
    defaultRoutes="$(ip route | grep -E $interfaceName | grep -E "^default ")"
    localRoutes="$(ip route | grep -E $interfaceName | grep -Ev "^default ")"

    while IFS=$'\n' read -r route; do
        dest="$(echo "$route" | awk -F' ' '{print $1}')"

        addRouteCommand="$ipCommand route add $dest dev $interfaceName table $routeTableName || true"
        deleteRouteCommand="$ipCommand route del $dest dev $interfaceName table $routeTableName || true"

        if [ "$createService" == 'true' ]; then
            echo "$addRouteCommand" >> $startServiceFile
            echo "$deleteRouteCommand" >> $stopServiceFile
        else
            eval "$addRouteCommand"
        fi

    done < <(echo "$localRoutes" | grep -Ev "^$")

    [ -z $defaultGW ] && {
        gw="$(echo "$route" | awk -F'via ' '{print $2}'| awk -F' ' '{print $1}')"

        while IFS=$'\n' read -r route; do
            dest="$(echo "$route" | awk -F' ' '{print $1}')"

            addRouteCommand="$ipCommand route add $dest dev $interfaceName table $routeTableName || true"
            deleteRouteCommand="$ipCommand route del $dest via $gw dev $interfaceName table $routeTableName || true"

            if [ "$createService" == 'true' ]; then
                echo "$addRouteCommand" >> $startServiceFile
                echo "$deleteRouteCommand" >> $stopServiceFile
            else
                eval "$addRouteCommand"
            fi
        done < <(echo "$defaultRoutes" | grep -Ev "^$")

    } || {
        gw="$defaultGW"
        dest="default"

        addRouteCommand="$ipCommand route add $dest dev $interfaceName table $routeTableName || true"
        deleteRouteCommand="$ipCommand route del $dest via $gw dev $interfaceName table $routeTableName || true"

        if [ "$createService" == 'true' ]; then
            echo "$addRouteCommand" >> $startServiceFile
            echo "$deleteRouteCommand" >> $stopServiceFile
        else
            eval "$addRouteCommand"
        fi
    }
}

parse_args $@
perform_prechecks
initServiceFiles
createRouteTableEntry
createRule
createRoutes
startService
