#!bin/bash

# create the private network
neutron net-create private-net  --provider:physical_network physnet2 --provider:network_type flat
neutron subnet-create private-net 10.10.10.0/24 --name private-subnet --allocation-pool start=10.10.10.50,end=10.10.10.100 --dns-nameserver 8.8.8.8 --gateway 10.10.10.1

# create the provider network
neutron net-create public-net --shared  --router:external --provider:physical_network physnet2 --provider:network_type flat
neutron subnet-create public-net --name public-subnet --allocation-pool start=192.168.0.150,end=192.168.0.180 --disable-dhcp --gateway 192.168.0.1 192.168.0.0/24

# create a router and hook it the the networks
neutron router-create router1

neutron router-interface-add router1 private-subnet
neutron router-gateway-set router1 public-net

