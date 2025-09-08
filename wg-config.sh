#!/usr/bin/env bash

cd `dirname ${BASH_SOURCE[0]}`

CLIENT_TPL_FILE=/etc/wireguard/client.conf.tpl
SERVER_TPL_FILE=/etc/wireguard/server.conf.tpl
SAVED_FILE=.saved
AVAILABLE_IP_FILE=.available_ip
AVAILABLE_IP6_FILE=.available_ip6
WG_TMP_CONF_FILE=.$_INTERFACE.conf
WG_CONF_FILE="/etc/wireguard/$_INTERFACE.conf"
USERS_FOLDER=/etc/wireguard/users

source /etc/wireguard/wg-config.def
source ./ip_utils.sh

generate_cidr_ip_file_if() {
    # IPv4
    local cidr=${_VPN_NET}
    local ip mask a b c d

    IFS=$'/' read ip mask <<< "$cidr"
    IFS=. read -r a b c d <<< "$ip"
    local beg=$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))
    local host_bits=$((32-mask))
    local num_hosts=$(echo "2^$host_bits" | bc)
    local end=$((beg+num_hosts-1))
    ip=$(dec2ip $((beg+1)))
    _SERVER_IP="$ip/$mask"
    if [[ ! -f $AVAILABLE_IP_FILE ]]; then
        > $AVAILABLE_IP_FILE
        local i=$((beg+2))
        while [[ $i -lt $end ]]; do
            ip=$(dec2ip $i)
            echo "$ip/$mask" >> $AVAILABLE_IP_FILE
            i=$((i+1))
        done
    fi

    # IPv6
    if [[ -n "${_VPN_NETv6}" ]]; then
        if [[ ! -f $AVAILABLE_IP6_FILE ]]; then
            > $AVAILABLE_IP6_FILE
            ip6_expand "${_VPN_NETv6}" >> $AVAILABLE_IP6_FILE
        fi
    fi
}

get_vpn_ip() {
    local ip=$(head -1 $AVAILABLE_IP_FILE)
    if [[ $ip ]]; then
        local mat="${ip/\//\\\/}"
        sed -i "/^$mat$/d" $AVAILABLE_IP_FILE
    fi
    echo "$ip"
}

get_vpn_ip6() {
    local ip6=$(head -1 $AVAILABLE_IP6_FILE)
    if [[ $ip6 ]]; then
        local mat="${ip6/\//\\\/}"
        sed -i "/^$mat$/d" $AVAILABLE_IP6_FILE
    fi
    echo "$ip6"
}

add_user() {
    local user=$1
    local template_file=${CLIENT_TPL_FILE}
    local interface=${_INTERFACE}
    local userdir="$USERS_DIR/$user"

    mkdir -p "$userdir"
    wg genkey | tee $userdir/privatekey | wg pubkey > $userdir/publickey

    # client config file
    _PRIVATE_KEY=`cat $userdir/privatekey`
    _VPN_IP=$(get_vpn_ip)
    _VPN_IP6=$(get_vpn_ip6)
    if [[ -z $_VPN_IP && -z $_VPN_IP6 ]]; then
        echo "no available ip"
        exit 1
    fi
    # Compose Address field for client config
    local address=""
    if [[ -n $_VPN_IP ]]; then
        address="$_VPN_IP"
    fi
    if [[ -n $_VPN_IP6 ]]; then
        if [[ -n $address ]]; then
            address+=" ,$_VPN_IP6"
        else
            address="$_VPN_IP6"
        fi
    fi
    export ADDRESS="$address"
    eval "echo \"$(cat "${template_file}")\"" > $userdir/wg0.conf
    qrencode -o $userdir/$user.png  < $userdir/wg0.conf

    # change wg config
    local allowed_ips=""
    if [[ -n $_VPN_IP ]]; then
        allowed_ips="${_VPN_IP%/*}/32"
    fi
    if [[ -n $_VPN_IP6 ]]; then
        if [[ -n $allowed_ips ]]; then
            allowed_ips="${allowed_ips},${_VPN_IP6}"
        else
            allowed_ips="${_VPN_IP6}"
        fi
    fi
    if [[ ! -z "$route" ]]; then
        allowed_ips="0.0.0.0/0,::/0"
    fi
    local public_key=`cat $userdir/publickey`
    wg set $interface peer $public_key allowed-ips $allowed_ips
    if [[ $? -ne 0 ]]; then
        echo "wg set failed"
        rm -rf $user
        exit 1
    fi

    echo "$user $_VPN_IP $_VPN_IP6 $public_key" >> ${SAVED_FILE} && echo "use $user is added. config dir is $userdir"
}

del_user() {
    local user=$1
    local userdir="$USERS_DIR/$user"
    local ip key
    local interface=${_INTERFACE}

    read ip key <<<"$(awk "/^$user /{print \$2, \$3}" ${SAVED_FILE})"
    if [[ -n "$key" ]]; then
        wg set $interface peer $key remove
        if [[ $? -ne 0 ]]; then
            echo "wg set failed"
            exit 1
        fi
    fi
    sed -i "/^$user /d" ${SAVED_FILE}
    if [[ -n "$ip" ]]; then
        echo "$ip" >> ${AVAILABLE_IP_FILE}
    fi
    rm -rf $userdir && echo "use $user is deleted"
}

generate_and_install_server_config_file() {
    local template_file=${SERVER_TPL_FILE}
    local ip4 ip6 allowed_ips

    # server config file
    eval "echo \"$(cat "${template_file}")\"" > $WG_TMP_CONF_FILE
    while read user vpn_ip vpn_ip6 public_key; do
        ip4=""
        ip6=""
        if [[ -n $vpn_ip ]]; then
            ip4="${vpn_ip%/*}/32"
        fi
        if [[ -n $vpn_ip6 ]]; then
            ip6="$vpn_ip6"
        fi
        allowed_ips="$ip4"
        if [[ -n $ip6 ]]; then
            if [[ -n $allowed_ips ]]; then
                allowed_ips+=" ,$ip6"
            else
                allowed_ips="$ip6"
            fi
        fi
        if [[ ! -z "$route" ]]; then
            allowed_ips="0.0.0.0/0,::/0"
        fi
        cat >> $WG_TMP_CONF_FILE <<EOF

# $user 
[Peer]
PublicKey = $public_key
AllowedIPs = $allowed_ips
EOF
    done < ${SAVED_FILE}
    \cp -f $WG_TMP_CONF_FILE $WG_CONF_FILE
}

clear_all() {
    local interface=$_INTERFACE
    wg-quick down $interface
    > $WG_CONF_FILE
    rm -f ${SAVED_FILE} ${AVAILABLE_IP_FILE}
}

do_user() {
    generate_cidr_ip_file_if

    if [[ $action == "-a" ]]; then
        if [[ -d $user ]]; then
            echo "$user exist"
            exit 1
        fi
        add_user $user
    elif [[ $action == "-d" ]]; then
        del_user $user
    fi

    generate_and_install_server_config_file
}

init_server() {
    local interface=$_INTERFACE
    local template_file=${SERVER_TPL_FILE}

    if [[ -s $WG_CONF_FILE ]]; then
        echo "$WG_CONF_FILE exist"
        exit 1
    fi
    generate_cidr_ip_file_if
    eval "echo \"$(cat "${template_file}")\"" > $WG_CONF_FILE
    chmod 600 $WG_CONF_FILE
    wg-quick up $interface
}

list_user() {
    cat ${SAVED_FILE}
}

usage() {
    echo "usage: $0 [-a|-d|-c|-g|-i] [username] [-r]

    -i: init server conf
    -a: add user
    -d: del user
    -l: list all users
    -c: clear all
    -g: generate ip file
    -r: enable route all traffic(allow 0.0.0.0/0)
    "
}

# main
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

action=$1
user=$2
route=$3

if [[ $action == "-i" ]]; then
    init_server
elif [[ $action == "-c" ]]; then
    clear_all
elif [[ $action == "-l" ]]; then
    list_user
elif [[ $action == "-g" ]]; then
    generate_cidr_ip_file_if
elif [[ ! -z "$user" && ( $action == "-a" || $action == "-d" ) ]]; then
    do_user
else
    usage
    exit 1
fi
