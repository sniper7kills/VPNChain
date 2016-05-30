# VPNChain

## About
Multi-Hop VPN Setup Script for AWS.

### Providers included
Private Internet Access

## Install

    sudo su
    apt-get install openvpn git
    cd /etc/openvpn
    git clone ... VPNChain
    crontab -l > newCronTab
    echo "@reboot /etc/openvpn/VPNChain/build_chain.sh >/etc/openvpn/VPNChain/logs/chain.log 2>&1" >> newCronTab
    crontab newCronTab
    rm newCronTab
    echo "PIA_USERNAME" > base/pia/auth.txt
    echo "PIA_PASSWORD" >> base/pia/auth.txt
    shutdown -r now

## Adding Providers
1. Create new `providers/PROVIDER` file
.1.The first line should be the relitive location of your .ovpn file (base/PROVIDER/PROVIDER.ovpn)
.1.The rest of the file should contain `SERVER,PORT` infromation for that providers servers (at least the ones you want to use)
1. Copy `PROVIDER.ovpn` to `base/PROVIDER/PROVIDER.ovpn`
1. Copy any needed files to `base/PROVIDER` - I.E. (ca.crt, clr.pem, auth.txt)
1. Edit `PROVIDER.ovpn` to put any file paths to `base/PROVIDER/FILE`
