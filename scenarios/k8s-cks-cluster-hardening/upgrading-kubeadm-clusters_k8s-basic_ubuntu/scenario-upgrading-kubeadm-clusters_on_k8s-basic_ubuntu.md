# Upgrading kubeadm cluster 

At the time of writing, the lastest stable version of kubernetes is 1.36.1. The kubeadm, kubectl and kubelet version of the cluster is 1.34.8.
This scenario will upgrade the kubeadm cluster 1.34.8->1.35.X->1.36.1.

It is recommended to upgrade kubeadm clusters one minor version at a time, e.g. 1.34->1.35->1.36.

```
# e.g.
nodes=(192.168.122.84 192.168.122.152 192.168.122.89)
```

```
ssh ${nodes[0]}
```

```
root@k8s-v1:~# kubectl get nodes 
NAME                STATUS   ROLES           AGE   VERSION
k8s-v1.34-ubuntu1   Ready    control-plane   13m   v1.34.8
k8s-v1.34-ubuntu2   Ready    <none>          13m   v1.34.8
k8s-v1.34-ubuntu3   Ready    <none>          13m   v1.34.8
```


For kubeadm clusters, there will be an official upgrade guide for each minor version (https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

General flow is:
 1. Upgrade the control-plane node first: 
    * upgrade kubeadm, then run `kubeadm upgrade apply` to upgrade the control-plane components (apiserver, controller-manager, scheduler).
    * There is a particular order the components are upgraded, but for kubeadm clusters the order is handled by kubeadm.
 2. Worker nodes: 
    * drain the nodes (one at a time so workloads can shift to alternate worker nodes), 
    * upgrade kubelet and kubectl, 
    * then uncordon the node.

## Upgrade kubeadm to 1.34.8->1.35.X

For each node (control-plane and worker nodes), check the installed kubeadm, kubelet and kubectl version, and check what versions are currently available in the apt repository (assuming ubuntu OS).

```
root@k8s-v1:~# kubeadm version 
kubeadm version: &version.Info{Major:"1", Minor:"34", EmulationMajor:"", EmulationMinor:"", MinCompatibilityMajor:"", MinCompatibilityMinor:"", GitVersion:"v1.34.8", GitCommit:"1f328c5e9dd683d0c5e69f3d7d58f8371278dec2", GitTreeState:"clean", BuildDate:"2026-05-12T09:52:10Z", GoVersion:"go1.25.9", Compiler:"gc", Platform:"linux/amd64"}
root@k8s-v1:~# kubectl version
Client Version: v1.34.8
Kustomize Version: v5.7.1
Server Version: v1.34.8
root@k8s-v1:~# kubelet --version 
Kubernetes v1.34.8
```

This is pretty uniform to start with, and the same is true for all nodes in this scenario.


Check what's available in the apt repository:

```
root@k8s-v1:~# apt-cache madison kubectl 
   kubectl | 1.34.8-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.5-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.4-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.3-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubectl | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
root@k8s-v1:~# apt-cache madison kubeadm
   kubeadm | 1.34.8-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.5-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.4-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.3-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubeadm | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
root@k8s-v1:~# apt-cache madison kubelet
   kubelet | 1.34.8-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.5-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.4-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.3-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
   kubelet | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
```

It seems we're only seeing 1.34.X versions in the apt repository, which means we need to add the apt repository for 1.35.X. This is normal practice.

```


