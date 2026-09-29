# K8S cilium with go/ebpf monitoring

Create a `k8s-basic` cluster with no CNI.

```
CLUSTERNAME=k8s-ebpf withCNI=cilium withPROMETHEUS=1 withMETRICS=1 IMAGENAME=rocky10 CLUSTEROSVARIANT=rocky10 CLUSTERRAM=4096 CLUSTERVCPUS=4 DISKSIZE=20G nVMS=3 bash deploy.sh
```

```
# e.g.
nodes=(192.168.122.21 192.168.122.6 192.168.122.23)
```

```kubectl get nodes``` should show the 3 nodes in Ready state.

Let's also enable the hubble relay. On the control plande node:
```
ssh root@${nodes[0]}
```


```
cilium hubble enable
# again,. wait for it to be ready
cilium status --wait
```

The compomemts listed in the `cilium status` command are:
  - `cilium`: the main CNI component, responsible for networking and network policies.
  - `cilium-envoy`: the Envoy sidecar used for L7 policies and observability. This means that Cilium can enforce policies based on HTTP, gRPC, and other L7 protocols.
  - `cilium-operator`: the operator that manages Cilium's lifecycle and configuration. It is largely responsible for managing the Cilium DaemonSet and other resources.
  - `hubble-relay`: the relay component that aggregates observability data from Cilium agents and makes it available for Hubble UI or CLI.

