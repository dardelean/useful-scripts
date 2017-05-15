#!/bin/bash

KOLLA_OPENSTACK_VERSION=4.0.0
KOLLA_INTERNAL_VIP_ADDRESS=192.168.10.17
DOCKER_NAMESPACE=dardelean

cd /mnt/smb
pip install "pywinrm>=0.2.2"
yum install -y python-pip git
pip install -U python-openstackclient python-neutronclient
pip install ./kolla
pip install ./kolla-ansible
cp -r kolla-ansible/etc/kolla /etc/


sed -i '/#kolla_base_distro/i kolla_base_distro: "centos"' /etc/kolla/globals.yml
sed -i '/#docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sed -i '/#openstack_release/i openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sed -i '/#network_interface/i network_interface: "eth0"' /etc/kolla/globals.yml
sed -i '/#neutron_external_interface/i neutron_external_interface: "eth1"' /etc/kolla/globals.yml


# hyperv setup
#sed -i '/#enable_hyperv/i enable_hyperv: "yes"' /etc/kolla/globals.yml
#sed -i '/#hyperv_username/i hyperv_username: "Administrator"' /etc/kolla/globals.yml
#sed -i '/#hyperv_password/i hyperv_password: "Passw0rd"' /etc/kolla/globals.yml
#sed -i '/#vswitch_name/i vswitch_name: "data-net"' /etc/kolla/globals.yml

systemctl restart docker

#kolla-ansible pull
#kolla-genpwd

#kolla-ansible prechecks -i /usr/share/kolla-ansible/ansible/inventory/all-in-one

#sed -i '18 i\[hyperv] \
#192.168.0.120 \
#\
#[hyperv:vars] \
#ansible_user=Administrator \
#ansible_password=Passw0rd \
#ansible_port=5986 \
#ansible_connection=winrm \
#ansible_winrm_server_cert_validation=ignore' /usr/share/kolla-ansible/ansible/inventory/all-in-one
#

#kolla-ansible deploy -i /usr/share/kolla-ansible/ansible/inventory/all-in-one
#kolla-ansible post-deploy -i /usr/share/kolla-ansible/ansible/inventory/all-in-one

# Remove unneeded Nova containers
#for name in nova_compute nova_ssh nova_libvirt
#do
#    for id in $(sudo docker ps -q -a -f name=$name)
#    do
#        sudo docker stop $id
#        sudo docker rm $id
#    done
#done
