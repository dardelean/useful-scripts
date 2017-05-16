#!/bin/bash

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
    --name $PUBLIC_SUBNET --allocation-pool start=192.168.10.100,end=192.168.10.150 \
    --disable-dhcp --gateway 192.168.0.1 192.168.0.0/16

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

configure_networks
configure_router
