#!/bin/bash

#https://ubuntu.com/server/docs/install/autoinstall-quickstart-s390x


wget https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso
sudo mount -r ubuntu-22.04-live-server-amd64.iso /mnt/

mkdir -p ~/www
cd ~/www
# copy the meta-data file in this dir and serve it via a python web server
python3 -m http.server 3003

qemu-img create -f qcow2 maas.qcow2 40G
qemu-img info maas.qcow2

sudo kvm -no-reboot -name maas -m 2048 -cpu host -nographic \
    -drive file=/home/ubuntu/maas.qcow2,format=qcow2,cache=none,if=virtio \
    -cdrom /home/ubuntu/ubuntu-22.04-live-server-amd64.iso \
    -kernel /mnt/casper/vmlinuz \
    -initrd /mnt/casper/initrd \
    -append 'autoinstall ds=nocloud-net;s=http://_gateway:3003/'


virt-install --noautoconsole --print-xml --boot hd,menu=on --osinfo ubuntu22.04\
  $GRAPHICS $CONTROLLER --name maas --ram 2048 --vcpus 2 $CPUOPTS \
  --disk path=/var/lib/libvirt/images/maas.qcow2,size=40,$DISKOPTS \
  --network=network=cloud \
  >> ~/maas.xml
virsh define ~/maas.xml
virsh autostart maas

