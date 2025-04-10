# BustaCluster

BustaCluster a collection of wrapper scripts that build virtual HPC/Cloud clusters (e.g. a slurm cluster, kubernetes, ceph). The project is a way of experimenting with clusters, their configuration, and test scenarios and configurations in a non-production environment. All VMs are created using libvirt virtualisation, using tools like virt-builder and virsh. 

The clusters are not designed as production quality, and will often lack features that would be required in a production environment.


## Requirements

- virt-localrepo (github.com/sglim2/virt-localrepo.git)
- libvirt
- guestfs-tool (virt-builder)
- ansible

## Example

Assuming a suitbale virt-builder image is available (see github.com/sglim2/virt-localrepo.git on how to build a local virt-builder repo)..

```bash
cd virt/k8s-basic
DISKSIZE=20G bash deploy.sh
```

This will build a kubernetes cluster, resizing the root partition of each of the VMs to 20G, and all other parameters maintaining their default values (virt-builder image, k8s version, etc.)

