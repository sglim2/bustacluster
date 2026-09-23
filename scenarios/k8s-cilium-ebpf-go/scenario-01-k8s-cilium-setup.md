# K8S cilium with go/ebpf monitoring

Create a `k8s-basic` cluster with no CNI.

```
CLUSTERNAME=k8s-ebpf withCNI=cilium withPROMETHEUS=1 withMETRICS=1 IMAGENAME=rocky10 CLUSTEROSVARIANT=rocky10 CLUSTERRAM=4096 CLUSTERVCPUS=4 DISKSIZE=20G nVMS=3 bash deploy.sh
```

```
# e.g.
nodes=(192.168.122.164 192.168.122.217 192.168.122.245)
```

```kubectl get nodes``` should show the 3 nodes in Ready state.

Let's also enable the hubble relay. On the control plande node:

```
cilium hubble enable
# again,. wait for it to be ready
cilium status --wait
```

You should see output similar to:

```
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-relay             Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 1
                       clustermesh-apiserver    
                       hubble-relay             Running: 1
Cluster Pods:          3/3 managed by Cilium
Helm chart version:    1.19.3
Image versions         cilium             quay.io/cilium/cilium:v1.19.3@sha256:2e61680593cddca8b6c055f6d4c849d87a26a1c91c7e3b8b56c7fb76ab7b7b10: 3
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.36.6-1776000132-2437d2edeaf4d9b56ef279bd0d71127440c067aa@sha256:ba0ab8adac082d50d525fd2c5ba096c8facea3a471561b7c61c7a5b9c2e0de0d: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.19.3@sha256:205b09b0ed6accbf9fe688d312a9f0fcfc6a316fc081c23fbffb472af5dd62cd: 1
                       hubble-relay       quay.io/cilium/hubble-relay:v1.19.3@sha256:5ee21d57b6ef2aa6db67e603a735fdceb162454b352b7335b651456e308f681b: 1
```


The compomemts listed in the `cilium status` command are:
  - `cilium`: the main CNI component, responsible for networking and network policies.
  - `cilium-envoy`: the Envoy sidecar used for L7 policies and observability. This means that Cilium can enforce policies based on HTTP, gRPC, and other L7 protocols.
  - `cilium-operator`: the operator that manages Cilium's lifecycle and configuration. It is largely responsible for managing the Cilium DaemonSet and other resources.
  - `hubble-relay`: the relay component that aggregates observability data from Cilium agents and makes it available for Hubble UI or CLI.





