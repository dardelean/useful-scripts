#!/bin/bash

sudo tee /etc/network/interfaces <<EOF
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
    sudo ifdown $iface || true
    sudo ifup $iface
done


# Get Docker and Ansible
sudo apt-add-repository ppa:ansible/ansible -y
sudo apt-get update
sudo apt-get install -y docker.io ansible

# NTP client
sudo apt-get install -y ntp

# Remove lxd or lxc so it won't bother Docker
sudo apt-get remove -y lxd lxc

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/kolla.conf <<-'EOF'
[Service]
MountFlags=shared
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# kolla-ansible prechecks fails if the hostname in the hosts file is set to 127.0.1.1
MGMT_IP=$(sudo ip addr show ens33 | sed -n 's/^\s*inet \([0-9.]*\).*$/\1/p')
sudo bash -c "echo $MGMT_IP $(hostname) >> /etc/hosts"

#./dev-kolla2.sh
