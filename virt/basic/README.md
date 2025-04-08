# Create a Basic VM

Create a basic VM, with the option to choose the VM name, image, RAM, vCPUs, disk size, and number of VMs.

An integer value, starting at 1, is appended CLUSTERNAME (and becomes the VM name).

defaults:

```bash
CLUSTERNAME=basic
IMAGENAME=rocky8-bustacluster
CLUSTEROSVARIANT=rocky8
CLUSTERRAM=8192 MB
CLUSTERVCPUS=6 vCPUs
DISKRESIZE=10G
nVMS=1
```

Make sure ansible is installed. From the cluster-build directory use ```pyenv``` to create a virtual environment and install ansible:

```bash
pyenv install 3.10.13
pyenv global 3.10.13
#
python3 -v venv ../py3venv
. ../py3venv/bin/activate
pip install ansible
```


To adjust the default values, pre-pend the variable with the new value:

```bash
CLUSTERNAME=cluster bash deploy.sh
```
The disk-image, cluster (VM) name, will be cluster1, cluster2, etc.




