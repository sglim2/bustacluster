# Create a Basic VM

Create a basic VM, with the option to choose the VM name, image, RAM, vCPUs, disk size, and number of VMs.

An integer value, starting at 1, is appended to CLUSTERNAME, and becomes the VM name.

defaults:

```bash
CLUSTERNAME=basic
IMAGENAME=rocky10
CLUSTEROSVARIANT=rocky10
CLUSTERRAM=8192MB
CLUSTERVCPUS=6
DISKSIZE=10G
nVMS=1
```

Make sure ansible is installed.

To adjust the default values, set the desired variables, for example:

```bash
CLUSTERNAME=mybasicVM DISKSIZE=20G nVMS=3 bash deploy.sh
#
# ubuntu:
CLUSTERNAME=ubuntu24.04-basic IMAGENAME=ubuntu24.04 DISKSIZE=20G nVMS=1 CLUSTEROSVARIANT=ubuntunoble bash deploy.sh
```

A VM disk image will be created in the current directory, named ```mybasicVM1.qcow2```, ```mybasicVM2.qcow2```, etc.




