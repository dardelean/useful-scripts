#!/bin/bash

set -e

# Kolla setup

function enable_hyperv() {
	sed -i '/enable_hyperv/c\enable_hyperv: "yes"' /etc/kolla/globals.yml
	sed -i '/hyperv_username/c\hyperv_username: "'$HYPERV_USERNAME'"' /etc/kolla/globals.yml
	sed -i '/hyperv_password/c\hyperv_password: "'$HYPERV_PASSWORD'"' /etc/kolla/globals.yml
	sed -i '/vswitch_name/c\vswitch_name: "v-switch"' /etc/kolla/globals.yml
	sed -i '/nova_msi_url/c\nova_msi_url: "https://cloudbase.it/downloads/HyperVNovaCompute_Ocata_15_0_0.msi"' /etc/kolla/globals.yml
}

function add_hyperv() {
	if ! grep -q "192.168.100.14" /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
	then
		sed -i '/hyperv]/a\
192.168.100.14' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
		#sed -i '/hyperv_host/d' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
		sed -i '/hyperv_host/d' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one 
 		sed -i '/ansible_user/c\ansible_user='$HYPERV_USERNAME'' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
                sed -i '/ansible_password/c\ansible_password='$HYPERV_PASSWORD'' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
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
    		echo "losetup /dev/loop2 /var/cinder/cinder-volumes.img" >> /etc/rc.local
    		chmod +x /etc/rc.local
	

		# needed for Ubuntu distro
		echo "configfs" >> /etc/modules
		update-initramfs -u
		systemctl stop open-iscsi; systemctl stop iscsid

		modprobe configfs
		systemctl start sys-kernel-config.mount
	fi
}

function enable_cinder() {
	sed -i '/enable_cinder:/c\enable_cinder: "yes"' /etc/kolla/globals.yml
	sed -i '/enable_cinder_backend_lvm/c\enable_cinder_backend_lvm: "yes"' /etc/kolla/globals.yml
	sed -i '/cinder_volume_group/c\cinder_volume_group: "cinder-volumes"' /etc/kolla/globals.yml
}

KOLLA_OPENSTACK_VERSION=4.0.0
KOLLA_INTERNAL_VIP_ADDRESS=192.168.100.13
DOCKER_NAMESPACE=dardelean
ADMIN_PASSWORD=admin
HYPERV_USERNAME=Administrator
HYPERV_PASSWORD=Passw0rd


# Install Kolla
cd /mnt/smb

pip install ./kolla
pip install ./kolla-ansible
cp -r kolla-ansible/etc/kolla /etc/

# Enable various stuff for Kolla
sed -i '/kolla_base_distro:/c\kolla_base_distro: "ubuntu"' /etc/kolla/globals.yml
sed -i '/kolla_install_type:/c\kolla_install_type: "source"' /etc/kolla/globals.yml
#sed -i '/docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sed -i '/openstack_release:/c\openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sed -i '/#network_interface:/c\network_interface: "eth0"' /etc/kolla/globals.yml
sed -i '/#neutron_external_interface:/c\neutron_external_interface: "eth1"' /etc/kolla/globals.yml
#sed -i '/#tunnel_interface:/c\tunnel_interface: "eth2"' /etc/kolla/globals.yml
sed -i '/#enable_tempest:/c\enable_tempest: "yes"' /etc/kolla/globals.yml
#sed -i '/enable_central_logging/c\ enable_central_logging: "yes"' /etc/kolla/globals.yml
sed -i '/#enable_magnum:/c\enable_magnum: "yes"' /etc/kolla/globals.yml
sed -i '/#enable_horizon_magnum:/c\enable_horizon_magnum: "{{ enable_magnum | bool }}"' /etc/kolla/globals.yml
sed -i '/keystone_admin_password/c\keystone_admin_password: "'$ADMIN_PASSWORD'"' /etc/kolla/passwords.yml

systemctl restart docker
systemctl enable docker

set_up_cinder
enable_cinder
enable_hyperv

#kolla-ansible bootstrap-servers
#kolla-ansible pull
kolla-genpwd

#kolla-ansible prechecks -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

add_hyperv

kolla-ansible deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

kolla-ansible post-deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

#./dev-kolla3.sh
