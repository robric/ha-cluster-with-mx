# Multi Node Topology Deployer 

## What is it ?

The Multi Node Topology Deployer is a set of ansible playbooks that aims at deploying complex topologies in an automated fashion. It is based on virtualisation on both compute and networking ressources that can be spread on several physical servers in a transparent fashion. 

So far deployment of networking nodes (outside contrail) is restricted  VMX VM (nested) newer release should include vQFX so Fabric topologies can be emulated too.

The main benefit of this approach is the automated defintion of OVS VXLAN overlay networking connectivity between compute in which all Virtual Networks are transported. For simplicity, this is managed in a Hub and Spoke fashion. All Nodes (Contrail, Openstack, K8, VMX, ...) are subsequently deployed in this overlay. 

When deploying on several physical servers, the only assumption to take care of is that you have IP connectivity between servers with JUMBO frames (this is the only step where you might need to reconfigure your switches). 

## Concretely 

An example below, where an engineer has 3 servers with 20 vcpu each and wants to emulate a Contrail HA cluster with MX GW and remote on several computes (testing/assessing things such as load balancing, redundancy, convergence, scale-out scenarios). Considering the amount of ressources, it is not possible to run such a complex design on a single compute, while networking make things complicated to operate at networking level (many virtual networks mapped to VLANs which have stickyness at fabric level).

```
                                                          +------------------------------------+                   
                                                          |            IP with JUMBO           |                   
                                                          +------------------|-----------------+                   
                                                           -----/            |           \-----                    
                                                     -----/                  |                 \-----              
                                         +----------/------+        +--------|--------+        +-----\-----------+ 
                                         |    SERVER 1     |        |     SERVER 2    |        |     SERVER 3    | 
                                         |   (20 vcpus)    |        |    (20 vcpus)   |        |    (20 vcpus)   | 
                                         |                 |        |                 |        |                 | 
                                         +-----------------+        +-----------------+        +-----------------+ 
                                                                        |    |                                     
                                                                        |    |                                     
                                                                        |    |                                     
 Contrail HA SETUP VIRTUAL DEPLOYMENT ON 3 PHYSICAL SERVERS             |    |                                     
 WITH:                                                                  |    |                                     
                                                                        |    |                                     
 - 4 computes: 6+5+4+4 = 21 vcpus                                       |    |                                     
 - 3 Controllers (Contrail/K8/OS): 3*7 = 21 vpcus                       |    |                                     
 - 2 VMX Gateway: 2*4 = 8 vcpus                                        \      /                                    
 - 1 Remote VMX PE = 4 vcpus                                            \    /                                     
                                                                         \  /                                      
 Note that 2 vCPUs are kept free for each Server (18 each)                --                                       
                                                                                                                   
                                                                  +------------------+                             
                                                                  |    SERVER 1      |                             
                                                                  |                  |                             
                                                                  |  VMX-GW-1 (4v)   |                             
                                                                  /  VMX-GW-2 (4v)   \                             
                                                                /-|  VMX-PE 3 (4v)   |\                            
                                                       V       /  |                  | \      V                    
                                                       X      /   |  Compute-1 (6v)  |  \     X                    
                                                       L    /-    +------------------+   -\   L                    
                                                       A   /                               \  A                    
                                                       N  /                                 \ N                    
                                                        /-                                   \                     
                                                       /                                      \                    
                                           +--------------------+                   +--------------------+         
                                           |     SERVER 2       |                   |      SERVER 3      |         
                                           |                    |                   |                    |         
                                           | Controller 1 (7v)  |                   |  Controller 3 (7v) |         
                                           | Controller 2 (7v)  |                   |                    |         
                                           |                    |                   |  Compute-3 (6v)    |         
                                           | Compute-2 (4v)     |                   |  Compute-4 (5v)    |         
                                           |                    |                   |                    |         
                                           +--------------------+                   +--------------------+         
                                                                                                                   
```

The next section covers the deployment embedded in this  based on Openstack (multicast or massive scale-out scenarios on many computes). It is possible to modify/customize the topology for other requirements (example remote compute).

## Out of Band Management 

### OOB definition: 192.168.222.0 reached via NAT from VXLAN HUB Host

An out of band management connects all VMs in the 192.168.222.0/24 network: note that this is NOT the default libvirt network (192.168.122.0/24).

There is some trick and complexity behind management as it is actually made of 2 management networks cross-connected via veth on a central node (an OVS one and a linux bridge one for a proper IP integration in qemu/libvirt). 

```
                                                                                                                                                            
 VM-XXX are VMs, they can be VMX or CONTRAIL/OPENSTACK VMs                                                                                                  
                                                                                                                                                            
                                            +----------------------------------------------------------+                                                    
                                            |              HUB VXLAN NODE                              |                                                    
                                            |                                                          |                                                    
                                            |                                                          |                                                    
                                            |                                                          |                                                    
                                            |         +---------------------+                          |                                                    
                                            |         |     br-nat-mngt     |                          |                                                    
                                            |         |  192.168.222.0/24   |                          |                                                    
                                            |         +----------|----------+                          |                                                    
                         physical NIC       |                    |                                     |                                                    
                         -to internet-      |                    |                                     |                                                    
                 ----------------------------                    |                                     |                                                    
                                            |                  veth            +----------+            |                                                    
                                            |                    |    +-----   |   VM-5   |            |                                                    
                                            |                    |    |        +----------+            |                                                    
                                            |                    |    |                                |                                                    
                                            |         +---------------|-----+        +----------+      |                                                    
                                            |         |     br-management   +-----   |   VM-6   |      |                                                    
                                            |         ----------------------+        +----------+      |                                                    
                                            |       -/    -/            \   \                          |                                                    
                                            |     -/    -/               \   \                         |                                                    
                                            +----/-----/------------------\---\------------------------+                                                    
                                               -/    /                     \   \                                                                            
                                             -/    -/                       \   \                                                                           
                                            /    -/                          \   \     - br-nat-mngt provides access to host / internet through NAT         
                                          -/ V  /                             \ V \    - br-management connects VN in a Layer 2 bridge                      
                                        -/  X -/                               \ X \   - both management bridges are dynamicall interconnected through a    
                                       /  L -/                                  \ L \  veth interfaces via a libvirt hook script ( /etc/libvirt/hooks/qemu )
                                     -/  A-/                                     \ A \                                                                      
                                   -/  N /                                        \ N \                                                                     
                                 -/    -/                                          \   \                                                                    
       +------------------------/-----/-----------------------+                 +------------------------------------------------------+                    
       |                      -/   -/       LEAF VXLAN NODE 1 |                 |    \   \                           LEAF VXLAN NODE 2 |                    
       |                    -/    /                           |                 |     \   \                                            |                    
       |                   /    -/                            |                 |      \   \                                           |                    
       |                 -/   -/                              |                 |       \   \                                          |                    
       |               -/    /      +----------+              |                 |        \   \               +----------+              |                    
       |              /    -/----   |   VM-1   |              |                 |         \   \     +-----   |   VM-2   |              |                    
       |            -/   -/|        +----------+              |                 |          \   \    |        +----------+              |                    
       |          -/   -/  |                                  |                 |           \   \   |                                  |                    
       |   +-----/----/----|-----+                            |                 |   +---------------|-----+                            |                    
       |   |     br-management   |                            |                 |   |     br-management   |                            |                    
       |   +---------------|-----+                            |                 |   +---------------|-----+                            |                    
       |                   |                                  |                 |                   |                                  |                    
       |                   |        +----------+              |                 |                   |        +----------+              |                    
       |                   +-----   |   VM-3   |              |                 |                   +-----   |   VM-4   |              |                    
       |                            +----------+              |                 |                            +----------+              |                    
       |                                                      |                 |                                                      |                    
       +------------------------------------------------------+                 +------------------------------------------------------+                                                                                     
```

### OK give me some examples

In order to illustrate the above, we can see the list of interfaces below (taken from HUB VXLAN node).

```

[root@5b5s40 ~]#ip addr
[...]
9: br-management: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
    link/ether 9e:87:b2:80:19:44 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::9c87:b2ff:fe80:1944/64 scope link 
       valid_lft forever preferred_lft forever
       
18: br-nat-mngt: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 00:00:ff:ab:cd:ef brd ff:ff:ff:ff:ff:ff
    inet 192.168.222.1/24 brd 192.168.222.255 scope global br-nat-mngt
       valid_lft forever preferred_lft forever

14: veth-mngt-l@veth-mngt-o: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-nat-mngt state UP group default qlen 1000
    link/ether 4e:94:66:a5:c7:7e brd ff:ff:ff:ff:ff:ff
    inet6 fe80::4c94:66ff:fea5:c77e/64 scope link 
       valid_lft forever preferred_lft forever

15: veth-mngt-o@veth-mngt-l: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master ovs-system state UP group default qlen 1000
    link/ether 72:f8:79:7d:db:7d brd ff:ff:ff:ff:ff:ff
    inet6 fe80::70f8:79ff:fe7d:db7d/64 scope link 
       valid_lft forever preferred_lft forever
```

We can see that on HUB VXLAN two management bridges are created and VMs have an interface in the br-management network.

```
[root@5b5s40 ~]# virsh net-list
 Name                 State      Autostart     Persistent
----------------------------------------------------------
[ ...}
 br-management        active     yes           yes
 br-nat-mngt          active     yes           yes
[...]

[root@5b5s40 ~]# virsh list
 Id    Name                           State
----------------------------------------------------
 1     vmx-dc-1                       running
 3     vmx-dc-2                       running
 7     compute-4v-10                  running
 8     compute-4v-9                   running
 9     compute-4v-8                   running
 10    compute-6v-6                   running
 11    compute-6v-5                   running
 12    compute-4v-7                   running
 36    vmx-remote                     running

[root@5b5s40 ~]# virsh domiflist vmx-dc-1
Interface  Type       Source     Model       MAC
-------------------------------------------------------
vm-01-mgt  bridge       br-management virtio      00:00:ff:aa:aa:01
vm-01-eth-00 bridge     br-lan-dc  virtio      52:54:00:26:de:61
vm-01-eth-01 bridge     br-wan-dc-p1-1 virtio      52:54:00:62:c1:49
vm-01-eth-02 bridge     br-wan-dc-dc virtio      52:54:00:cd:32:f1

[root@5b5s40 ~]# virsh domiflist compute-4v-10 
Interface  Type       Source     Model       MAC
-------------------------------------------------------
vnet0      bridge     br-management virtio      52:54:00:9d:86:22
vnet1      bridge     br-lan-dc  virtio      52:54:00:7f:0e:09

[root@5b5s40 ~]# 

```
On a SPOKE VXLAN host, only br-management network is configured to connect VM in OOB
```
[root@5b5s41 ~]# virsh net-list
 Name                 State      Autostart     Persistent
----------------------------------------------------------
[...]
br-management        active     yes           yes


[root@5b5s41 ~]# 

[root@5b5s41 ~]# virsh list
 Id    Name                           State
----------------------------------------------------
 7     all-in-one-3                   running
 8     all-in-one-2                   running
 9     all-in-one-1                   running
 10    compute-4v-1                   running
 11    compute-4v-3                   running
 12    compute-4v-2                   running
 13    compute-4v-4                   running

[root@5b5s41 ~]# 

[root@5b5s41 ~]# virsh domiflist all-in-one-3 
Interface  Type       Source     Model       MAC
-------------------------------------------------------
vnet0      bridge     br-management virtio      52:54:00:c7:f8:8b
vnet1      bridge     br-lan-dc  virtio      52:54:00:23:b2:72

[root@5b5s41 ~]# 

 ```    
 
# Topology Deployment Example

## Contrail HA design with VMX and Remote PE 

This set of ansible  playbooks will deploy a complex topology based on VMX and Contrail/Openstack Virtual Machines and nested virtualisation. The scope of this deployment is mostly for lab/demo purposes where ressources requirements is not crucial. For example,  we deploy on 2 physical servers a set of 16 nodes made up of Contrail/Openstack HA setup(3 VMs) + redundant VMX (2VMs)  + 1 remote PE (1 VM) + 10 computes (10 VMs).

It assumes solely a fresh compute reimaged with Centos (tested with 7.5, later versions should work too - just not tested here -).  The ansible script taking care of node package installation and provisionning of the Virtual Topology and Configuring VMX, while the Contrail ansible deployer will deploy Contrail/Openstack thanks to pre-configured intallation files. 

Note that there is not much server version dependancy vis a vis the Overlay Topology (Openstack, Contrail, VMX, etc..) as it is used for the contruction of the virtual topology (VMs and VNs to hosting the Virtual Topology). 

Again, we have nested virtualisation (VMs in VMs and VNs in VNs) so don't expect performances, still, this is a very good tool for building demo/lab complex network emulation involving multiple nodes (think of testing multicast with several VMX and VROUTERs) when you can't afford the luxury to purchase 10+ physical servers.

## Target Design

### Virtual Topology

This deployment is mostly for testing purposes. Upon completion of the deployment, the following VMs will be spawned:
 - 10 nested computes nodes: 
 - HA control planes (openstack all but nova-compute, contrail all but vrouter):
 - Redundant VMX GW: vmx-dc-x
 - Remote PE: vmx-remote

This virtual topology is spread over several computes in order to be be able onboard enough compute ressources. For this purpose an overlay network (VXLAN) is implemented in order to virtually connect all VMs in consistent virtual networks wherever their location. Note that this implies that jumbo frames must be transported from computes to computes so as to carry the overlay overhead flawlessly.

The details of this implementation is detailed in the Overlay Networking section.

```
                                                                                                                                             
                                      +------------+                                                                                         
                                      | vmx-remote |                                                                                         
                                      /------------\                                                                                         
                                     /              -\                                                                                       
                {  br-wan-dc-p1-1 } /                 \ {  br-wan-dc-p1-2 }                                                                  
                                  /-    ISIS/LDP       \                                                                                     
                                 /                      -\                                                                                   
                       ge-0/0/1 /                         - ge-0/0/1                                                                         
                    +-----------       { br-wan-dc-dc }    +----------+                                                                      
                    | vmx-dc-1 |---------------------------- vmx-dc-2 |                                                                      
                    +-----|----+ ge-0/0/2         ge-0/0/2 +-----|----+       +        +-----------+                                         
                 ge-0/0/0 |                                      | ge-0/0/0        +---- compute-1 | .161                                    
                          |.101                             .102 |                 |   +-----------+                                         
                          |                                      |                 |   +-----------+                                         
                          |                                      |                 |---- compute-2 | .162                                    
                          |                                      |                 |   +-----------+                                         
                          |          192.168.100.0/24            |                 |   +-----------+                                         
                          |                                      |                 |   | compute-3 | .163                                    
         |-------------|-------------| { br-lan-dc }  -----------------------------|---+-----------+                                         
         |             |             |                                             |   +-----------+                                         
   +-----|----+  +-----|----+  +-----|----+                                        |---- compute-4 | .164                                    
   |all-cont-1|  |all-cont-2|  |all-cont-3|                                        |   +-----------+                                         
   +----------+  +----------+  +----------+                                        |   +-----------+                                         
      .151          .152           .153                                            |---- compute-5 | .165                                    
                                                            NESTED COMPUTES (10)   |   +-----------+                                         
             HA SDN CONTROLLERS                             Naming convention      |   +-----------+                                         
          (OPENSTACK / CONTRAIL)                            is actually            |---- compute-6 | .166                                    
                                                            compute-#vcpu-ID       |   +-----------+                                         
                                                                                   |   +-----------+                                         
                                                                                   |---- compute-7 | .167                                    
   NESTED TOPOLOGY:                                                                |   +-----------+                                         
                                                                                   |   +-----------+                                         
   - DATA PLANE CONNECTIVITY                                                       |---- compute-8 | .168                                    
   - IP ADDRESSING                                                                 |   +-----------+                                         
   - BRIDGE NAMES                                                                  |   +-----------+                                         
                                                                                   |---- compute-9 | .169                                    
                                                                                   |   +-----------+                                         
                                                                                   |   +-----------+                                         
                                                                                   +---- compute-10| .170                                    
                                                                                       +-----------+                                         
                                                                                                          
```

### IP Addressing of Virtual Topology

All Contrail nodes are in a single control-plan Virtual Network "br-lan-dc" with IP subnet 192.168.100.0/24 with:
 - Computes .161 to .170
 - Controllers: .151,.152 and .153

VMX have several interfaces as indicated on the picture:
 - VMX IP in br-lan-dc: .101 and .102 with VRRP IP .254


## Phyiscal / Underlay Topology

### Physical Topology

In this example, the virtual topology is based on two servers (2 * 10 Cores each). The ansible playbook is flexible enough to add extra servers (have a look at the inventory file) and spread the vcpu/memory accordingly in order to support the virtual topology requirements (see customization).

```                                                                                                                                                                                                                                       
         +----------------------+                                                            +----------------------+     
         |                      |                                                            |                      |     
         |      SERVER 1        |                                                            |      SERVER 2        |     
         |      (5b5s40)        |                +-----------------------+                   |      (5b5s41)        |     
         |                      |                |                       |                   |                      |     
         |                      |                |   IP CONNECTIVITY     |                   |                      |     
         |                      |----------------|    (e.g. Fabric)      --------------------|                      |     
         |      40 vcpu         |                |                       |                   |       40 vcpu        |     
         |  (2*10 cores + HT)   |                +-----------------------+                   |   (2*10 cores + HT)  |     
         |                      |                                                            |                      |     
         |                      |                                                            |                      |     
         |                      |                                                            |                      |     
         +----------------------+                                                            +----------------------+     
                                                                                                                         -
                                                                                                                          
                                    ---------------------------------------------------                                   
                                        VXLAN TUNNELS FOR VIRTUNAL NETWORKS/TOPO                                          
                                    ---------------------------------------------------                                                                                                                                                                                                                                                                                                                                                                                                          
```

### Virtual Networking

Virtual Networking is based on OVS VXLAN with the exception for management where we use a local linux bridge Virtual Network to enter the underlay networking through NAT (the reason is NAT +  OVS VN is not supported in libvirt).

For this purpose we have Hub and Spoke Topology of phyiscal servers (i.e. the overlay traffic from spoke to spoke will transit through the Hub). This approach simplifies the definition of the networking topology to the detriment of performances.


## Deployment Instructions

1. Reimage a set of servers in Centos 7.5
2. On a git installer host (example HUB host): git clone go the created folder  

```
cd
yum install -y git ansible-2.4.2.0
git clone https://github.com/robric/ha-cluster-with-mx
cd ha-cluster-with-mx

```
4. Edit the inventory file (inventory.ini) with host information. Single hub and several spokes definition in appropriate groups is mandatory as this script will deploy an overlay topology to transport Virtual Networks in a hub and spoke fashion thanks to OVS VXLAN.
```
vi inventory.ini
```
5. Edit the var file, where topology is actually defined: 
   * vmx_download_url and vmx_image_name variables location getting a fresh vmx image (qcow2 format)
   * topology.network for networking definition: vni and names
   * topology.instances for VMX: vmx properties (such as interface connectivity) and flavor (defined in this file too)
   
6. Run the set of playbooks

```
ansible-playbook -i inventory.ini deploy.yml" 
``` 
You might give some retry due to reboot (a remote installer is better for that), but if you can not afford it (e.g. installation from VXLAN HUB host) - wait 5 minutes for reboot to complete and VMX to boot up, then run separetely the two scripts 

```
ansible-playbook -i inventory.ini vmx-config_only.yml
ansible-playbook -i inventory.iniinstall_hub_only.yml
```

Now the virtual topology is installed

7. Edit the contrail ansible deployer 

Conntect to the VXLAN Hub host and edit the Contrail ansible config file instances.yaml (auto-generation is not automated yet)
Things such as ntp server or Host IP of your physical hosts must be updated on all nodes.

```
cd
[root@5b5s40 ~]# vi contrail-ansible-deployer/config/instances.yaml
global_configuration:
  CONTAINER_REGISTRY: ci-repo.englab.juniper.net:5010
  REGISTRY_PRIVATE_INSECURE: True
provider_config:
  kvm:
    image: CentOS-7-x86_64-GenericCloud-1805.qcow2   ############# potentially replace it - it is upgraded anyway - 
    image_url: http://10.84.5.120/cs-customer/images ############# you may replace it https://cloud.centos.org/centos/7/images/
    ssh_pwd: c0ntrail123
    ssh_user: root
    ssh_public_key:
    ssh_private_key:
    vcpu: 8
    vram: 65536
    vdisk: 170G
    subnet_prefix: 192.168.222.0
    subnet_netmask: 255.255.255.0
    gateway: 192.168.222.1
    nameserver: 192.168.222.1
    ntpserver: 10.84.5.100                            ###### Use an ntp server 
    domainsuffix: sdn.lab
instances:
  all-in-one-1:
    provider: kvm
    host: 10.87.65.29                                ###### Configure your PHyiscal HOST IP for all instances !
    bridge: br-management
    ip: 192.168.222.151
    additional_interfaces:
      - bridge: br-lan-dc
        ip: 192.168.100.151
        mask: 255.255.255.0
    roles:
      config_database:
      config:
      control:
      analytics_database:
      analytics:
      webui:
      openstack:
 [....]
```

8. Launch the Contrail ansible deployer at VXLAN hub

```
ansible-playbook -i inventory/ playbooks/provision_instances.yml
ansible-playbook -i inventory/ playbooks/configure_instances.yml 
ansible-playbook -i inventory/ playbooks/install_openstack.yml
ansible-playbook -i inventory/ playbooks/install_contrail.yml
``` 

9. Install some SSH redirection for remote reachability 

On VXLAN HUB Host only, for UI access to out of band management network

```
ssh -fNT -L 0.0.0.0:8143:192.168.222.100:8143 root@**HOST_IP_ADDRESS** &
ssh -fNT -L 0.0.0.0:80:192.168.222.100:80 root@**HOST_IP_ADDRESS** &
```

## Customisation 
 Networking: 
 
 This script will configure overlay networking with networks defined in the var file.
 Two well known names are defined by this script (do not change it):
  - br-nat-mngt: Linux Bridge with NAT configured via libvirt to connect to the outer world (ssh, http access, yum install etc..)
  - br-management: OVS bridge to attach VM management interfaces. This bridge is actually connected to br-nat-management via veth interfaces (libvirt network hook script).
  - Next all other bridges are defined as per the var file located in ha-cluster-with-mx/group_vars/all/vars.yaml

Virtual Machines:

- Network devices:
  So far VMX can be brought up with appropriate configuration (stored in the config/ folder with name matching). It is rather simple to deploy different types of VMs with this script.

- Contrail installation:
  This script actually is made to work in conjunction with Contrail's ansible deployer. For this purpose, instances.yaml and clone of this repository is actually installed on the hub site. Standard Contrail installation (provider kvm must follow) with regular scripts starting with provision_instances which will created instances. Same naming of networks (with br-) as define in var file must be used. 

Customization: 

Networks are defined in the vars.yaml file with two parameters: 
 - name 
 - vni for VXLAN 

Networks 

```
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
```

This generates the following linux bridges and libvirt networks (note that "br-" is appended in front of networks):

```

[root@5b5s40 ~]# virsh net-list 
 Name                 State      Autostart     Persistent
----------------------------------------------------------
 br-lan-dc            active     yes           yes
 br-lan-p1            active     yes           yes
 br-management        active     yes           yes
 br-nat-mngt          active     yes           yes
 br-wan-dc-dc         active     yes           yes
 br-wan-dc-p1-1       active     yes           yes
 br-wan-dc-p1-2       active     yes           yes
 default              active     yes           yes

[root@5b5s40 ~]# 

 ```
 
VMX Instances are defined as follow, with the appropriate mapping of interfaces.

```
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
```

For interfaces, a dedicated management interface is created (hardcoded) to host the fxp0 interface, while other interfaces are mapped canonically as follow: 

```
      interfaces:
        management: management      ===========  mapped to ===============> fxp0
        user:  
          0: lan-dc                 ===========  mapped to ===============> ge-0/0/0
          1: wan-dc-p1-1            ===========  mapped to ===============> ge-0/0/1
          2: wan-dc-dc              ===========  mapped to ===============> ge-0/0/2
```



The name, management ip, console ports  are derived from the vm_id (VM identified must be unique) and interface id.

