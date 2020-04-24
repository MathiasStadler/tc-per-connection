#!/bin/sh

# set -e

# settings
dev=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
ip_port=49152:65535
rate_limit=512kbit
rate_ceil=1024kbit
htb_class=10
# max_byte=10485760
max_byte=50000
# Interface virtual for incomming traffic
tin1="ifb0"

htb_egress_class=3
htb_ingress_class=4

# load modul for ifb
# “numifbs=1” indicates 
# that one virtual 
# communication ports are created.
# from here
# https://choreonoid.org/en/manuals/latest/trafficcontrol/index.html
modprobe ifb numifbs=1

# set interface up
ip link set dev $tin1 up

# root check
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# list interfeces
echo "Use egress interfaces $dev"
echo "Use ingress interfaces $tin1"

# commands
if [ "$1" = "enable" ]; then
    echo "enabling rate limits"
    # delete egress
    tc qdisc del dev $dev root > /dev/null 2>&1
    tc qdisc del dev $dev root handle 1: htb
    # delete ingress
    tc qdisc del dev $tin1 root
    tc qdisc del dev $tin1 root handle 2: htb

    ### tc qdisc add dev $dev root handle 1: htb
    # handle all traffic
    tc qdisc add dev $dev handle ffff: ingress
    # Redirecto ingress $dev to egress $tin1
    tc filter add dev $dev parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $tin1


    echo "tc class add dev $dev"
    tc class add dev $dev parent 1: classid 1:$htb_egress_class htb rate $rate_limit ceil $rate_ceil
    tc filter add dev $dev parent 1: prio 0 protocol ip handle $htb_egress_class fw flowid 1:$htb_egress_class
    echo "tc class add dev $tin1"
    tc class add dev $tin1 parent 2: classid 2:$htb_ingress_class htb rate $rate_limit ceil $rate_ceil
    tc filter add dev $tin1 parent 2: prio 0 protocol ip handle $htb_ingress_class fw flowid 2:$htb_ingress_class
    


    #iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -j MARK --set-mark $htb_class

    # small packet is probably interactive or flow control
    # egress
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m length --length 0:500 -j RETURN
    # ingress
    iptables -t mangle -A INPUT -p tcp --sport $ip_port -m length --length 0:500 -j RETURN
    
    # small packet connections: multi purpose (don't harm since not maxed out)
    # engress
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes 0:250 --connbytes-dir both --connbytes-mode avgpkt -j RETURN
    # ingress
    iptables -t mangle -A INPUT -p tcp --sport $ip_port -m connbytes --connbytes 0:250 --connbytes-dir both --connbytes-mode avgpkt -j RETURN
    

    # after 10 megabyte a connection is considered a download
    # egress
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes $max_byte: --connbytes-dir both --connbytes-mode bytes -j MARK --set-mark $htb_egress_class
    iptables -t mangle -A OUTPUT -j RETURN
    # ingress
    iptables -t mangle -A INPUT -p tcp --sport $ip_port -m connbytes --connbytes $max_byte: --connbytes-dir both --connbytes-mode bytes -j MARK --set-mark $htb_ingress_class
    iptables -t mangle -A INPUT -j RETURN

elif [ "$1" = "disable" ]; then
    echo "disabling rate limits"
    
    # engress
    tc qdisc del dev $dev root > /dev/null 2>&1
    # ingress
    tc qdisc del dev $tin1 root > /dev/null 2>&1

    iptables -t mangle -F
    iptables -t mangle -X

elif [ "$1" = "show" ]; then
    # egress
    tc qdisc show dev $dev
    tc class show dev $dev
    tc filter show dev $dev
    # ingress
    tc qdisc show dev $tin1
    tc class show dev $tin1
    tc filter show dev $tin1
    # iptables
    iptables -t mangle -vnL INPUT
    iptables -t mangle -vnL OUTPUT
elif [ "$1" = "showtree" ]; then
    # show tree
    tc -s -g class show dev $dev
    tc -s -g class show dev $tin1

elif [ "$1" = "reset" ]; then
    tc qdisc del root dev $tin1
    tc qdisc del dev $tin1 ingress
    tc qdisc del dev $tin1 root
    tc qdisc del dev $tin1 root

    tc qdisc del root dev $dev
    tc qdisc del dev $dev ingress
    tc qdisc del dev $dev root
    tc qdisc del dev $dev root

else
    echo "invalid arg $1"
fi
