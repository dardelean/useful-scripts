#!/bin/bash
# Script that creates an OVS bridge and add a port into a physical network
# The new bridgeconnects into a an existing bridge
# this can be useful in situations when you want to connect to br-int

# bridge to be created
BRIDGE1=$1
# bridge to be connected to
BRIDGE2=$2
# physical inteface to connect to
INTERFACE=$3


# create the ovs bridge 
ovs-vsctl add-br $BRIDGE1
ovs-vsctl add-port $BRIDGE1 $INTERFACE

# connect the two bridges
ovs-vsctl add-port $BRIDGE1 phy-"${BRIDGE1}"
ovs-vsctl set interface phy-"${BRIDGE1}" type=patch

ovs-vsctl add-port $BRIDGE2 int-"${BRIDGE1}"
ovs-vsctl set interface int-"${BRIDGE1}" type=patch


ovs-vsctl set interface phy-"${BRIDGE1}" options:peer=int-"${BRIDGE1}"
ovs-vsctl set interface int-"${BRIDGE1}" options:peer=phy-"${BRIDGE1}"
