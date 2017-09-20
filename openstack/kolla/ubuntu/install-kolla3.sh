#!/bin/bash
set -e

# Post deploy stuff

function configure_ovs() {
	docker exec -u root neutron_server pip install --upgrade pip
	#docker exec --privileged neutron_server pip install wheel
	docker exec -u root neutron_server pip install "networking-hyperv>=5.0.0,<6.0.0"	
	docker restart neutron_server

	docker exec -u root openvswitch_vswitchd ovs-vsctl add-br br-data
	docker exec -u root openvswitch_vswitchd ovs-vsctl add-port br-data eth2
	docker exec -u root openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
	docker exec -u root openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
	docker exec -u root openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
	docker exec -u root openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
	docker exec -u root openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
	docker exec -u root openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data

	docker restart neutron_server neutron_openvswitch_agent neutron_dhcp_agent openvswitch_vswitchd openvswitch_db
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
    PUBLIC_NET="public_net"
    PUBLIC_SUBNET="public_subnet"
    PRIVATE_NET="private_net"
    PRIVATE_SUBNET="private_subnet"
    PRIVATE_NET_VLAN="private_net_vlan"
    PRIVATE_SUBNET_VLAN="private_subnet_vlan"
    PUBLIC_NET_START_IP="192.168.100.150"
    PUBLIC_NET_END_IP="192.168.100.170"
    PUBLIC_NET_GATEWAY="192.168.100.1"
    PUBLIC_NETWORK="192.168.100.0/24"
	
    # create the ext net&subnet
    neutron net-create $PUBLIC_NET  \
    --router:external --provider:physical_network physnet1 --provider:network_type flat

    neutron subnet-create $PUBLIC_NET \
    --name $PUBLIC_SUBNET --allocation-pool start=$PUBLIC_NET_START_IP,end=$PUBLIC_NET_END_IP \
    --disable-dhcp --gateway $PUBLIC_NET_GATEWAY $PUBLIC_NETWORK
    
    # create the private flat net&subnet 
    neutron net-create $PRIVATE_NET \
    --provider:physical_network physnet2 --provider:network_type flat
    
    neutron subnet-create $PRIVATE_NET 10.10.10.0/24 --name $PRIVATE_SUBNET \
    --allocation-pool start=10.10.10.50,end=10.10.10.200  --gateway 10.10.10.1

    # create the private vlan net&subnet
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
	wget http://balutoiu.com/ionut/images/cirros-gen2.vhdx -O /tmp/cirros-gen2.vhdx
	openstack image create --property hw_machine_type=hyperv-gen2 \
                       --property hypervisor_type=hyperv \
                       --disk-format vhd --container-format bare --file /tmp/cirros-gen2.vhdx --public cirros-vhdx-gen2
	rm /tmp/cirros-gen2.vhdx
}

function configure_magnum() {
	apt install qemu-utils -y
	openstack keypair create --public-key ~/.ssh/id_rsa.pub kolla-controller
	nova flavor-create cloud1 auto 1024 10 1  --is-public True
	nova flavor-create cloud2 auto 2048 10 1  --is-public True

	wget https://download.fedoraproject.org/pub/alt/atomic/stable/Fedora-Atomic-26-20170920.0/CloudImages/x86_64/images/Fedora-Atomic-26-20170920.0.x86_64.raw.xz -O /tmp/fedora-atomic.raw.xz
	unxz /tmp/fedora-atomic.raw.xz
	qemu-img convert -f raw -O vpc /tmp/fedora-atomic.raw /tmp/fedora-atomic.vhd
	#qemu-img convert -f raw -O qcow2 /tmp/fedora-atomic.raw /tmp/fedota-atomic.qcow2
	
	openstack image create --public \
	--property os_distro='fedora-atomic' --disk-format vhd --container-format bare --file /tmp/fedora-atomic.vhd fedora-atomic
	#openstack image create --public --property os_distro='fedora-atomic' \
	#--disk-format qcow2 --container-format bare --file /tmp/fedora-atomic.vhd fedora-atomic	
	rm /tmp/fedora-atomic.raw	
	rm /tmp/fedora-atomic.vhd

	magnum cluster-template-create --name k8s-cluster-template --image fedora-atomic \
	--keypair kolla-controller --external-network public_net --dns-nameserver 8.8.8.8 --flavor cloud1 \
	--docker-volume-size 3 --network-driver flannel --coe kubernetes
	#magnum cluster-create --name k8s-cluster --cluster-template k8s-cluster-template  --master-count 1 --node-count 2
}

function config_flavors() {
	nova flavor-create m1.nano 11 96 1 1
	nova flavor-create m1.tiny 1 512 1 1
	nova flavor-create m1.small 2 2048 20 1
	nova flavor-create m1.medium 3 4096 40 2
	nova flavor-create m1.large 5 8192 80 4
	nova flavor-create m1.xlarge 6 16384 160 8
}

source /etc/kolla/admin-openrc.sh

configure_ovs
configure_neutron
#cirros_vhd
#configure_magnum
#configure_networks
#configure_router
#config_flavors
