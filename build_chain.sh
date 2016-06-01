#!/bin/bash
###
#
# Functions
#
###
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function FirstHop()
{
	echo "## Choosing Random Provider"
	VPN0_CONFIG=$(find providers/ ! -path "providers/" |sort -R |tail -1)
	
	echo "## Choosing Random Server"
	VPN0_VARS=$(tail -n +2 $VPN0_CONFIG | sort -R | head -n 1)
	VPN0_BASE=$(head $VPN0_CONFIG -n 1)
	IFS=',' read -a VPN0_ARRAY <<< "$VPN0_VARS"
	VPN0_IP=$(host ${VPN0_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	while ! valid_ip $VPN0_IP
	do
		#Error Getting IP... Choosing New Server
	    VPN0_VARS=$(tail -n +2 $VPN0_CONFIG | sort -R | head -n 1)
		IFS=',' read -a VPN0_ARRAY <<< "$VPN0_VARS"
	    VPN0_IP=$(host ${VPN0_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	done;
	echo $VPN0_IP > .vpn0.public
	
	echo "### Trying $VPN0_IP"
	
	echo "## Creating VPN Config File"
	cp $VPN0_BASE vpn0.ovpn
	sed -i '/remote/ d' vpn0.ovpn
	echo "remote $VPN0_IP ${VPN0_ARRAY[1]}" >> vpn0.ovpn
	echo "route-nopull" >> vpn0.ovpn
	
	echo "## Adding Route For VPN IP"
	#Check if the route exists; then delete it; then add it properly
	EXIST=`ip route show $VPN0_IP | wc -l`
	if [ $EXIST -eq 1 ]
	then
		sudo ip route del $VPN0_IP
	fi
	/sbin/ip route add $VPN0_IP via $ETH0_GATEW dev eth0
	
	echo "## Connecting to VPN"
	/usr/sbin/openvpn vpn0.ovpn >> logs/vpn0.log &
	echo $! > vpn0.pid
}

function SecondHop()
{
	echo "## Choosing Random Provider"
	VPN1_CONFIG=$(find providers/ ! -path "providers/" ! -path $VPN0_CONFIG |sort -R |tail -1)
	
	echo "## Choosing Random Server"
	VPN1_VARS=$(tail -n +2 $VPN1_CONFIG | sort -R | head -n 1)
	VPN1_BASE=$(head $VPN1_CONFIG -n 1)
	IFS=',' read -a VPN1_ARRAY <<< "$VPN1_VARS"
	VPN1_IP=$(host ${VPN1_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	while ! valid_ip $VPN1_IP
	do
		#Error Getting IP... Choosing New Server
	    VPN1_VARS=$(tail -n +2 $VPN1_CONFIG | sort -R | head -n 1)
		IFS=',' read -a VPN1_ARRAY <<< "$VPN1_VARS"
	    VPN1_IP=$(host ${VPN1_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	done;
	echo $VPN1_IP > .vpn1.public
	
	echo "### Trying $VPN1_IP"
	
	echo "## Creating VPN Config File"
	cp $VPN1_BASE vpn1.ovpn
	sed -i '/remote/ d' vpn1.ovpn
	echo "remote $VPN1_IP ${VPN1_ARRAY[1]}" >> vpn1.ovpn
	echo "route-nopull" >> vpn1.ovpn
	
	echo "## Adding Route For VPN IP"
	#Check if the route exists; then delete it; then add it properly
	EXIST=`ip route show $VPN1_IP | wc -l`
	if [ $EXIST -eq 1 ]
	then
		sudo ip route del $VPN1_IP
	fi
	/sbin/ip route add $VPN1_IP via $VPN0_LOCAL dev tun0
	
	echo "## Connecting to VPN"
	/usr/sbin/openvpn vpn1.ovpn >> logs/vpn1.log &
	echo $! > vpn1.pid
}
	
function ThirdHop()
{
	echo "## Choosing Random Provider"
	VPN2_CONFIG=$(find providers/ ! -path "providers/" ! -path $VPN0_CONFIG ! -path $VPN1_CONFIG |sort -R |tail -1)
	
	echo "## Choosing Random Server"
	VPN2_VARS=$(tail -n +2 $VPN2_CONFIG | sort -R | head -n 1)
	VPN2_BASE=$(head $VPN2_CONFIG -n 1)
	IFS=',' read -a VPN2_ARRAY <<< "$VPN2_VARS"
	VPN2_IP=$(host ${VPN2_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	while ! valid_ip $VPN1_IP
	do
		#Error Getting IP... Choosing New Server
	    VPN2_VARS=$(tail -n +2 $VPN2_CONFIG | sort -R | head -n 1)
		IFS=',' read -a VPN2_ARRAY <<< "$VPN2_VARS"
	    VPN2_IP=$(host ${VPN2_ARRAY[0]}|awk '{print $NF}'|head -n 1)
	done;
	echo $VPN2_IP > .vpn2.public
	
	echo "### Trying $VPN2_IP"
	
	echo "## Creating VPN Config File"
	cp $VPN2_BASE vpn2.ovpn
	sed -i '/remote/ d' vpn2.ovpn
	echo "remote $VPN2_IP ${VPN2_ARRAY[1]}" >> vpn2.ovpn
	echo "route-nopull" >> vpn2.ovpn
	
	echo "## Adding Route For VPN IP"
	#Check if the route exists; then delete it; then add it properly
	EXIST=`ip route show $VPN2_IP | wc -l`
	if [ $EXIST -eq 1 ]
	then
		sudo ip route del $VPN2_IP
	fi
	/sbin/ip route add $VPN2_IP via $VPN1_LOCAL dev tun1
	
	echo "## Connecting to VPN"
	/usr/sbin/openvpn vpn2.ovpn >> logs/vpn2.log &
	echo $! > vpn2.pid
}

###
#
# Change To Chain Directory
# this is for when it is run as a cron
#
###
cd /etc/openvpn/chain

###
#
# Kill This Script if it is already running somewhere
# create a pid so this script can be killed if run again
#
###
kill -9 `cat .scriptPID`
echo $$ > .scriptPID

###
#
# Clear Internet Routing Rules
#
###
echo "# Deleting Any Internet Routes"
/sbin/ip route del 0.0.0.0/1
/sbin/ip route del 128.0.0.0/1

###
#
# Get Server Local INFO
#
###
echo "# Getting Local Server Info"
ETH0_MAC=$(cat /sys/class/net/eth0/address) ||
    die "Unable to determine MAC address on eth0."
ETH0_LOCAL=$(ip -o -4 addr show dev eth0 | awk -F '[ /]+' '/global/ {print $4}')
while ! valid_ip $ETH0_LOCAL
do
	ETH0_LOCAL=$(ip -o -4 addr show dev eth0 | awk -F '[ /]+' '/global/ {print $4}')
	echo "## Waiting on ETH0 Local IP"
	sleep 1
done
ETH0_GATEW=$(/sbin/route -n | grep 'UG[ \t]' | awk '{print $2}')
while ! valid_ip $ETH0_GATEW
do
	ETH0_GATEW=$(/sbin/route -n | grep 'UG[ \t]' | awk '{print $2}')
	echo "## Waiting on ETH0 GATEWAY"
	sleep 1
done
echo "### Local IP: $ETH0_LOCAL"
echo "### Local GW: $ETH0_GATEW"

###
#
# Add routes some static routes
#
###
echo "# Adding Name Server Routes Though Local Server"
/sbin/ip route add 8.8.8.8 via $ETH0_GATEW dev eth0
/sbin/ip route add 8.8.4.4 via $ETH0_GATEW dev eth0
echo "# Adding AWS JSON Backend route"
/sbin/ip route add 169.254.169.254 via $ETH0_GATEW dev eth0
echo "# Adding AWS VPC route"
VPC_CIDR_URI="http://169.254.169.254/latest/meta-data/network/interfaces/macs/${ETH0_MAC}/vpc-ipv4-cidr-block"
VPC_CIDR_RANGE=$(curl --retry 3 --silent --fail ${VPC_CIDR_URI})
echo "## AWS VPC Network: $VPC_CIDR_RANGE"
/sbin/ip route add $VPC_CIDR_RANGE via $ETH0_GATEW dev eth0

###
#
# Security...
# Route all internet traffic to local host
#
###
echo "# Temp Internet Access Kill"
/sbin/ip route add 0.0.0.0/1 via 127.0.0.1 dev lo
/sbin/ip route add 128.0.0.0/1 via 127.0.0.1 dev lo

###
#
# Kill VPN Connections
#
###
echo "# Killing VPN Connections"
kill -9 `cat vpn2.pid`
kill -9 `cat vpn1.pid`
kill -9 `cat vpn0.pid`

sleep 5
###
#
# Ensure Old Routes Get clean
#
###
echo "# Ensuring that all old routes have been removed"

/sbin/ip route del `cat .vpn1.public`
/sbin/ip route del `cat .vpn2.public`

###
#
# Remove VPN Log Info
#
###
echo "# Remove Old Log Files"
rm logs/vpn0.log
rm .vpn0.public
rm vpn0.ovpn
rm logs/vpn1.log
rm logs/vpn2.log
rm .vpn1.public
rm .vpn2.public
rm vpn1.ovpn
rm vpn2.ovpn

###
#
# First Hop
#
###
FirstHop
VPN0_LOCAL=$(ip -o -4 addr show dev tun0 | awk -F '[ /]+' '/global/ {print $4}')
COUNT=0
while ! valid_ip $VPN0_LOCAL
do
	VPN0_LOCAL=$(ip -o -4 addr show dev tun0 | awk -F '[ /]+' '/global/ {print $4}')
	sleep $((COUNT++))
	if [ $COUNT -gt 5 ]
	then
		echo "ERROR CONNECTING TO VPN RESETTING"
		/sbin/ip route del `cat .vpn0.public`
		kill -9 `cat vpn0.pid`  via $LOCAL_GATEW dev eth0
		FirstHop
		COUNT=0
	fi
done
echo "### Public IP: $VPN0_IP"
echo "### Local IP: $VPN0_LOCAL"
###
#
# Route Internet Traffic Out The 2nd VPN
#
###
/sbin/ip route del 0.0.0.0/1
/sbin/ip route add 0.0.0.0/1 via $VPN0_LOCAL dev tun0
/sbin/ip route del 128.0.0.0/1
/sbin/ip route add 128.0.0.0/1 via $VPN0_LOCAL dev tun0

###
#
# Second Hop
#
###
SecondHop
VPN1_LOCAL=$(ip -o -4 addr show dev tun1 | awk -F '[ /]+' '/global/ {print $4}')
COUNT=0
while ! valid_ip $VPN1_LOCAL
do
	VPN1_LOCAL=$(ip -o -4 addr show dev tun1 | awk -F '[ /]+' '/global/ {print $4}')
	sleep $((COUNT++))
	if [ $COUNT -gt 5 ]
	then
		echo "ERROR CONNECTING TO VPN RESETTING"
		/sbin/ip route del `cat .vpn1.public`  via $VPN0_LOCAL dev tun0
		kill -9 `cat vpn1.pid`
		SecondHop
		COUNT=0
	fi
done
echo "### Public IP: $VPN1_IP"
echo "### Local IP: $VPN1_LOCAL"
###
#
# Route Internet Traffic Out The 2nd VPN
#
###
/sbin/ip route del 0.0.0.0/1
/sbin/ip route add 0.0.0.0/1 via $VPN1_LOCAL dev tun1
/sbin/ip route del 128.0.0.0/1
/sbin/ip route add 128.0.0.0/1 via $VPN1_LOCAL dev tun1

###
#
# Third Hop
#
###
ThirdHop
VPN2_LOCAL=$(ip -o -4 addr show dev tun2 | awk -F '[ /]+' '/global/ {print $4}')
COUNT=0
while ! valid_ip $VPN2_LOCAL
do
	VPN2_LOCAL=$(ip -o -4 addr show dev tun2 | awk -F '[ /]+' '/global/ {print $4}')
	sleep $((COUNT++))
	if [ $COUNT -gt 5 ]
	then
		echo "ERROR CONNECTING TO VPN RESETTING"
		/sbin/ip route del `cat .vpn2.public`  via $VPN1_LOCAL dev tun1
		kill -9 `cat vpn2.pid`
		SecondHop
		COUNT=0
	fi
done
echo "### Public IP: $VPN2_IP"
echo "### Local IP: $VPN2_LOCAL"


###
#
# Route Internet Traffic Out The 3rd VPN
#
###
/sbin/ip route del 0.0.0.0/1
/sbin/ip route add 0.0.0.0/1 via $VPN2_LOCAL dev tun2
/sbin/ip route del 128.0.0.0/1
/sbin/ip route add 128.0.0.0/1 via $VPN2_LOCAL dev tun2

echo "Finished Setting Up Multi-Hop VPN"
echo "Final IP: $VPN2_IP"
