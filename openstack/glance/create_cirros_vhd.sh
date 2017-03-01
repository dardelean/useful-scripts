#!/bin/bash

wget https://github.com/cloudbase/ci-overcloud-init-scripts/raw/master/scripts/devstack_vm/cirros.vhdx -O ~/cirros-gen1.vhdx
openstack image create --public --property hypervisor_type=hyperv --disk-format vhd \
                       --container-format bare --file ~/cirros-gen1.vhdx cirros-gen1-vhdx
