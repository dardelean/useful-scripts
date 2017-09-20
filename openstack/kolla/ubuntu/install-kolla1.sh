#!/bin/bash

set -e

HOST_IP=192.168.100.100
HOST_GATEWAY=192.168.100.1
HOST_NETMASK=255.255.255.0

# host setup
function set_up_networking() {
	tee /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet static
    address $HOST_IP
    netmask $HOST_NETMASK
    gateway $HOST_NETMASK
    dns-nameservers 8.8.8.8


auto eth1
iface eth1 inet manual
up ip link set eth1 up
up ip link set eth1 promisc on
down ip link set eth1 promisc off
down ip link set eth1 down

auto eth2
iface eth2 inet manual
up ip link set eth2 up
up ip link set eth2 promisc on
down ip link set eth2 promisc off
down ip link set eth2 down
EOF

	for iface in eth0 eth1 eth2
	do
		ifdown $iface || true
		ifup $iface
	done
}

function install_packages () {
	# Get Docker and Ansible
	apt-add-repository ppa:ansible/ansible -y
	apt-get update
	apt-get install -y docker.io ansible

	# NTP client
	apt-get install -y ntp

	# Remove lxd or lxc so it won't bother Docker
	apt-get remove -y lxd lxc

	apt-get install -y python-pip
	apt-get install -y python-openstackclient
	pip install python-cinderclient python-magnumclient
	pip install "pywinrm>=0.2.2"
}

#set_up_networking
install_packages


# config docker
mkdir -p /etc/systemd/system/docker.service.d
tee /etc/systemd/system/docker.service.d/kolla.conf <<-'EOF'
[Service]
MountFlags=shared
EOF

systemctl daemon-reload
systemctl restart docker


#./dev-kolla2.sh
