#!/bin/bash



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

wget https://cloudbase.it/downloads/cirros-0.3.4-x86_64.vhdx.gz
gunzip cirros-0.3.4-x86_64.vhdx.gz
openstack image create --public --property hypervisor_type=hyperv --disk-format vhd --container-format bare --file cirros-0.3.4-x86_64.vhdx cirros-gen1-vhdx
rm cirros-0.3.4-x86_64.vhdx


# Create the private network
neutron net-create private-net --provider:segmentation_id 501 --provider:physical_network physnet2 --provider:network_type vlan
neutron subnet-create private-net 10.10.10.0/24 --name private-subnet --allocation-pool start=10.10.10.50,end=10.10.10.200  --gateway 10.10.10.1


# Create sample flavors
nova flavor-create m1.nano 11 96 1 1
nova flavor-create m1.tiny 1 512 1 1
nova flavor-create m1.small 2 2048 20 1
nova flavor-create m1.medium 3 4096 40 2
nova flavor-create m1.large 5 8192 80 4
nova flavor-create m1.xlarge 6 16384 160 8

docker restart neutron_server neutron_openvswitch_agent neutron_dhcp_agent openvswitch_vswitchd openvswitch_db
