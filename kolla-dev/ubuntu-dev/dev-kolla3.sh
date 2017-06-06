#!/bin/bash
set -e

# Post deploy stuff

function configure_ovs() {
	docker exec --privileged neutron_server pip install --upgrade pip
	docker exec --privileged neutron_server pip install wheel
	docker exec --privileged neutron_server pip install "networking-hyperv>=3.0.0,<4.0.0"	
	docker restart neutron_server

	docker exec --privileged openvswitch_vswitchd ovs-vsctl add-br br-data
	docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data eth2
	docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
	docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
	docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
	docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
	docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
	docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data
}

function configure_neutron() { 
	for conf_file in /etc/kolla/neutron-server/ml2_conf.ini /etc/kolla/neutron-openvswitch-agent/ml2_conf.ini
	do
        	sed -i '/bridge_mappings/c\bridge_mappings = physnet1:br-ex,physnet2:br-data' $conf_file
        	sed -i '/flat_networks/c\flat_networks = physnet1,physnet2' $conf_file
        	sed -i '/network_vlan_ranges/c\network_vlan_ranges = physnet2:500:2000' $conf_file
	done	

	docker restart neutron_server neutron_openvswitch_agent
}

function configure_networks() {
    PUBLIC_NET=public_net
    PUBLIC_SUBNET=public_subnet
    PRIVATE_NET=private_net
    PRIVATE_SUBNET=private_subnet
    PRIVATE_NET_VLAN=private_net_vlan
    PRIVATE_SUBNET_VLAN=private_subnet_vlan
	
    neutron net-create $PUBLIC_NET  \
    --router:external --provider:physical_network physnet1 --provider:network_type flat

    neutron subnet-create $PUBLIC_NET \
    --name $PUBLIC_SUBNET --allocation-pool start=192.168.100.100,end=192.168.100.150 \
    --disable-dhcp --gateway 192.168.100.1 192.168.100.0/24

    neutron net-create $PRIVATE_NET \
    --provider:physical_network physnet2 --provider:network_type flat
    
    neutron subnet-create $PRIVATE_NET 10.10.10.0/24 --name $PRIVATE_SUBNET \
    --allocation-pool start=10.10.10.50,end=10.10.10.200  --gateway 10.10.10.1


    neutron net-create $PRIVATE_NET_VLAN --provider:segmentation_id 500 \
    --provider:physical_network physnet2 --provider:network_type vlan

    neutron subnet-create $PRIVATE_NET_VLAN 10.10.20.0/24 --name $PRIVATE_SUBNET_VLAN \
    --allocation-pool start=10.10.20.50,end=10.10.20.200  --gateway 10.10.20.1

}

function configure_router() {
    PUBLIC_ROUTER=router1

    neutron router-create $PUBLIC_ROUTER
    neutron router-interface-add $PUBLIC_ROUTER $PRIVATE_SUBNET
    neutron router-interface-add $PUBLIC_ROUTER $PRIVATE_SUBNET_VLAN
    neutron router-gateway-set $PUBLIC_ROUTER $PUBLIC_NET
}

function cirros_vhd() {
	wget https://cloudbase.it/downloads/cirros-0.3.4-x86_64.vhdx.gz
	gunzip cirros-0.3.4-x86_64.vhdx.gz
	openstack image create --public --property hypervisor_type=hyperv \
	--disk-format vhd --container-format bare --file cirros-0.3.4-x86_64.vhdx cirros-gen1-vhdx
	rm cirros-0.3.4-x86_64.vhdx
}

source /etc/kolla/admin-openrc.sh

configure_ovs
configure_neutron

cirros_vhd

configure_networks
configure_router

# Create sample flavors
nova flavor-create m1.nano 11 96 1 1
nova flavor-create m1.tiny 1 512 1 1
nova flavor-create m1.small 2 2048 20 1
nova flavor-create m1.medium 3 4096 40 2
nova flavor-create m1.large 5 8192 80 4
nova flavor-create m1.xlarge 6 16384 160 8

docker restart neutron_server neutron_openvswitch_agent neutron_dhcp_agent openvswitch_vswitchd openvswitch_db
