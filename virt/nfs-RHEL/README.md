# Create a VM serving an NFS volume

Create an NFS VM, with the option to choose the VM name, image, RAM, vCPUs, root partition disk size, nfs partition disk size, and number of VMs.

An integer value, starting at 1, is appended to CLUSTERNAME, and becomes the VM name.

defaults:

```bash
CLUSTERNAME=nfs
IMAGENAME=rocky9
CLUSTEROSVARIANT=rocky9
CLUSTERRAM=8192 MB
CLUSTERVCPUS=6 vCPUs
DISKSIZE=10G
SCRATCHSIZE=30G
nVMS=1
```

The NFS VM will utilise the VM deploy script of the 'basic' (../basic) VM.


To adjust the default values, set the desired variables:

```bash
CLUSTERNAME=myNFS DISKSIZE=20G SCRATCHDISKSIZE=50G nVMS=1 bash deploy.sh
```

A VM disk image will be created in the current directory, named ```myNFS1.qcow2```.




