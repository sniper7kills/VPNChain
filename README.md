# VPNChain

## About
Multi-Hop VPN Setup Script for AWS.

## Install

    sudo su
    apt-get install openvpn git
    cd /etc/openvpn
    git clone ... VPNChain
    crontab -l > newCronTab
    echo "@reboot /etc/openvpn/VPNChain/build_chain.sh >/etc/openvpn/VPNChain/logs/chain.log 2>&1" >> newCronTab
    crontab newCronTab
    rm newCronTab
    shutdown -r now
