#!/bin/bash

config_network_adapter () {
    local IFACE=$1
    local IPADDR=$2
    local NETMASK=$3
    local GATEWAY=$4

    cat << EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE
DEVICE="$IFACE"
NM_CONTROLLED="no"
BOOTPROTO="none"
MTU="1500"
ONBOOT="yes"
IPADDR="$IPADDR"
NETMASK="$NETMASK"
GATEWAY="$GATEWAY"
NAMESERVER=8.8.8.8
EOF
}

config_ovs_network_adapter () {
    local ADAPTER=$1

    cat << EOF > /etc/sysconfig/network-scripts/ifcfg-$ADAPTER
DEVICE="$ADAPTER"
NM_CONTROLLED="no"
BOOTPROTO="none"
MTU="1500"
ONBOOT="yes"
EOF
}
config_network_adapter eth0 192.168.10.16 255.255.0.0 192.168.0.1
config_ovs_network_adapter eth1
config_ovs_network_adapter eth2

for iface in eth0 eth1 eth2
do
    sudo ifdown $iface || true
    sudo ifup $iface
done

yum install -y epel-release
yum install -y python-pip python-docker-py
pip install -U pip
yum install -y python-devel libffi-devel gcc openssl-devel

# Install Docker
curl -sSL https://get.docker.io | bash

# NTP client
yum install -y ntp
systemctl enable ntpd.service
systemctl start ntpd.service

mkdir -p /etc/systemd/system/docker.service.d
tee /etc/systemd/system/docker.service.d/kolla.conf <<-'EOF'
[Service]
MountFlags=shared
EOF

systemctl daemon-reload
systemctl restart docker

# kolla-ansible prechecks fails if the hostname in the hosts file is set to 127.0.1.1
MGMT_IP=$(sudo ip addr show eth0 | sed -n 's/^\s*inet \([0-9.]*\).*$/\1/p')
bash -c "echo $MGMT_IP $(hostname) >> /etc/hosts"
