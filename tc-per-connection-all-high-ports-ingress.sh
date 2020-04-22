#!/bin/sh

dev=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
ip_port=49152:65535
rate_limit=512kbit
rate_ceil=1024kbit
htb_class=10
# max_byte=10485760
max_byte=50000

if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

echo "Use interfaces $dev"

if [ "$1" = "enable" ]; then
    echo "enabling rate limits"
    tc qdisc del dev $dev root > /dev/null 2>&1
    tc qdisc add dev $dev root handle 1: htb

    tc class add dev $dev parent 1: classid 1:$htb_class htb rate $rate_limit ceil $rate_ceil
    tc filter add dev $dev parent 1: prio 0 protocol ip handle $htb_class fw flowid 1:$htb_class

    #iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -j MARK --set-mark $htb_class

    # small packet is probably interactive or flow control
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m length --length 0:500 -j RETURN

    # small packet connections: multi purpose (don't harm since not maxed out)
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes 0:250 --connbytes-dir both --connbytes-mode avgpkt -j RETURN

    #after 10 megabyte a connection is considered a download
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes $max_byte: --connbytes-dir both --connbytes-mode bytes -j MARK --set-mark $htb_class
    iptables -t mangle -A OUTPUT -j RETURN

elif [ "$1" = "disable" ]; then
    echo "disabling rate limits"
    tc qdisc del dev $dev root > /dev/null 2>&1

    iptables -t mangle -F
    iptables -t mangle -X

elif [ "$1" = "show" ]; then
    tc qdisc show dev $dev
    tc class show dev $dev
    tc filter show dev $dev
    iptables -t mangle -vnL INPUT
    iptables -t mangle -vnL OUTPUT
else
    echo "invalid arg $1"
fi
