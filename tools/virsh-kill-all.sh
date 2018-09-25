virsh list --name | xargs -I {} virsh undefine {}
virsh list --name | xargs -I {} virsh destroy {}