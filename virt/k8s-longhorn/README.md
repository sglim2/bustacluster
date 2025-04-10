# Create a Kubernetes cluster with longhorn storage

Example:

(The kubeadm install script used in this build assumes a RHEL-based OS).

```bash
DISKSIZE=20G longhornDISKSIZE=50G longhornVER=v1.8.1 kubeVER=1.32.0 withCNI=cilium CLUSTERNAME=lh IMAGENAME=rocky9 nVMS=3 bash deploy.sh
```

The k8s-longhorn cluster will be created, with an addition longhorn data-disk attached to each VM.





