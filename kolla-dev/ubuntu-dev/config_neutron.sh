#!/bin/bash

function configure_ovs() {
#        docker exec --privileged neutron_server pip install --upgrade pip
#        docker exec --privileged neutron_server pip install wheel
#        docker exec --privileged neutron_server pip install "networking-hyperv>=3.0.0,<4.0.0"
#        docker restart neutron_server

        docker exec --privileged openvswitch_vswitchd ovs-vsctl add-br br-data
        docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data eth2
        docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
        docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
        docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
        docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
        docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
        docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data

	docker restart neutron_server neutron_openvswitch_agent
}

function configure_neutron() {
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
flat_networks = physnet1,physnet2

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

function configure_neutronnn() {
        for conf_file in /etc/kolla/neutron-server/ml2_conf.ini /etc/kolla/neutron-openvswitch-agent/ml2_conf.ini
        do
		sed -i '/bridge_mappings/c\bridge_mappings = physnet1:br-ex,physnet2:br-data' $conf_file
		sed -i '/flat_networks/c\flat_networks = physnet1,physnet2' $conf_file
		sed -i '/network_vlan_ranges/c\network_vlan_ranges = physnet2:500:2000' $conf_file
	done

        docker restart neutron_server neutron_openvswitch_agent
}


configure_ovs
configure_neutronnn
#configure_neutron
