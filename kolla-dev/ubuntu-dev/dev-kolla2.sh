#!/bin/bash

set -e

# Kolla setup

function enable_hyperv() {
	sed -i '/#enable_hyperv/i enable_hyperv: "yes"' /etc/kolla/globals.yml
	sed -i '/#hyperv_username/i hyperv_username: "'$HYPERV_USERNAME'"' /etc/kolla/globals.yml
	sed -i '/#hyperv_password/i hyperv_password: "'$HYPERV_PASSWORD'"' /etc/kolla/globals.yml
	sed -i '/#vswitch_name/i vswitch_name: "v-switch"' /etc/kolla/globals.yml
	sed -i '/#nova_msi_url/i nova_msi_url: "https://cloudbase.it/downloads/HyperVNovaCompute_Ocata_15_0_0.msi"' /etc/kolla/globals.yml
}

function add_hyperv() {
	if ! grep -q "hyperv" /usr/local/share/kolla-ansible/ansible/inventory/all-in-one;
	then
		sed -i '18 i\[hyperv] \
192.168.10.14 \
\
[hyperv:vars] \
ansible_user="'$HYPERV_USERNAME'" \
ansible_password="'$HYPERV_PASSWORD'" \
ansible_port=5986 \
ansible_connection=winrm \
ansible_winrm_server_cert_validation=ignore \
\' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
	fi

}

function set_up_cinder() {
	# Set up cinder-volumes
	if ! vgs cinder-volumes 2>/dev/null
	then
    		mkdir -p /var/cinder
    		fallocate -l 20G /var/cinder/cinder-volumes.img
    		losetup /dev/loop2 /var/cinder/cinder-volumes.img

    		pvcreate /dev/loop2
    		vgcreate cinder-volumes /dev/loop2

		# make this reboot persistent
    		echo "losetup /dev/loop2 /var/cinder/cinder-volumes.img" >> /etc/rc.d/rc.local
    		chmod +x /etc/rc.d/rc.local
	

		# needed for Ubuntu distro
		echo "configfs" >> /etc/modules
		update-initramfs -u
		systemctl stop open-iscsi; systemctl stop iscsid

		modprobe configfs
		systemctl start sys-kernel-config.mount
	fi
}

function enable_cinder() {
	sed -i '/#enable_cinder:/i enable_cinder: "yes"' /etc/kolla/globals.yml
	sed -i '/#enable_cinder_backend_lvm/i enable_cinder_backend_lvm: "yes"' /etc/kolla/globals.yml
	sed -i '/#cinder_volume_group/i cinder_volume_group: "cinder-volumes"' /etc/kolla/globals.yml
}

KOLLA_OPENSTACK_VERSION=4.0.0
KOLLA_INTERNAL_VIP_ADDRESS=192.168.10.13
DOCKER_NAMESPACE=dardelean
ADMIN_PASSWORD=admin
HYPERV_USERNAME=
HYPERV_PASSWORD=


# Install Kolla
cd /mnt/smb

pip install ./kolla
pip install ./kolla-ansible
cp -r kolla-ansible/etc/kolla /etc/

# Enable various stuff for Kolla
sed -i '/#kolla_base_distro/i kolla_base_distro: "ubuntu"' /etc/kolla/globals.yml
sed -i '/#docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sed -i '/#openstack_release/i openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sed -i '/#network_interface/i network_interface: "eth0"' /etc/kolla/globals.yml
sed -i '/#neutron_external_interface/i neutron_external_interface: "eth1"' /etc/kolla/globals.yml
#sed -i '/#enable_central_logging/i enable_central_logging: "yes"' /etc/kolla/globals.yml
#sed -i '/#enable_magnum/i enable_magnum: "yes"' /etc/kolla/globals.yml
#sed -i '/#enable_horizon_magnum/i enable_horizon_magnum: "{{ enable_magnum | bool }}"' /etc/kolla/globals.yml
sed -i '/keystone_admin_password/c\keystone_admin_password: "'$ADMIN_PASSWORD'"' /etc/kolla/passwords.yml

systemctl restart docker
systemctl enable docker

set_up_cinder
enable_cinder
enable_hyperv

#kolla-ansible bootstrap-servers
kolla-ansible pull
kolla-genpwd

#kolla-ansible prechecks -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

add_hyperv

kolla-ansible deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

kolla-ansible post-deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

#./dev-kolla3.sh
