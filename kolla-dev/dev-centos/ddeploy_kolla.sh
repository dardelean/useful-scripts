#!/bin/bash
set -e

KOLLA_OPENSTACK_VERSION=4.0.0
KOLLA_INTERNAL_VIP_ADDRESS=192.168.10.17
DOCKER_NAMESPACE=dardelean


exec_with_retry () {
    local MAX_RETRIES=$1
    local INTERVAL=$2

    local COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        local EXIT=0
        eval '${@:3}' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}


# Networking configuration
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


# Install dependencies
yum install -y epel-release
yum update -y
yum install -y wget git python-pip python-docker-py python-devel libffi-devel gcc openssl-devel
pip install -U pip
pip install "pywinrm>=0.2.2"
pip install -U python-openstackclient python-neutronclient


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

# Set up cinder-volumes
mkdir -p /var/cinder
fallocate -l 20G /var/cinder/cinder-volumes.img
losetup /dev/loop2 /var/cinder/cinder-volumes.img

pvcreate /dev/loop2
vgcreate cinder-volumes /dev/loop2


# Install Kolla
cd /mnt/smb
pip install ./kolla
pip install ./kolla-ansible
cp -r kolla-ansible/etc/kolla /etc/


# Configure globals.yml for Kolla
sed -i '/#kolla_base_distro/i kolla_base_distro: "centos"' /etc/kolla/globals.yml
sed -i '/#docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sed -i '/#openstack_release/i openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sed -i '/#network_interface/i network_interface: "eth0"' /etc/kolla/globals.yml
sed -i '/#neutron_external_interface/i neutron_external_interface: "eth1"' /etc/kolla/globals.yml

# enable cinder
sed -i '/#enable_cinder/i enable_cinder: "yes"' /etc/kolla/globals.yml
sed -i '/#enable_cinder_backend_lvm/i enable_cinder_backend_lvm: "yes"' /etc/kolla/globals.yml
sed -i '/#cinder_volume_group/i cinder_volume_group: "cinder-volumes"' /etc/kolla/globals.yml

# hyperv setup
sed -i '/#enable_hyperv/i enable_hyperv: "yes"' /etc/kolla/globals.yml
sed -i '/#hyperv_username/i hyperv_username: "Administrator"' /etc/kolla/globals.yml
sed -i '/#hyperv_password/i hyperv_password: "Passw0rd"' /etc/kolla/globals.yml
sed -i '/#vswitch_name/i vswitch_name: "data-net"' /etc/kolla/globals.yml

systemctl restart docker

kolla-ansible pull
kolla-genpwd

kolla-ansible prechecks -i /usr/share/kolla-ansible/ansible/inventory/all-in-one

sed -i '18 i\[hyperv] \
192.168.0.120 \
\
[hyperv:vars] \
ansible_user=Administrator \
ansible_password=Passw0rd \
ansible_port=5986 \
ansible_connection=winrm \
ansible_winrm_server_cert_validation=ignore' /usr/share/kolla-ansible/ansible/inventory/all-in-one


exec_with_retry 5 0 kolla-ansible deploy -i /usr/share/kolla-ansible/ansible/inventory/all-in-one
exec_with_retry 5 0 kolla-ansible post-deploy -i /usr/share/kolla-ansible/ansible/inventory/all-in-one

# Remove unneeded Nova containers
#for name in nova_compute nova_ssh nova_libvirt
#do
#    for id in $(sudo docker ps -q -a -f name=$name)
#    do
#        sudo docker stop $id
#        sudo docker rmi -f $id
#    done
#done


for conf_file in /etc/kolla/neutron-server/ml2_conf.ini /etc/kolla/neutron-openvswitch-agent/ml2_conf.ini
do
	cat << EOF > $conf_file
[ml2]
type_drivers = flat,vlan
tenant_network_types = flat,vlan
mechanism_drivers = openvswitch,hyperv
extension_drivers = port_security

[ml2_type_vlan]
network_vlan_ranges = physnet2:500:2000

[ml2_type_flat]
flat_networks = physnet1, physnet2

[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[ovs]
bridge_mappings = physnet1:br-ex,physnet2:br-data
ovsdb_connection = tcp:192.168.10.16:6640
local_ip = 192.168.10.16
EOF
done

docker restart neutron_server neutron_openvswitch_agent

# Configure the OVS data bridge
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-br br-data
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data eth2
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data

source /etc/kolla/admin-openrc.sh

# Create Glance Cirros VHD image
wget https://cloudbase.it/downloads/cirros-0.3.4-x86_64.vhdx.gz
gunzip cirros-0.3.4-x86_64.vhdx.gz
openstack image create --public --property hypervisor_type=hyperv --disk-format vhd --container-format bare --file cirros-0.3.4-x86_64.vhdx cirros-gen1-vhdx
rm cirros-0.3.4-x86_64.vhdx


# Create neutron networks network
neutron net-create private-net --provider:physical_network physnet2 --provider:network_type flat
neutron subnet-create private-net 10.10.10.0/24 --name private-subnet --allocation-pool start=10.10.10.50,end=10.10.10.200  --gateway 10.10.10.1

neutron net-create public-net --shared  --router:external --provider:physical_network physnet1 --provider:network_type flat
neutron subnet-create public-net --name public-subnet --allocation-pool start=192.168.10.110,end=192.168.10.120 --disable-dhcp --gateway 192.168.0.1 192.168.0.0/16

neutron router-create router1
neutron router-interface-add router1 private-subnet
neutron router-gateway-set router1 public-net


# Create sample flavors
nova flavor-create m1.nano 11 96 1 1
nova flavor-create m1.tiny 1 512 1 1
nova flavor-create m1.small 2 2048 20 1
nova flavor-create m1.medium 3 4096 40 2
nova flavor-create m1.large 5 8192 80 4
nova flavor-create m1.xlarge 6 16384 160 8

docker restart neutron_server neutron_openvswitch_agent neutron_dhcp_agent openvswitch_vswitchd openvswitch_db
