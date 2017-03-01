#!/bin/bash

wget http://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img -O ~/cirros.img
openstack image create --public --disk-format qcow2 --container-format bare --file ~/cirros.img cirros-qcow2
