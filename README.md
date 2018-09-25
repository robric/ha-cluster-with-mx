HA cluster deployment based on topology deployer 

This script will deploy a baseline for complex topologies based on VMX on fresh compute reimaged with Centos (tested with 7.5). 

Instructions:
 - Reimage a set of servers in Centos 7.5
 - Edit the inventory file (inventory.ini) with host information. Single hub and several spokes definition in appropriate groups is mandatory as this script will deploy an overlay topology to transport Virtual Networks in a hub and spoke fashion thanks OVS VXLAN.
 - Edit the var file, where topology is actually defined: 
   * vmx_download_url and vmx_image_name variables location getting a fresh vmx image (qcow2 format)
   * topology.network for networking definition: vni and names
   * instances for VMX: vmx properties (such as interface connectivity) and flavor (defined in this file too)
   
 On a git installer host: 
 - "git clone https://github.com/robric/ha-cluster-with-mx"
 - "cd ha-cluster-with-mx"
 - "ansible-playbook -i inventory.ini deploy.yml" 
 
 Networking: 
 
 This script will configure overlay networking with networks defined in the var file.
 Two well known names are defined by this script (do not change it):
  - br-nat-mngt: Linux Bridge with NAT configured via libvirt to connect to the outer world (ssh, http access, yum install etc..)
  - br-management: OVS bridge to attach VM management interfaces. This bridge is actually connected to br-nat-management via veth interfaces (libvirt network hook script).

Virtual Machines:
- Network devices:
  So far VMX can be brought up with appropriate configuration (stored in the config/ folder with name matching). It is rather simple to deploy different types of VMs with this script.
- Contrail installation:
  This script actually is made to work in conjunction with Contrail's ansible deployer. For this purpose, instances.yaml and clone of this repository is actually installed on the hub site. Standard Contrail installation (provider kvm must follow) with regular scripts starting with provision_instances which will created instances. Same naming of networks (with br-) as define in var file must be used. 
  
  
