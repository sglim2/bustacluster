# Create a Basic VM

Create a basic VM, with the option to choose the VM name, image, RAM, vCPUs, disk size, and number of VMs.

An integer value, starting at 1, is appended to CLUSTERNAME, and becomes the VM name.

defaults:

```bash
CLUSTERNAME=basic
IMAGENAME=rocky9
CLUSTEROSVARIANT=rocky9
CLUSTERRAM=8192 MB
CLUSTERVCPUS=6 vCPUs
DISKRESIZE=10G
nVMS=1
```

Make sure ansible is installed.

To adjust the default values, set the desired variables:

```bash
CLUSTERNAME=mybasicVM DISKRESIZE=20G nVMS=3 bash deploy.sh
```

A VM disk image will be created in the current directory, named ```mybasic1.qcow2```, ```mybasic2.qcow2```, etc.




