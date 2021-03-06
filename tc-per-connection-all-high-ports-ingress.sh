#!/bin/sh

# set -e

# settings
dev=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
ip_port=1025:65535
# rate_limit=1024kbit
rate_egress_limit=3072kbit
# rate_ingress_limit=1024kbit
# rate_ingress_limit=512kbit
rate_ingress_limit=256kbit

# @ TODO not used rate_ceil=1024kbit
# @TODO old check to delete  htb_class=10
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

    echo "tc qdisc add dev $dev"
    tc qdisc add dev $dev root handle 1: htb default 10
    
    # handle all traffic
    tc qdisc add dev $dev handle ffff: ingress
    
    # Redirec to ingress $dev to egress $tin1
    tc filter add dev $dev parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $tin1
    
    # tc qdisc add
    echo "tc qdisc add dev $tin1"
    
    # https://linux.die.net/man/8/tc-htb
    # default minor-id
    # Unclassified traffic gets sent to the class with this minor-id.
    tc qdisc add dev $tin1 root handle 2: htb default 10
    tc class add dev $tin1 parent 2: classid 2:1 htb rate $rate_ingress_limit
    tc class add dev $tin1 parent 2:1 classid 2:10 htb rate $rate_ingress_limit

    echo "tc class add dev $dev"
    tc class add dev $dev parent 1: classid 1:$htb_egress_class htb rate $rate_egress_limit # ceil $rate_ceil
    tc filter add dev $dev parent 1: prio 0 protocol ip handle $htb_egress_class fw flowid 1:$htb_egress_class
    # HINT: set-mark not work for ifb device
    ## echo "tc class add dev $tin1"
    ## tc class add dev $tin1 parent 2: classid 2:$htb_ingress_class htb rate $rate_limit ceil $rate_ceil
    ## tc filter add dev $tin1 parent 2: prio 0 protocol ip handle $htb_ingress_class fw flowid 2:$htb_ingress_class

    #iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -j MARK --set-mark $htb_class

    # small packet is probably interactive or flow control
    # egress
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m length --length 0:500 -j RETURN
    # ingress
    ## iptables -t mangle -A INPUT -p tcp --sport $ip_port -m length --length 0:500 -j RETURN
    
    # small packet connections: multi purpose (don't harm since not maxed out)
    # engress
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes 0:250 --connbytes-dir both --connbytes-mode avgpkt -j RETURN
    # ingress
    ## iptables -t mangle -A INPUT -p tcp --sport $ip_port -m connbytes --connbytes 0:250 --connbytes-dir both --connbytes-mode avgpkt -j RETURN

    # after 10 megabyte a connection is considered a download
    # egress
    # iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -m connbytes --connbytes $max_byte: --connbytes-dir both --connbytes-mode bytes -j MARK --set-mark $htb_egress_class
    
    iptables -t mangle -A OUTPUT -p tcp --sport $ip_port -j MARK --set-mark $htb_egress_class
    iptables -t mangle -A OUTPUT -j RETURN
    # ingress
    # HINT: set-mark not work for ifb device
    ## iptables -t mangle -A INPUT -p tcp --sport $ip_port -m connbytes --connbytes $max_byte: --connbytes-dir both --connbytes-mode bytes -j MARK --set-mark $htb_ingress_class
    ## iptables -t mangle -A PREROUTING -p tcp --sport $ip_port -j MARK --set-mark $htb_ingress_class
    ## iptables -t mangle -A PREROUTING -j RETURN

elif [ "$1" = "replace_ingress" ]; then

    if [ -z "$2" ]
        then
            echo "\$2 bitrate missing e.g. 1024kbit"
            echo "exit script"
            exit
        else
            echo "limit set to $2" 
        fi
    # Redirec to ingress $dev to egress $tin1
    tc filter replace dev $dev parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $tin1
    
    # tc qdisc add
    echo "tc qdisc replace dev $tin1"
    
    # https://linux.die.net/man/8/tc-htb
    # default minor-id
    # Unclassified traffic gets sent to the class with this minor-id.
    
    ## todo not need tc qdisc replace dev $tin1 root handle 2: htb default 10
    tc class replace dev $tin1 parent 2: classid 2:1 htb rate $2
    tc class replace dev $tin1 parent 2:1 classid 2:10 htb rate $2
   ## echo "tc class add dev $dev"
   ## tc class replace dev $dev parent 1: classid 1:$htb_egress_class htb rate $rate_egress_limit # ceil $rate_ceil
   ## tc filter replace dev $dev parent 1: prio 0 protocol ip handle $htb_egress_class fw flowid 1:$htb_egress_class

elif [ "$1" = "replace_egress" ]; then

    if [ -z "$2" ]
        then
            echo "\$2 bitrate missing e.g. 1024kbit"
            echo "exit script"
            exit
        else
            echo "limit set to $2" 
        fi
    # Redirec to ingress $dev to egress $tin1
    tc filter replace dev $dev parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $tin1
    
    # tc qdisc add
    ## echo "tc qdisc replace dev $tin1"
    
    # https://linux.die.net/man/8/tc-htb
    # default minor-id
    # Unclassified traffic gets sent to the class with this minor-id.
    
    ## todo not need tc qdisc replace dev $tin1 root handle 2: htb default 10
    ## tc class replace dev $tin1 parent 2: classid 2:1 htb rate $2
    ## tc class replace dev $tin1 parent 2:1 classid 2:10 htb rate $2
    echo "tc class replace dev $dev"
    tc class replace dev $dev parent 1: classid 1:$htb_egress_class htb rate $2 # ceil $rate_ceil
    tc filter replace dev $dev parent 1: prio 0 protocol ip handle $htb_egress_class fw flowid 1:$htb_egress_class
    


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
	echo "enable" 
	echo "replace_ingress" 
	echo "replace_egress" 
	echo "disable" 
	echo "show"
	echo "showtree" 
	echo "reset" 

fi
