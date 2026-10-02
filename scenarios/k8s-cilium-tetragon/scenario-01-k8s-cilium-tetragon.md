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


## Tetragon

The goal is to record user activity in a pod (acting as an eductional linux playground) 
and send the events to a central location for analysis.

The following diagram illustrates the architecture:

```

             one Kubernetes node

 Student workload
      │
      ├─────────────────────────┐
      │                         │
      ▼                         ▼
 Tetragon/eBPF            Linux taskstats
      │                         │
 process_exec                   │ process exit
 process_exit                   │ AGGR_TGID
      │                         │
      ▼                         ▼
 /var/run/tetragon/       Generic Netlink
 tetragon.sock                  │
      │                         │
      └─────────┐   ┌───────────┘
                ▼   ▼
         resource-accounting
                │
       PID/TGID correlation
                │
                ▼
        Tetragon exec_id
        + Kubernetes identity
        + final taskstats
                │
                ▼
             JSON
             stdout

```

At this point we should check that the nodes expose the kernel BTF:
(BTF a translator from kernel info to ebpf parsable data - or more specifically, informs ebpf programs about the kernel data structures and types, allowing them to interact with the kernel in an efficient and type-safe manner.)

```
for i in $(kubectl get nodes -o name); 
do 
  kubectl debug $i -it --image=busybox -- chroot /host ls -l /sys/kernel/btf/vmlinux
done
```

You may, or may not, see the `vmlinux` file. If you don't see it, it may just be due to the container exiting before establising a valid stdout connection 
(Or, you may need to install the kernel-debuginfo package on each node). Check to see the the problem was just timing, by checking the logs of the debug pod:

```
# ordering is handy, collect the final few lines...
kubectl get pods --sort-by=.metadata.creationTimestamp | grep node-debugger-k8s-ebpf
#
# then check the logs of the relevant pods:
kubectl logs [podname]
```
You should see the `vmlinux` file in the logs. If not, you may need to install the kernel-debuginfo package on each node.



## Install Tretragon

```
helm repo add cilium https://helm.cilium.io
helm repo update
# get versions
# helm search repo cilium/tetragon --versions | head
# helm install tetragon cilium/tetragon --namespace kube-system --version <TESTED_VERSION>
# or install the latest version:
helm install tetragon cilium/tetragon --namespace kube-system
#
# check 
kubectl rollout status -n kube-system ds/tetragon
```

Enable prometheus integration:
```
helm upgrade tetragon cilium/tetragon --namespace kube-system -reuse-values --set tetragon.prometheus.serviceMonitor.enabled=true --set tetragonOperator.prometheus.serviceMonitor.enabled=true
```

## Deploy a linux-playground to monitor

First create a suitable OCI image to deploy. We will, for test purposes only, create an image
that will run as a non-root user, with hardcoded uid/gid of 2001.

```
##
## Run on the k8s controlplane node
##
dnf install -y podman
#
podman build -t stress-ng:ubuntu24.04 -f - . <<'EOF'
FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      stress-ng \
      bash \
      procps \
      coreutils \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 2001 student \
 && useradd -m -u 2001 -g 2001 -s /bin/bash student

USER 2001:2001
WORKDIR /home/student

CMD ["sleep", "infinity"]
EOF
#
podman save --format oci-archive -o stress-ng.tar stress-ng:ubuntu24.04
#
#copy to other k8s nodes
rsync stress-ng.tar k8s-ebpf2:~/
rsync stress-ng.tar k8s-ebpf3:~/
# 
#make available to k8s 
ctr -n k8s.io images import stress-ng.tar
ssh k8s-ebpf2 "ctr -n k8s.io images import stress-ng.tar"
ssh k8s-ebpf3 "ctr -n k8s.io images import stress-ng.tar"
```

Launch a linux-playground pod:

```
kubectl create namespace linux-playground
```

```
cat > linux-playground.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: linux-playground
  namespace: linux-playground
  labels:
    app: linux-playground
    bios.cf.ac.uk/accounting: "enabled"
    bios.cf.ac.uk/course: tutorial
    bios.cf.ac.uk/workload-type: ssh
    bios.cf.ac.uk/environment: student01
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 2001
    runAsGroup: 2001
    fsGroup: 2001
  containers:
  - name: linux-playground
    image: localhost/stress-ng:ubuntu24.04
    imagePullPolicy: Never
    command:
    - sleep
    - infinity
    securityContext:
      privileged: false
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
  dnsPolicy: ClusterFirst
  restartPolicy: Always
EOF
```

```
kubectl apply -f linux-playground.yaml
```

### run some workloads on the linux-playground pod

```
kubectl exec -n linux-playground -it linux-playground -- bash
```

Some useful commands to run inside the pod:

```
id
stress-ng --cpu 2 --vm 2 --vm-bytes 1G -t 1m
/bin/sh -c 'exit 42'
ls /this/path/does/not/exist
sha256sum /etc/passwd
sleep 3
```

Assuming none of the above commands kill the pod (!), in a separate terminal you can now inspect the tetragon events:

```
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout --max-log-requests=10 -f |
jq -c '
  if .process_exec then
    select(.process_exec.process.pod.namespace == "linux-playground") |
    {
      event: "exec",
      exec_id: .process_exec.process.exec_id,
      uid: .process_exec.process.uid,
      pid: .process_exec.process.pid,
      binary: .process_exec.process.binary,
      arguments: .process_exec.process.arguments,
      cwd: .process_exec.process.cwd,
      start_time: .process_exec.process.start_time,
      namespace: .process_exec.process.pod.namespace,
      pod: .process_exec.process.pod.name,
      container: .process_exec.process.pod.container.name
    }
  else
    empty
  end
'
```

These logs are in the handy JSON format, so we process them to show only what we want.


Tetragon's normal process execution event contains fields including:

```
process.exec_id
process.pid
process.uid
process.cwd
process.binary
process.arguments
process.start_time

parent process information

pod.namespace
pod.name
pod.container
pod.labels
```

A typical result would look like:

```
{"event":"exec","exec_id":"azhzLWVicGYyOjQ3NDgyOTQ2Mjk3MDc6NTgzNA==","uid":2001,"pid":5834,"binary":"/usr/bin/id","arguments":null,"cwd":"/home/student","start_time":"2026-09-27T23:02:52.864357575Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
{"event":"exec","exec_id":"azhzLWVicGYyOjQ3NTIxMjAwMjE0Njg6NTgzNQ==","uid":2001,"pid":5835,"binary":"/usr/bin/stress-ng","arguments":"--cpu 2 --vm 2 --vm-bytes 1G -t 1m","cwd":"/home/student","start_time":"2026-09-27T23:02:56.689749186Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
{"event":"exec","exec_id":"azhzLWVicGYyOjQ4MTQzMDQxMTQ4ODQ6NTg0OA==","uid":2001,"pid":5848,"binary":"/bin/sh","arguments":"-c \"exit 42\"","cwd":"/home/student","start_time":"2026-09-27T23:03:58.873842683Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
{"event":"exec","exec_id":"azhzLWVicGYyOjQ4MTkxODIzNzg2ODE6NTg1MQ==","uid":2001,"pid":5851,"binary":"/usr/bin/ls","arguments":"--color=auto /this/path/does/not/exist","cwd":"/home/student","start_time":"2026-09-27T23:04:03.752106450Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
{"event":"exec","exec_id":"azhzLWVicGYyOjQ4MjI4ODA1NDI1ODk6NTg1NA==","uid":2001,"pid":5854,"binary":"/usr/bin/sha256sum","arguments":"/etc/passwd","cwd":"/home/student","start_time":"2026-09-27T23:04:07.450270337Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
{"event":"exec","exec_id":"azhzLWVicGYyOjQ4MjU4NzAzMjk5ODQ6NTg1NQ==","uid":2001,"pid":5855,"binary":"/usr/bin/sleep","arguments":"3","cwd":"/home/student","start_time":"2026-09-27T23:04:10.440057712Z","namespace":"linux-playground","pod":"linux-playground","container":"linux-playground"}
```

We can extend this useful information by also looking at the process exit events. The following command will show both exec and exit events:

```
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout --max-log-requests=10 -f |
jq -c '
  if .process_exit then
    select(.process_exit.process.pod.namespace == "linux-playground") |
    {
      event: "exit",
      exec_id: .process_exit.process.exec_id,
      uid: .process_exit.process.uid,
      pid: .process_exit.process.pid,
      binary: .process_exit.process.binary,
      start_time: .process_exit.process.start_time,
      exit_status: .process_exit.status,
      signal: .process_exit.signal,
      namespace: .process_exit.process.pod.namespace,
      pod: .process_exit.process.pod.name
    }
  else
    empty
  end
'
```


And a typical output would be something like:

```
{"event":"exit","exec_id":"azhzLWVicGYyOjUxNzE5ODk1MjI5Mjg0MjoxMjc4OTk=","uid":2001,"pid":127899,"binary":"/usr/bin/sleep","start_time":"2026-09-29T10:12:25.582357929Z","exit_status":null,"signal":null,"namespace":"linux-playground","pod":"linux-playground"}
{"event":"exit","exec_id":"azhzLWVicGYyOjUxNzM0MTcwNjYzNTcyMToxMjc5MTk=","uid":2001,"pid":127919,"binary":"/usr/bin/stress-ng","start_time":"2026-09-29T10:14:48.336701084Z","exit_status":null,"signal":null,"namespace":"linux-playground","pod":"linux-playground"}
```

Each tetragon pod will have 2 containers:

```
kubectl get pod tetragon-h7fdt -n kube-system -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}'
export-stdout
tetragon
```




### Filling the gaps

Tetragon already provides a lot of information, but it does not provide many of the resource accounting data that we may be interested in. 
Tetragon's built-in lifecycle events tell us what happened (who, when, where), but does not expose a complete final resource-consumption (how much). For instance,
we may want to know information such as:

```
cpu_user_ns
cpu_system_ns
cpu_total_ns
max_rss_bytes
read_bytes
write_bytes
read_syscalls
write_syscalls
```

This information would give use a more complete picture of the resource usage of each process, which is important for our target of performance analysis and optimization.

This is where Tetragon stops being the complete solution. However, we can expand on Tetragon's `runtime security observability`, with our own `resource accounting` solution, which will be more akin to traditional `performance monitoring` tools.












