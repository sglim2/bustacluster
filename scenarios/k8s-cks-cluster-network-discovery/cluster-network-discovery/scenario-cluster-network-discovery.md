# K8S Cluster Network Discovery

Useful baseline tools for this scenario include:

```
tcpdump
ip addr
ip route
ip link
ip netns
ss
conntrack
iptables-save
nft list ruleset
kubectl
crictl
nsenter
dig
curl
openssl s_client
kubectl sniff
ngrep
tshark
```

And a useful habit is to collect information at several layers:

```
inside pod namespace
node veth interface
node bridge / CNI interface
node physical/libvirt interface
control-plane node
libvirt host bridge
```

```
# kubectl get nodes -owide
NAME          STATUS   ROLES           AGE     VERSION   INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
k8s-ubuntu1   Ready    control-plane   5d19h   v1.36.1   192.168.122.184   <none>        Ubuntu 24.04.4 LTS   6.8.0-106-generic (amd64)   containerd://2.2.1
k8s-ubuntu2   Ready    <none>          5d19h   v1.36.1   192.168.122.51    <none>        Ubuntu 24.04.4 LTS   6.8.0-106-generic (amd64)   containerd://2.2.1
k8s-ubuntu3   Ready    <none>          5d19h   v1.36.1   192.168.122.189   <none>        Ubuntu 24.04.4 LTS   6.8.0-106-generic (amd64)   containerd://2.2.1
```


## Pod-to-Pod traffic (same node)

Create two pods on the same node, and set up some data tranfer between the two:

```
kubectl create ns nginx1
kubectl run nginx --image=nginx:latest -n nginx1 --port=80 --restart=Never --overrides='{"spec":{"nodeName":"k8s-ubuntu3"}}'
kubectl run curl --image=curlimages/curl:latest -n nginx1 --restart=Never --overrides='{"spec":{"nodeName":"k8s-ubuntu3"}}'
```
























