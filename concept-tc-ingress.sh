#!/bin/bash

# as root
# set EXTDEV
EXTDEV=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
echo "payload interface $EXTDEV"

DOWNLINK=1024
echo "Downlink rate to echo ${DOWNLINK}"

# load kernel module
modeprobe ifb

# check load
lsmod |grep ifb

# set ifb0 down
ip link set dev ifb0 down

# Clear old queuing disciplines (qdisc) on the interfaces and the MANGLE table
tc qdisc del dev $EXTDEV root    # 2> /dev/null > /dev/null
tc qdisc del dev $EXTDEV ingress # 2> /dev/null > /dev/null
tc qdisc del dev ifb0 root       # 2> /dev/null > /dev/null
tc qdisc del dev ifb0 ingress    # 2> /dev/null > /dev/null
iptables -t mangle -F
iptables -t mangle -X QOS

# intrface ifb0 up
ip link set dev ifb0 up

# HTB classes on IFB with rate limiting
tc qdisc add dev ifb0 root handle 3: htb default 30
tc class add dev ifb0 parent 3: classid 3:3 htb rate ${DOWNLINK}kbit
tc class add dev ifb0 parent 3:3 classid 3:30 htb rate 400kbit ceil ${DOWNLINK}kbit
tc class add dev ifb0 parent 3:3 classid 3:33 htb rate 1400kbit ceil ${DOWNLINK}kbit


# Packets marked with "3" on IFB flow through class 3:33
tc filter add dev ifb0 parent 3:0 protocol ip handle 3 fw flowid 3:33

# Outgoing traffic from 192.168.1.50 is marked with "3"
iptables -t mangle -N QOS
iptables -t mangle -A FORWARD -o $EXTDEV -j QOS
iptables -t mangle -A OUTPUT -o $EXTDEV -j QOS
iptables -t mangle -A QOS -j CONNMARK --restore-mark
iptables -t mangle -A QOS -s 192.168.1.50 -m mark --mark 0 -j MARK --set-mark 3
iptables -t mangle -A QOS -j CONNMARK --save-mark

# Forward all ingress traffic on internet interface to the IFB device
tc qdisc add dev $EXTDEV ingress handle ffff:
tc filter add dev $EXTDEV parent ffff: protocol ip \
        u32 match u32 0 0 \
        action connmark \
        action mirred egress redirect dev ifb0 \
        flowid ffff:1

exit 0