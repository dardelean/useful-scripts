#!/bin/bash

# Post deploy stuff

function configure_ovs() {
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-br br-data
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data ens35
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
	sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data

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
ovsdb_connection = tcp:192.168.10.11:6640
local_ip = 192.168.10.11
EOF
	done

	docker restart neutron_server neutron_openvswitch_agent
}

function configure_networks() {
    PUBLIC_NET=public_net
    PUBLIC_SUBNET=public_subnet

    neutron net-create $PUBLIC_NET \
    --router:external --provider:physical_network physnet1 --provider:network_type flat

    neutron subnet-create $PUBLIC_NET \
    --name $PUBLIC_SUBNET --allocation-pool start=192.168.10.100,end=192.168.10.150 \
    --disable-dhcp --gateway 192.168.0.1 192.168.0.0/16

    neutron net-create private-net --provider:physical_network physnet2 --provider:network_type flat
    neutron subnet-create private-net 10.10.10.0/24 --name private-subnet --allocation-pool start=10.10.10.50,end=10.10.10.200  --gateway 10.10.10.1

}

function configure_router() {
    PUBLIC_ROUTER=router1

    neutron router-create $PUBLIC_ROUTER
    neutron router-interface-add $PUBLIC_ROUTER $PRIVATE_SUBNET
    neutron router-gateway-set $PUBLIC_ROUTER $PUBLIC_NET
}

function cirros_vhd() {
	wget https://cloudbase.it/downloads/cirros-0.3.4-x86_64.vhdx.gz
	gunzip cirros-0.3.4-x86_64.vhdx.gz
	openstack image create --public --property hypervisor_type=hyperv \
	--disk-format vhd --container-format bare --file cirros-0.3.4-x86_64.vhdx cirros-gen1-vhdx
	rm cirros-0.3.4-x86_64.vhdx
}

#configure_ovs

#cirros_vhd

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
