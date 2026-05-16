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
 1. Upgrade the control-plane node first (if multiple control-plane nodes exist, upgrade them one at a time): 
    * upgrade kubeadm, then run `kubeadm upgrade apply` to upgrade the control-plane components (apiserver, controller-manager, scheduler).
    * There is a particular order the components are upgraded, but for kubeadm clusters the order is handled by kubeadm.
 2. Worker nodes: 
    * drain the nodes (one at a time so workloads can shift to alternate worker nodes), 
    * upgrade kubelet and kubectl, 
    * then uncordon the node.

## Upgrade kubeadm control-plane nodes 1.34.8->1.35.X

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
root@k8s-v1:~# sudo apt update
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

Edit the file `/etc/apt/sources.list.d/kubernetes.list`, and change the distribution from `v1.34` to `v1.35`:

```
# e.g. change the line to:
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /
```

```
apt update
apt-cache madison kubeadm # this will help determine the latest stable minor-minor version to upgrade to, e.g. 1.35.5
```

For kubeadm clusters, it is likely that the various kubernetes binaries have an apt `hold` on them, meaning they will be held back from being upgraded until the hold is removed. 

```
root@k8s-v1:~# apt-mark showhold 
kubeadm
kubectl
kubelet
```

```
apt-mark unhold kubeadm
```

There may be workloads running on the control-plane nodes (dependent on cluister settings). Before the upgrade process is started, you may want to drain the control-plane node to shift any workloads to the worker nodes.

```
kubectl drain k8s-v1.34-ubuntu1 --ignore-daemonsets
```

Now we can start the upgrade process:

```
apt update
apt install kubeadm='1.35.5*'   # use the latest stable minor-minor version available in the apt repository
#
# re-implement the 'hold on kubeadm
apt-mark hold kubeadm
```

```
kubeadm upgrade plan
```
The above command checks that the cluster can be upgraded. It will provide the kubeadm process for doing so, and warns of any cluster components that will need to be upgraded manually on its completion.

Choose the latest stable minor-minor version to upgrade to, e.g. 1.35.5, and run the following command to upgrade the control-plane components:

```
kubeadm upgrade apply v1.35.5
```
This command will also automatically renew the certificates managed on this node. To opt-out of certificate renewal the flag `--certificate-renewal=false` can be used.

The upgrade process will typically take 5-10 minutes to complete. Once complete, check the control-plane components are running the new version:

```
#
kubectl version  ## client will still be on the old version until kubectl is upgraded, but server version should be on the new version
#
kubectl get pods -n kube-system -l component=kube-apiserver  -ojsonpath='{.items[].spec.containers[*].image}{"\n"}'
# registry.k8s.io/kube-apiserver:v1.35.5
#
kubectl get pods -n kube-system -l component=kube-controller-manager  -ojsonpath='{.items[].spec.containers[*].image}{"\n"}'
 # registry.k8s.io/kube-controller-manager:v1.35.5
#
kubectl get pods -n kube-system -l component=kube-scheduler  -ojsonpath='{.items[].spec.containers[*].image}{"\n"}'
 # registry.k8s.io/kube-scheduler:v1.35.5
```

The kubelet and kubectl on the control-plane node will still be on the old version. The new minor version should be available from our previous upgrade of the apt repo.

```
apt-cache madison kubelet
apt-cache madison kubectl
# ...shows 1.35.5 is available
```

Removethe hold on kubelet and kubectl, so they can be upgraded.

```
apt-mark unhold kubelet
apt-mark unhold kubectl
```

Upgrade and restart the kubelet service:

```
apt install kubelet="1.35.5*" kubectl="1.35.5*"
systemctl daemon-reload
systemctl restart kubelet
```

Replace the hold on kubelet and kubectl, to prevent them from being accidentally upgraded later on.

```
apt-mark hold kubelet
apt-mark hold kubectl
```
Check the versions:

```
kubectl version
kubectl get nodes 
```

## Upgrade kubeadm worker nodes 1.34.8->1.35.X

For the worker nodes, follow the same process for upgrade:
    1. drain the node (one at a time so workloads can shift to alternate worker nodes), 
    2. point the package manager to the updated kubernetes repo 
    3. remove any package holds, e.g. kubeadm, kubelet, kubectl. (But kubeadm/kubectl may not be relevant on the worker nodes, depending on how the cluster was set up.)
    4. upgrade kubelet, and kubeadm/kubectl if relevant. 
    5. then uncordon the node.
    6. replace the package holds on kubeadm, kubelet and kubectl if they were removed.

    






