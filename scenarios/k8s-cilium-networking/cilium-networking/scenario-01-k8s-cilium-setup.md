# K8S cilium networking

Create a k8s-basic cluster with no CNI.

```
DISKSIZE=20G kubeVER=1.36.0 withCNI=none CLUSTERNAME=k8s-cilium IMAGENAME=ubuntu24.04 CLUSTEROSVARIANT=ubuntunoble nVMS=3 bash deploy-ubuntu.sh
```

```
# e.g.
nodes=(192.168.122.164 192.168.122.217 192.168.122.245)
```

```kubectl get nodes``` should show the 3 nodes in NotReady state.

Once available, log into the controlplane node and install Cilium and associated tools:

```
ssh ${nodes[0]}
```

```
# controlplane node
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Install:

```
cilium install --helm-set ipam.mode=kubernetes
# Wait for Cilium to be ready
cilium status --wait
```

Note that we have set the IPAM mode to kubernetes, which means that Cilium will use the Kubernetes API to manage IP addresses for pods, where Cilium allocates pod IPs from each node’s /24 CIDR range from Kubernetes-assigned PodCIDR.
This is simple, if a little inflexible.
```
kubectl get nodes -ojsonpath='{range .items[*]}{.spec.podCIDRs}{"\n"}{end}'
```

Further IPAM options are, and more will likely be added in the future - specificalliy for cloud environments:
- `ipam.mode=cluster-pool` — Cilium-managed pod CIDR allocation; more flexible than Kubernetes host-scope and supports multiple cluster CIDRs.
- `ipam.mode=multi-pool` — Cilium-managed multiple IP pools; useful when different nodes or workloads need different PodCIDR ranges.
- `ipam.mode=eni` — AWS-native IP allocation from ENIs; gives pods VPC-routable IPs without overlay networking.
- `ipam.mode=crd` — external/operator-driven IP allocation via Cilium CRDs; useful for custom environments.


Let's also enable the hubble relay:

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





