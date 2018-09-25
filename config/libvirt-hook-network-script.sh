#!/bin/bash

# 
# Add veth plumbery to connect linux bridges and obs bridge for management
#


if [ -z "$(ip link | grep veth-mngt-o)" ]; 
        then
        ip link add \
                name veth-mngt-o \
                type veth \
                peer name veth-mngt-l
        if ovs-vsctl br-exists br-management; 
              then
              ovs-vsctl add-port br-management veth-mngt-o;
        fi
fi
ip link set up veth-mngt-o
ip link set up veth-mngt-l

if [ -z "$(brctl show | grep veth-mngt-l )" ] && [ -n "$(brctl show | grep br-nat-mngt)" ]; 
        then
                brctl addif br-nat-mngt veth-mngt-l;
fi
