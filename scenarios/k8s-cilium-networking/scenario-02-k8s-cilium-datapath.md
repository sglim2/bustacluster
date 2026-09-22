# K8S cilium datapath


A kubernetes cluster running Cilium CNI should be already set up and accessible via ssh.

```
# e.g.
nodes=(192.168.122.164 192.168.122.217 192.168.122.245)
```

```
ssh ${nodes[0]}
```


In this scenario we explore how traffic flows between pods, and how cilium processes, routes, and forwards packets within a Kubernetes cluster.


Since kubernetes is fundamentally a container orchestration tool, some core underlying kernel primitives are important to understand when dealing with traffic and networking between pods:

  - Networking namespaces: In Linux, a network namespace provides an isolated networking stack for processes. Each pod in Kubernetes runs in its own network namespace, which means that it has its own IP address, firewall rules, routing table, and network interfaces. This gives the illusion of eand pods having their own dedicated network stack, even though they share the same underlying host kernel.
  - Virtual ethernet pairs (veth): A veth pair is a pair of virtual network interfaces that are connected to each other. One end of the veth pair is placed in the pod's network namespace, while the other end is placed in the host's network namespace. This allows the pod to communicate with the host and other pods on the same node.


## Pod-to-Pod traffic within the same node

### Trace a successful ping from one pod to another running on the same node.

Create 2 pods - skip the scheduler by assigning them to the same node.

```
kubectl run pod-a --image alpine --overrides='{"spec":{"nodeName":"k8s-cilium2"}}' -- sleep infinity
kubectl run pod-b --image alpine --overrides='{"spec":{"nodeName":"k8s-cilium2"}}' -- sleep infinity
```

Each pod will connect to the host via an `veth` pair. One end of a pair will be in the pod's network namespace (and be available within the pod as, likely, `eth0`) amd the other end will be in the host's network namespace (likely named `lxc*` on the host).

Cilium, as the cluster CNI, will attach eBPF programs to the host's side veth interfaces, and will be able to inspect packets as soon as they leave or enter the pod. This allows cilium early inspection of the packets, and be able to consult any eBPF maps for decision making of those packets. Otherwise, in non-eBPF-based CNIs, the packets would routed through the kernel firewall and iptables rules, which is a more expensive operation.

```
$ kubectl get pods -o wide
NAME    READY   STATUS    RESTARTS   AGE   IP                NODE          NOMINATED NODE   READINESS GATES
pod-a   1/1     Running   0          52s   192.168.225.200   k8s-cilium2   <none>           <none>
pod-b   1/1     Running   0          49s   192.168.225.175   k8s-cilium2   <none>           <none>
```

```
$ kubectl exec -it pod-a --  ping -c 1 192.168.225.175
PING 192.168.225.175 (192.168.225.175): 56 data bytes
64 bytes from 192.168.225.175: seq=0 ttl=63 time=0.188 ms

--- 192.168.225.175 ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 0.188/0.188/0.188 ms
```


The pods are on the same node, so each of their veth pairs are terminated at the same host network namespace. This acts as a common interface for which the pods can communicate with each other. Cilium will inspect the packets, and in this instance, since both pods are on the same node it will forward the packets directly to the destination pod without needing to route them through any other nodes or networks.


For each pod, determine the veth pair names - within the pods and on the host.

```
# pod-a
$ kubectl exec -it pod-a -- ip a | grep eth0
10: eth0@if11: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP 
    inet 192.168.225.200/32 scope global eth0
```

Similarly for pod-b:
```
# pod-b
$ kubectl exec -it pod-b -- ip a | grep eth0
12: eth0@if13: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP 
    inet 192.168.225.175/32 scope global eth0
```

The `pod-a`'s eth0 interface has an index `10`, and point to `if11`, which is the host's side of the veth pair. 
`pod-b`'s eth0 interface has an index `12`, and point to `if13`.

On the host, we can find the corresponding interface:

```
# remeber, pods are running on node k8s-cilium2 - on this host, run:
$ ip a | grep lxc
root@k8s-cilium2:~# ip a | grep lxc 
6: lxc_health@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
9: lxc161c2d2870e9@if8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
11: lxc68e4dd1fee7f@if10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
13: lxc9a61936aa7b7@if12: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
```

The `veth` pairs are therefore 
  * pod-a: eth0@if11 <-> lxc68e4dd1fee7f@if10
  * pod-b: eth0@if13 <-> lxc9a61936aa7b7@if12

These pairngs are how the network network is able to enter/leave the pod's network namespace and connect to the wider networks vis the host's network namespace. 

This is also the point at which cilium attaches eBPF programs to inspect packets, and make routing decision.


You will also notice on the hosts the cilium interfaces `cilium_host`, `cilium_net`, and `cilium_vxlan` (or `cilium_geneve`). 
```
# on host k8s-cilium2
$ ip addr show dev cilium_host
4: cilium_host@cilium_net: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 82:f7:5f:ab:8f:3d brd ff:ff:ff:ff:ff:ff
    inet 192.168.225.119/32 scope global cilium_host
       valid_lft forever preferred_lft forever
    inet6 fe80::80f7:5fff:feab:8f3d/64 scope link 
       valid_lft forever preferred_lft forever
$
$ ip addr show dev cilium_net
3: cilium_net@cilium_host: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 52:92:97:83:ae:e8 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::5092:97ff:fe83:aee8/64 scope link 
       valid_lft forever preferred_lft forever
$
$ ip addr show dev cilium_vxlan
7: cilium_vxlan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default 
    link/ether 3e:ad:a5:bb:8d:de brd ff:ff:ff:ff:ff:ff
    inet6 fe80::3cad:a5ff:febb:8dde/64 scope link 
       valid_lft forever preferred_lft forever
```

The `cilium_host` interface is used as the default gateway for all pods on that host. Here we see the pod gateways reference the host's `cilium_host` ip address:

```
$ kubectl exec -it pod-a --  ip route show 
default via 192.168.225.119 dev eth0 
192.168.225.119 dev eth0 scope link 
$ kubectl exec -it pod-b --  ip route show 
default via 192.168.225.119 dev eth0 
192.168.225.119 dev eth0 scope link 
```

The host's `cilium_net` interface is one half of the `cilium_host`/`cilium_net` veth pair. This veth pair provides cilium with both a host router/gateway address (`cilium_host`) and the `cilium_net` peer device provides an interface for cilium to attach eBPF programs to inspect traffic between pods and the host.

The `cilium_vxlan` interface is used to tunnel traffic between pods on different nodes. It will  not be used for intra-node pod-to-pod traffic, but will be used for inter-node pod-to-pod traffic. This allows pods on different nodes to communicate with each other as if they were on the same network. Cilium uses VXLAN (or Geneve) tunneling to achieve this, which encapsulates the original packet in a new packet with a new header that includes the destination node's IP address. When the packet reaches the destination node, it is decapsulated and delivered to the destination pod. 


## Inspecting traffic control with bpftool

Cilium uses eBPF programs to inspect and manipulate network traffic. These eBPF programs are attached to the cilium interfaces listed previously, and can be used to implement features such as load balancing, network policies, and observability.

To understand how cilium controls the network traffic we will use the `bpftool` utility to inspect the eBPF programs attached to the cilium interfaces. On the host  running the 2 pods (k8s-cilium2), run the following commands:

```
$ bpftool net show
xdp:

tc:
enp1s0(2) tcx/ingress cil_from_netdev prog_id 662 link_id 10 
cilium_net(3) tcx/ingress cil_to_host prog_id 654 link_id 7 
cilium_host(4) tcx/ingress cil_to_host prog_id 645 link_id 5 
cilium_host(4) tcx/egress cil_from_host prog_id 646 link_id 6 
lxc_health(6) tcx/ingress cil_from_container prog_id 675 link_id 9 
cilium_vxlan(7) tcx/ingress cil_from_overlay prog_id 638 link_id 3 
cilium_vxlan(7) tcx/egress cil_to_overlay prog_id 639 link_id 4 
lxc161c2d2870e9(9) tcx/ingress cil_from_container prog_id 734 link_id 11 
lxc68e4dd1fee7f(11) tcx/ingress cil_from_container prog_id 952 link_id 12 
lxc9a61936aa7b7(13) tcx/ingress cil_from_container prog_id 964 link_id 13 

flow_dissector:

netfilter:

```

The listing shows where Cilium has attached eBPF programs.

The host-side Cilium devices, such as `cilium_host`, `cilium_net`, and `cilium_vxlan`, are used by Cilium to process traffic as it moves between pods, the host, other nodes, and overlay networks.

Each pod also has a host-side veth device named `lxc*`. These usually have an ingress program called `cil_from_container`. Although this is shown as `ingress`, it represents traffic leaving the pod, because packets sent out of the pod enter the host-side veth device. This means pod traffic is processed by Cilium as soon as it reaches the host network namespace.


In our example, packets sent from pod-a to pod-b traverse the following simplified path:

pod-a eth0 -> lxc68e4dd1fee7f -> Cilium eBPF datapath -> lxc9a61936aa7b7 -> pod-b eth0

The packet leaves pod-a through its veth pair and appears on the host-side lxc interface, where the cil_from_container program runs. Because pod-b is on the same node, Cilium can redirect the packet directly to pod-b's host-side veth without using cilium_vxlan, and usually without traversing cilium_net/cilium_host.

We can confirms this by analysing `tcpdump` on the host-side veth interfaces, and on the cilium interfaces. We should see packets on the lxc interfaces, but not on the cilium interfaces.

Simultaneously run the following 3 commands on the host (k8s-cilium2):

```
$ tcpdump -ni lxc68e4dd1fee7f icmp
$ tcpdump -ni lxc9a61936aa7b7 icmp
$ tcpdump -ni cilium_net icmp
```

Once running perform a ping from pod-a (IP=192.168.225.200) to pod-b (IP=192.168.225.175):

```
$ kubectl exec -it pod-a -- ping -c1 192.168..225.175
```

The outputs of the tcpdump command should show something similar to the following:

```
# lxc68e4dd1fee7f
18:05:59.011031 IP 192.168.225.200 > 192.168.225.175: ICMP echo request, id 89, seq 0, length 64
18:05:59.011099 IP 192.168.225.175 > 192.168.225.200: ICMP echo reply, id 89, seq 0, length 64

# lxc9a61936aa7b7
18:05:59.011068 IP 192.168.225.200 > 192.168.225.175: ICMP echo request, id 89, seq 0, length 64
18:05:59.011080 IP 192.168.225.175 > 192.168.225.200: ICMP echo reply, id 89, seq 0, length 64

# cilium_net
# no output
```

This confirms that the packets are being processed by Cilium, but are not traversing the cilium_net interface, and are being redirected directly to the destination pod's veth interface.


In modern kernels (6.8 owards), an alternative to veth can be used, named netkit. The netkit kernel feature allows ebpf program to be attached to the pod's network namespace directly, without needing to traverse the host's network namespace. This can improve performance and reduce latency for pod-to-pod traffic, especially for pods on the same node. t the time of writing (cilium version 1.19.3), this feature needs to be explicilty enabled in the cilium configuration, and a modern enough kernel.


## Pod-to-Pod traffic across different nodes

Keeping the previous pods running, create a new pod on a different node:

```
kubectl run pod-c --image alpine --overrides='{"spec":{"nodeName":"k8s-cilium3"}}' -- sleep infinity
```

The default routing for pod-a to pod-c will be through the cilium_vxlan interface, which will encapsulate the original packet in a new packet with a new header that includes the destination node's IP address. When the packet reaches the destination node, it is decapsulated and delivered to the destination pod.

Let's confirm the routing by again monitoring the traffic on the host-side veth interfaces, and on the cilium interfaces. We should see packets on the lxc interface of pod-a, and on the cilium_vxlan interface, but not on the lxc interface of pod-c. But first confirm that the `lxc` interface paired with pod-c eth0 interface (this is `lxcaf5e8c67773b` on k8s-cilium3 on this author's particular test).

```
# on k8s-cilium2
$ tcpdump -ni lxc68e4dd1fee7f icmp
$ tcpdump -ni cilium_vxlan icmp

# on k8s-cilium3
tcpdump -ni cilium_vxlan icmp
tcpdump -ni lxcaf5e8c67773b icmp
```


Perform a ping from `pod-a` (residing on `k8s-cilium2`) to `pod-c` (on `k8s-cilium3`), having first determined the IP address of pod-c (`192.168.226.43` in this author's test):

```
kubectl exec -it pod-a -- ping -c1 192.168.226.43
```

The output of the 4 tcpdumps are:

```
$ root@k8s-cilium2:~# tcpdump -ni lxc68e4dd1fee7f icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lxc68e4dd1fee7f, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:22:40.327653 IP 192.168.225.200 > 192.168.226.43: ICMP echo request, id 131, seq 0, length 64
22:22:40.327942 IP 192.168.226.43 > 192.168.225.200: ICMP echo reply, id 131, seq 0, length 64

$ root@k8s-cilium2:~# tcpdump -ni cilium_vxlan icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_vxlan, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:22:40.327680 IP 192.168.225.200 > 192.168.226.43: ICMP echo request, id 131, seq 0, length 64
22:22:40.327899 IP 192.168.226.43 > 192.168.225.200: ICMP echo reply, id 131, seq 0, length 64


root@k8s-cilium3:~# tcpdump -ni cilium_vxlan icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_vxlan, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:22:40.329733 IP 192.168.225.200 > 192.168.226.43: ICMP echo request, id 131, seq 0, length 64
22:22:40.329813 IP 192.168.226.43 > 192.168.225.200: ICMP echo reply, id 131, seq 0, length 64

root@k8s-cilium3:~# tcpdump -ni lxcaf5e8c67773b icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lxcaf5e8c67773b, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:22:40.329785 IP 192.168.225.200 > 192.168.226.43: ICMP echo request, id 131, seq 0, length 64
22:22:40.329802 IP 192.168.226.43 > 192.168.225.200: ICMP echo reply, id 131, seq 0, length 64
```

The output from the four packet captures shows the full cross-node path.

On the source node, `k8s-cilium2`, we see the ICMP request on pod-a's host-side veth interface:

```text
lxc68e4dd1fee7f:
192.168.225.200 > 192.168.226.43: ICMP echo request
```

This shows the packet leaving pod-a and entering the host network namespace. At this point, Cilium's `cil_from_container` eBPF program processes the packet. Because the destination pod is not on the same node, Cilium cannot simply redirect the packet to another local `lxc` interface. Instead, it sends the packet through the VXLAN datapath.

We can see the same ICMP request on `cilium_vxlan` on the source node:

```text
cilium_vxlan on k8s-cilium2:
192.168.225.200 > 192.168.226.43: ICMP echo request
```

This is the original pod-to-pod packet before it is sent across the node network. Cilium then encapsulates this packet inside a new outer packet. The outer packet uses the source and destination node IP addresses, allowing the underlying network to deliver it from `k8s-cilium2` to `k8s-cilium3`.

On the destination node, `k8s-cilium3`, we again see the ICMP request on `cilium_vxlan`:

```text
cilium_vxlan on k8s-cilium3:
192.168.225.200 > 192.168.226.43: ICMP echo request
```

This shows the packet after it has arrived on the destination node and been decapsulated. The inner packet is still the original pod-to-pod packet: source pod `192.168.225.200`, destination pod `192.168.226.43`.

Finally, we see the packet on pod-c's host-side veth interface:

```text
lxcaf5e8c67773b:
192.168.225.200 > 192.168.226.43: ICMP echo request
```

This confirms that the packet is delivered from the VXLAN datapath to pod-c.

The simplified request path is:

```text
pod-a eth0
  -> lxc68e4dd1fee7f
  -> Cilium eBPF processing
  -> cilium_vxlan on k8s-cilium2
  -> VXLAN tunnel between nodes
  -> cilium_vxlan on k8s-cilium3
  -> lxcaf5e8c67773b
  -> pod-c eth0
```


The echo reply follows the same path in reverse:

```text
pod-c eth0
  -> lxcaf5e8c67773b on k8s-cilium3
  -> cilium_vxlan on k8s-cilium3
  -> encapsulated VXLAN packet across the node network
  -> cilium_vxlan on k8s-cilium2
  -> lxc68e4dd1fee7f on k8s-cilium2
  -> pod-a eth0
```

One important point is that we should expect to see the packet on pod-c's `lxc` interface. The VXLAN tunnel only carries the packet between nodes. Once the packet has arrived on the destination node and has been decapsulated, it still has to be delivered into the destination pod through that pod's host-side veth interface.

The packet captures therefore confirm the cross-node path:

```text
source pod veth -> source node VXLAN -> destination node VXLAN -> destination pod veth
```

This is different from same-node pod-to-pod traffic. For same-node traffic, Cilium can redirect the packet directly from one local pod veth to another local pod veth. For cross-node traffic, Cilium must send the packet through the node-to-node overlay network.

Note also that the packet would also be seen on the host's physical network interface (e.g., `enp1s0`), as the VXLAN packet is sent over the physical network







