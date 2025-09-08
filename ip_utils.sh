#!/usr/bin/env bash
# IPv4 and IPv6 address utilities for wg-config

# Convert decimal to IPv4 address
# Usage: dec2ip <int>
dec2ip() {
    local delim=''
    local ip dec=$1
    for e in {3..0}
    do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        ip+=$delim$octet
        delim=.
    done
    printf '%s\n' "$ip"
}

# Generate IPv6 address from prefix and host part
# Usage: gen_ipv6 <prefix> <host>
gen_ipv6() {
    local prefix=$1
    local host=$2
    python3 -c "import ipaddress; print(str(ipaddress.IPv6Address(int(ipaddress.IPv6Network(u'${prefix}').network_address)+${host})))"
}

# Expand a /64 IPv6 subnet to a list of addresses (demo: first 100)
ip6_expand() {
    local cidr="$1"
    local ip6 mask
    IFS='/' read ip6 mask <<< "$cidr"
    if [[ "$mask" != "64" ]]; then
        echo "Only /64 IPv6 subnets are supported." >&2
        return 1
    fi
    local base=$(python3 -c "import ipaddress; print(ipaddress.IPv6Network(u'$ip6/$mask').network_address)")
    for i in {1..100}; do
        local addr=$(python3 -c "import ipaddress; print(ipaddress.IPv6Address(int(ipaddress.IPv6Address(u'$base'))+$i))")
        echo "$addr/$mask"
    done
}
