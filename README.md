HA cluster deployment based on topology deployer 

This script will deploy a baseline for complex topologies based on VMX on fresh compute reimaged with Centos (tested with 7.5, following versions should work too assuming right packages). 

Instructions:
 - Reimage a set of servers in Centos 7.5
 - Edit the inventory file (inventory.ini) with host information. Single hub and several spokes definition in appropriate groups is mandatory as this script will deploy an overlay topology to transport Virtual Networks in a hub and spoke fashion thanks to OVS VXLAN.
 - Edit the var file, where topology is actually defined: 
   * vmx_download_url and vmx_image_name variables location getting a fresh vmx image (qcow2 format)
   * topology.network for networking definition: vni and names
   * topology.instances for VMX: vmx properties (such as interface connectivity) and flavor (defined in this file too)
   
 On a git installer host: 
 - "git clone https://github.com/robric/ha-cluster-with-mx"
 - "cd ha-cluster-with-mx"
 - "ansible-playbook -i inventory.ini deploy.yml" 
 
 Networking: 
 
 This script will configure overlay networking with networks defined in the var file.
 Two well known names are defined by this script (do not change it):
  - br-nat-mngt: Linux Bridge with NAT configured via libvirt to connect to the outer world (ssh, http access, yum install etc..)
  - br-management: OVS bridge to attach VM management interfaces. This bridge is actually connected to br-nat-management via veth interfaces (libvirt network hook script).
  - Next all other bridges are defined as per the var file located in ha-cluster-with-mx/group_vars/all/vars.yaml
'''
test---notest

'''
Virtual Machines:
- Network devices:
  So far VMX can be brought up with appropriate configuration (stored in the config/ folder with name matching). It is rather simple to deploy different types of VMs with this script.
- Contrail installation:
  This script actually is made to work in conjunction with Contrail's ansible deployer. For this purpose, instances.yaml and clone of this repository is actually installed on the hub site. Standard Contrail installation (provider kvm must follow) with regular scripts starting with provision_instances which will created instances. Same naming of networks (with br-) as define in var file must be used. 

Customization: 

In the vars.yaml file, networks are defined as follow: 

topology:
  networks:
    # Hardcoded management Virtual Network
    - name: management  
      vni: 99
    - name: lan-dc
      vni: 100
    - name: wan-dc-p1-1
      vni: 1000
    - name: wan-dc-p1-2
      vni: 1001
    - name: wan-dc-dc
      vni: 1005
    - name: lan-p1
      vni: 101
 
 This generate the following linux bridges and libvirt networks (note that "br-" is appended in front of networks):


virsh net-list

Name                 State      Autostart     Persistent 
 r-lan-dc            active     yes           yes
 br-lan-p1            active     yes           yes
 br-management        active     yes           yes
 br-nat-mngt          active     yes           yes
 br-wan-dc-dc         active     yes           yes
 br-wan-dc-p1-1       active     yes           yes
 br-wan-dc-p1-2       active     yes           yes
 default              active     yes           yes

 
VMX Instances are defined as follow, with the appropriate mapping of interfaces.
A dedicated management interface is created (hardcoded) to host the fxp0 interface, while other interfaces are mapped canonically:
 - user: 
    0 ==> ge-0/0/0
    1 ==> ge-0/0/1
    [etc]
 
instances:
    - name: vmx-dc-1
      vm_id: 01
      host_id: 1
      flavor: fl-vmx-nested
      interfaces:
        management: management
        user:  
          0: lan-dc
          1: wan-dc-p1-1
          2: wan-dc-dc
    - name: vmx-dc-2
      vm_id: 02
      host_id: 1
      flavor: fl-vmx-nested

The name, management ip, console ports  are derived from the vm_id (VM identified must be unique) and interface id.



        management: management
        user:
          0: lan-dc
          1: wan-dc-p1-2
2: wan-dc-dc
