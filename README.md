# BustaCluster

BustaCluster a collection of scripts that build virtual HPC/Cloud clusters (e.g. a slurm cluster, kubernetes, ceph). The project is a way of experimenting with clusters, their configuration, and test scenarios and configurations in a non-production environment. All VMs are created using libvirt virtualisation, using tools like virt-builder and virsh. 

The clusters are not designed as production quality, and will often lack features that would be required in a production environment, such as high-availability. The scripts are designed to be run on a single machine, and will create VMs on that machine.


## Requirements

- virt-localrepo (github.com/sglim2/virt-localrepo.git)
- libvirt
- guestfs-tool # (virt-builder)
- ansible


```bash
git clone git@github.com:sglim2/bustacluster.git
cd bustacluster
pyenv install 3.10.15
pyenv global 3.10.15
pyenv activate bustacluster
```

## Build a local virt-builder repository

The script ```virt/repo-builder/build-generics.sh``` will create a local virt-builder repository. See the README.md file in the virt/repo-builder directory for more information.


## Build a cluster 

To build a single VM, run the following command:

```bash

./build-vm.sh -n busta-vm -t generic -d 10G -m 2048 -c 2 -i /path/to/iso

```
