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
kubectl expose pod nginx -n nginx1 --port=80 --target-port=80  --name=nginx-svc
kubectl run curl --image=curlimages/curl:latest -n nginx1 --restart=Never --overrides='{"spec":{"nodeName":"k8s-ubuntu3"}}' --  /bin/sh -c "while true ; do sleep 10 ; curl nginx-svc.nginx1.svc.cluster.local ; done"
```


### Investigate the following:

  1. Do the Pods use DNS?
  2. Which interfaces see the DNS and HTTP traffic?
  3. Does the HTTP traffic leave the node?
  4. Does the DNS traffic leave the node?
  5. Is NAT involved?
  6. Does the packet pass through a CNI bridge?
  7. Can you identify the veth pair for each Pod?


To answer these questions, let's first discover some details:

```
curl Pod IP
nginx Pod IP
nginx-svc ClusterIP
worker node IP
```


```
IPnginx=$(kubectl get pods -n nginx1 nginx -ojsonpath='{.status.podIPs[0].ip}')
IPcurl=$(kubectl get pods -n nginx1 curl -ojsonpath='{.status.podIPs[0].ip}')
IPnginxsvc=$(kubectl get svc -n nginx1 nginx-svc -ojsonpath='{.spec.clusterIP}')
IPnode=$(kubectl get pod -n nginx1 nginx -ojsonpath='{.status.hostIP}')
```

Identify the DNS:
```
kubectl get svc -n kube-system kube-dns -o wide
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
#
IPdns=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
```

#### Task 1. Do the Pods use DNS?

Does the curl Pod use Kubernetes DNS to resolve: `nginx-svc.nginx1.svc.cluster.local`? ... Very likely since the target is a domain name, unless something like `/etc/hosts` is being used, but let's confirm it by looking at the traffic.

```
# Inspect the pod's dns configuration:
kubectl exec -n nginx1 curl -- cat /etc/resolv.conf
```

The expected output should be the nameserver pointing to `$IPdns` and the search domain likely includes all 3 of `[namespace].svc.cluster.local`, `svc.cluster.local`, and `cluster.local`. This would 
confirm
  - The Pod is configured to use the Kubernetes DNS Service.
  - The nameserver is usually the kube-dns/CoreDNS ClusterIP.
  - The search path includes the Pod namespace.


```
# explicitly test DNS resolution from the curl Pod:
kubectl exec -n nginx1 curl -- nslookup nginx-svc.nginx1.svc.cluster.local
```

The output should show that the DNS query is successful and resolves to the ClusterIP of the nginx-svc `$IPnginxsvc`. This confirms that the Pod is indeed using DNS to resolve service names.

However, to be more certain that the Pod is actually sending DNS queries to the DNS service IP, we can use `tcpdump` to capture the traffic on the node.

On the worker node, use `tcpdump` to capture DNS traffic:

```
timeout 10s tcpdump -ni any "udp port 53 or tcp port 53"
```
This gives information like:
```
22:30:45.020134 cilium_vxlan P   IP 192.168.224.138.53 > 192.168.226.17.53892: 31567 NXDomain*- 0/1/0 (163)
22:30:45.020156 lxc25fed2932472 Out IP 192.168.240.10.53 > 192.168.226.17.53892: 31567 NXDomain*- 0/1/0 (163)
22:30:45.020178 lxc25fed2932472 In  IP 192.168.226.17.55175 > 192.168.240.10.53: 50033+ A? nginx-svc.nginx1.svc.cluster.local.cluster.local. (66)
22:30:45.020187 lxc25fed2932472 In  IP 192.168.226.17.58251 > 192.168.240.10.53: 59921+ AAAA? nginx-svc.nginx1.svc.cluster.local.cluster.local. (66)
22:30:45.020189 cilium_vxlan Out IP 192.168.226.17.55175 > 192.168.224.138.53: 50033+ A? nginx-svc.nginx1.svc.cluster.local.cluster.local. (66)
22:30:45.020198 lxcfe7fb04b3014 Out IP 192.168.226.17.58251 > 192.168.226.224.53: 59921+ AAAA? nginx-svc.nginx1.svc.cluster.local.cluster.local. (66)
22:30:45.020271 lxcfe7fb04b3014 In  IP 192.168.226.224.53 > 192.168.226.17.58251: 59921 NXDomain*- 0/1/0 (159)
22:30:45.020284 lxc25fed2932472 Out IP 192.168.240.10.53 > 192.168.226.17.58251: 59921 NXDomain*- 0/1/0 (159)
22:30:45.020319 lxc25fed2932472 In  IP 192.168.226.17.34263 > 192.168.240.10.53: 61588+ AAAA? nginx-svc.nginx1.svc.cluster.local. (52)
22:30:45.020332 lxcfe7fb04b3014 Out IP 192.168.226.17.34263 > 192.168.226.224.53: 61588+ AAAA? nginx-svc.nginx1.svc.cluster.local. (52)
```

If `IPcurl` is `192.168.226.17`, and `IPdns` is `192.168.240.10` (also recognised in the output from the port `53` references), then we can see that the curl Pod is sending DNS queries to the DNS service IP, and receiving responses from it. This confirms that the Pod is using DNS for name resolution. This output also provide information about the interfaces involved in the DNS traffic. The `cilium_vxlan` interface is likely the CNI bridge or overlay interface, and the `lxc25fed2932472` interface is likely the external side of the veth pair for the curl Pod (the other end sitting inside the Pod's network namespace - usually named eth0). The fact that we see traffic on both interfaces (`cilium_vxlan` and `lxc25fed2932472`) suggests that the DNS queries are being sent from the curl Pod, going through the CNI bridge, and reaching the DNS service.

The interface `lxc25fed2932472` will reside on the worker node where the curl Pod is running (check this by logging in to the relevant worker node and search with `ip a`), and it will be part of a veth pair that connects the Pod's network namespace to the host network. The `cilium_vxlan` interface is likely part of the CNI overlay network that allows communication between Pods across different nodes. 






