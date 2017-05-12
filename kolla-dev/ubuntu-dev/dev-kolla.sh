#!/bin/bash

# host setup

function set_up_networking() {
	tee /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ens33
iface ens33 inet static
    address 192.168.10.11
    netmask 255.255.0.0
    gateway 192.168.0.1
    dns-nameservers 8.8.8.8


auto ens34
iface ens34 inet manual
up ip link set ens34 up
up ip link set ens34 promisc on
down ip link set ens34 promisc off
down ip link set ens34 down

auto ens35
iface ens35 inet manual
up ip link set ens35 up
up ip link set ens35 promisc on
down ip link set ens35 promisc off
down ip link set ens35 down
EOF

	for iface in ens33 ens34 ens35
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

set_up_networking
install_packages


mkdir -p /etc/systemd/system/docker.service.d
tee /etc/systemd/system/docker.service.d/kolla.conf <<-'EOF'
[Service]
MountFlags=shared
EOF

systemctl daemon-reload
systemctl restart docker


#./dev-kolla2.sh
