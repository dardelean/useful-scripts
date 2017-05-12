#!/bin/bash

function enable_hyperv() {
	sed -i '/#enable_hyperv/i enable_hyperv: "yes"' /etc/kolla/globals.yml
	sed -i '/#hyperv_username/i hyperv_username: "'$HYPERV_USERNAME'"' /etc/kolla/globals.yml
	sed -i '/#hyperv_password/i hyperv_password: "'$HYPERV_PASSWORD'"' /etc/kolla/globals.yml
	sed -i '/#vswitch_name/i vswitch_name: "v-magine-data"' /etc/kolla/globals.yml
	sed -i '/#nova_msi_url/i nova_msi_url: "https://cloudbase.it/downloads/HyperVNovaCompute_Ocata_15_0_0.msi"' /etc/kolla/globals.yml
}

function add_hyperv() {
	sed -i '18 i\[hyperv] \
192.168.0.120 \
\
[hyperv:vars] \
ansible_user=Administrator \
ansible_password=Passw0rd \
ansible_port=5986 \
ansible_connection=winrm \
ansible_winrm_server_cert_validation=ignore' /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
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
	fi

	# needed for Ubuntu distro
	echo "configfs" >> /etc/modules
	update-initramfs -u
	systemctl stop open-iscsi; systemctl stop iscsid

	modprobe configfs
	systemctl start sys-kernel-config.mount
}

KOLLA_OPENSTACK_VERSION=4.0.0
KOLLA_INTERNAL_VIP_ADDRESS=192.168.10.13
DOCKER_NAMESPACE=dardelean
ADMIN_PASSWORD=admin
HYPERV_USERNAME=Administrator
HYPERV_PASSWORD=Passw0rd

cd /mnt/smb

sudo apt-get install -y python-pip
sudo apt-get install -y python-openstackclient
sudo pip install ./kolla
sudo pip install ./kolla-ansible
sudo cp -r kolla-ansible/etc/kolla /etc/

sudo pip install "pywinrm>=0.2.2"

sudo sed -i '/#kolla_base_distro/i kolla_base_distro: "ubuntu"' /etc/kolla/globals.yml
#sudo sed -i '/#docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sudo sed -i '/#openstack_release/i openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sudo sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sudo sed -i '/#network_interface/i network_interface: "ens33"' /etc/kolla/globals.yml
sudo sed -i '/#neutron_external_interface/i neutron_external_interface: "ens34"' /etc/kolla/globals.yml
sudo sed -i '/#enable_central_logging/i enable_central_logging: "yes"' /etc/kolla/globals.yml
sudo sed -i '/#enable_magnum/i enable_magnum: "yes"' /etc/kolla/globals.yml
sudo sed -i '/#enable_horizon_magnum/i enable_horizon_magnum: "{{ enable_magnum | bool }}"' /etc/kolla/globals.yml

# enable cinder
#sed -i '/#enable_cinder:/i enable_cinder: "yes"' /etc/kolla/globals.yml
#sed -i '/#enable_cinder_backend_lvm/i enable_cinder_backend_lvm: "yes"' /etc/kolla/globals.yml
#sed -i '/#cinder_volume_group/i cinder_volume_group: "cinder-volumes"' /etc/kolla/globals.yml

sed -i '/keystone_admin_password/c\keystone_admin_password: "'$ADMIN_PASSWORD'"' /etc/kolla/passwords.yml

#enable_hyperv

systemctl restart docker
systemctl enable docker

set_up_cinder

sudo kolla-ansible pull
sudo kolla-genpwd

#sudo kolla-ansible prechecks -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

#add_hyperv

sudo kolla-ansible deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one
sudo kolla-ansible post-deploy -i /usr/local/share/kolla-ansible/ansible/inventory/all-in-one

#./dev-kolla3.sh
