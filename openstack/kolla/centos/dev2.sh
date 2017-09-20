#!/bin/bash

source /etc/kolla/admin-openrc.sh

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
