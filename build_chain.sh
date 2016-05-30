#!/bin/bash
###
#
# providers/example
#   Line 1.    .openvpn base file
#   Line ...   IP,PORT
#
###

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

###
#
# Change To Chain Directory
# this is for when it is run as a cron
#
###
cd /etc/openvpn/chain

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

###
#
# Ensure Old Routes Get clean
#
###
echo "# Ensuring that all old routes have been removed"
/sbin/ip route del `cat .vpn0.public`
/sbin/ip route del `cat .vpn1.public`
/sbin/ip route del `cat .vpn2.public`

###
#
# Remove VPN Log Info
#
###
echo "# Remove Old Log Files"
rm logs/vpn0.log
rm logs/vpn1.log
rm logs/vpn2.log

###
#
# VPN1
#
###
echo "# Starting VPN1"
echo "## Choosing Random Provider"
VPN0_CONFIG=$(find providers/ ! -path "providers/" |sort -R |tail -1)
echo "## Choosing Random Server"
VPN0_VARS=$(tail -n +2 $VPN0_CONFIG | sort -R | head -n 1)
VPN0_BASE=$(head $VPN0_CONFIG -n 1)
IFS=',' read -a VPN0_ARRAY <<< "$VPN0_VARS"
echo "## Getting IP if given DNS name"
if valid_ip ${VPN0_ARRAY[0]};
then
    VPN0_IP=${VPN0_ARRAY[0]};
else
    VPN0_IP=$(host ${VPN0_ARRAY[0]}|awk '{print $NF}'|head -n 1)
fi;
echo $VPN0_IP > .vpn0.public
echo "### VPN1 IP: $VPN0_IP"
echo "## Creating VPN Config File"
cp $VPN0_BASE vpn0.ovpn
sed -i '/remote/ d' vpn0.ovpn
echo "remote $VPN0_IP ${VPN0_ARRAY[1]}" >> vpn0.ovpn
echo "route-nopull" >> vpn0.ovpn
echo "## Adding Route For VPN IP"
/sbin/ip route add $VPN0_IP via $ETH0_GATEW dev eth0
echo "## Connecting to VPN"
/usr/sbin/openvpn vpn0.ovpn >> logs/vpn0.log &
echo $! > vpn0.pid
echo "## Getting VPN Local IP"
VPN0_LOCAL=$(ip -o -4 addr show dev tun0 | awk -F '[ /]+' '/global/ {print $4}')
while ! valid_ip $VPN0_LOCAL
do
	VPN0_LOCAL=$(ip -o -4 addr show dev tun0 | awk -F '[ /]+' '/global/ {print $4}')
	echo "### Waiting on tun0 to come up"
	sleep 1
done
echo "### VPN1 Local: $VPN0_LOCAL"

###
#
# VPN 2
#
###
echo "# Starting VPN2"
echo "## Choosing Random Provider"
VPN1_CONFIG=$(find providers/ ! -path "providers/" ! -path $VPN0_CONFIG |sort -R |tail -1)
echo "## Choosing Random Server"
VPN1_VARS=$(tail -n +2 $VPN1_CONFIG | sort -R | head -n 1)
VPN1_BASE=$(head $VPN1_CONFIG -n 1)
IFS=',' read -a VPN1_ARRAY <<< "$VPN1_VARS"
echo "## Getting IP if given DNS name"
if valid_ip ${VPN1_ARRAY[0]};
then
    VPN1_IP=${VPN1_ARRAY[0]};
else
    VPN1_IP=$(host ${VPN1_ARRAY[0]}|awk '{print $NF}'|head -n 1)
fi;
echo $VPN1_IP > .vpn1.public
echo "### VPN2 IP: $VPN1_IP"
echo "## Creating VPN Config File"
cp $VPN1_BASE vpn1.ovpn
sed -i '/remote/ d' vpn1.ovpn
echo "remote $VPN1_IP ${VPN1_ARRAY[1]}" >> vpn1.ovpn
echo "route-nopull" >> vpn1.ovpn
echo "## Adding Route For VPN IP"
/sbin/ip route add $VPN1_IP via $VPN0_LOCAL dev tun0
echo "## Connecting to VPN"
/usr/sbin/openvpn vpn1.ovpn >> logs/vpn1.log &
echo $! > vpn1.pid
echo "## Getting VPN Local IP"
VPN1_LOCAL=$(ip -o -4 addr show dev tun1 | awk -F '[ /]+' '/global/ {print $4}')
while ! valid_ip $VPN1_LOCAL
do
	VPN1_LOCAL=$(ip -o -4 addr show dev tun1 | awk -F '[ /]+' '/global/ {print $4}')
	echo "### Waiting on tun1 to come up"
	sleep 1
done
echo "### VPN2 Local: $VPN1_LOCAL"

###
#
# VPN 3
#
###
echo "# Starting VPN3"
echo "## Choosing Random Provider"
VPN2_CONFIG=$(find providers/ ! -path "providers/" ! -path $VPN0_CONFIG ! -path $VPN1_CONFIG |sort -R |tail -1)
echo "## Choosing Random Server"
VPN2_VARS=$(tail -n +2 $VPN2_CONFIG | sort -R | head -n 1)
VPN2_BASE=$(head $VPN2_CONFIG -n 1)
IFS=',' read -a VPN2_ARRAY <<< "$VPN2_VARS"
echo "## Getting IP if given DNS name"
if valid_ip ${VPN2_ARRAY[0]};
then
    VPN2_IP=${VPN2_ARRAY[0]};
else
    VPN2_IP=$(host ${VPN2_ARRAY[0]}|awk '{print $NF}'|head -n 1)
fi;
echo $VPN2_IP > .vpn2.public
echo "### VPN3 IP: $VPN2_IP"
echo "## Creating VPN Config File"
cp $VPN2_BASE vpn2.ovpn
sed -i '/remote/ d' vpn2.ovpn
echo "remote $VPN2_IP ${VPN2_ARRAY[1]}" >> vpn2.ovpn
echo "route-nopull" >> vpn2.ovpn
echo "## Adding Route For VPN IP"
/sbin/ip route add $VPN2_IP via $VPN1_LOCAL dev tun1
echo "## Connecting to VPN"
/usr/sbin/openvpn vpn2.ovpn >> logs/vpn2.log &
echo $! > vpn2.pid
echo "## Getting VPN Local IP"
VPN2_LOCAL=$(ip -o -4 addr show dev tun2 | awk -F '[ /]+' '/global/ {print $4}')
while ! valid_ip $VPN2_LOCAL
do
	VPN2_LOCAL=$(ip -o -4 addr show dev tun2 | awk -F '[ /]+' '/global/ {print $4}')
	echo "### Waiting on tun2 to come up"
	sleep 1
done
echo "### VPN3 Local: $VPN2_LOCAL"

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
