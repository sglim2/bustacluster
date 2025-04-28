# deploy a heterogeneous k8s cluster with a custom scheduler

 * 1 controlplane node with 2 cpu and 4GB memory
 * 2 worker nodes
   * 1 worker node with 4 cpu and 4GB memory
   * 1 worker node with 8 cpu and 8GB memory

Since bustacluster does not have the functionality to deploy a cluster whose 
nodes have different cpu and memory configurations, we will deploy the nodes
individually.

# base image

Make sure that a suitable base image is available:

```
virt-builder --list
```

We assume that a rocky9 image is available (see git@github.com:sglim2/virt-localrepo.git for details on building a suitable image).


# deploy multiple individual basic VMs

```
# cd to the virt/basic directory
#
# create the controlplane node
CLUSTERNAME=k8s-cp_ IMAGENAME=rocky9 CLUSTEROSVARIANT=rocky9 CLUSTERRAM=4096 CLUSTERVCPUS=2 DISKSIZE=20G nVMS=1 bash deploy.sh
# create the worker1 node
CLUSTERNAME=k8s_worker1_ IMAGENAME=rocky9 CLUSTEROSVARIANT=rocky9 CLUSTERRAM=4096 CLUSTERVCPUS=4 DISKSIZE=20G nVMS=1 bash deploy.sh
# create the worker2 node
CLUSTERNAME=k8s_worker2_ IMAGENAME=rocky9 CLUSTEROSVARIANT=rocky9 CLUSTERRAM=8192 CLUSTERVCPUS=8 DISKSIZE=20G nVMS=1 bash deploy.sh
```


Copy the ```kubeadm-cluster-install.sh``` script, and other info, to the controlplane node, and set up vars to install k8s across the 3 nodes.

```
for i in k8s-cp_1 k8s_worker1_1 k8s_worker2_1 ; do virsh domifaddr --source=agent $i ; done  | grep eth0 | awk '{print $4}' |  sed 's|/.*||' | tr '\n' ' ' > k8s-ips.txt
for i in k8s-cp_1 k8s_worker1_1 k8s_worker2_1 ; do echo -n "$i " >> k8s-names.txt ; done

read -a IPS < k8s-ips.txt
read -a NODES < k8s-names.txt
scp k8s-ips.txt k8s-names.txt ../k8s-basic/kubeadm-cluster-install.sh root@${IPS[0]}:/root/

# set up /etc/hosts
ETCHOSTS=""
for ((i=0; i<${#IPS[@]}; i++)); do
    ETCHOSTS+=$'\n'"${IPS[$i]} ${NODES[$i]}"
done
for ip in "${IPS[@]}"; do
    echo "Updating /etc/hosts on $ip..."
    ssh "$ip" "echo \"$ETCHOSTS\" | tee -a /etc/hosts > /dev/null"
done


# passwordless ssh log-ins between VMs
ssh-keygen -t ed25519 -f "./id_ed25519" -N "" -C "k8s-clusterkey"

# push public key to all nodes
for ip in "${IPS[@]}"; do
    echo "Pushing key to $ip..."
    ssh root@${ip} "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    scp id_ed25519.pub root@${ip}:~/.ssh/id_ed25519.pub
    ssh root@${ip} "cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done


# push private key to all nodes
for ip in "${IPS[@]}"; do
    echo "Pushing private key to $ip..."
    scp id_ed25519 root@${ip}:~/.ssh/id_ed25519
    ssh root@${ip} "chmod 600 ~/.ssh/id_ed25519"

    ssh root@${ip} <<EOF
cat <<'EOT' >> ~/.ssh/config
Host *
    User root
    IdentityFile ~/.ssh/id_ed25519 
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    Identitiesonly yes
EOT
EOF
done


ssh root@${IPS[0]} <<'EOF'
#read -a IPS < k8s-ips.txt
#read -a NODES < k8s-names.txt
kubeVER=1.32.0 withCNI=cilium nodes="$(cat k8s-names.txt)" nodesIP="$(cat k8s-ips.txt)" bash /root/kubeadm-cluster-install.sh
EOF
```

```
# copy the kubeconfig to the local host
scp root@${IPS[0]}:/etc/kubernetes/admin.conf ./kubeconfig
export KUBECONFIG=${PWD}/kubeconfig
#
kubectl describe nodes | grep -E "cpu:|memory:"
```


# Build the custom scheduler

Strictly for test environments. You are about to run a privileged job with hostPath mounts to interface with the 
host's container runtime.

Use Kaniko to build the image, and then use ctr to import the image into containerd on the host (control-plane), to the ```k8s.io``` namespace of the containerd image cache.

```
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-build-import
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: "k8s-cp1"
      hostNetwork: true
      restartPolicy: Never

      initContainers:
      - name: clone-repo
        image: alpine:latest
        volumeMounts:
        - name: shared
          mountPath: /workspace
        command:
        - sh
        - -c
        - |
          apk add --no-cache git
          git clone https://bigr.bios.cf.ac.uk/sacim/kube-threadsched.git  /workspace/src

      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:latest
        volumeMounts:
        - name: shared
          mountPath: /workspace
        args:
        - "--dockerfile=/workspace/src/Dockerfile"
        - "--context=/workspace/src"
        - "--tarPath=/workspace/image.tar"
        - "--no-push"
        - "--destination=localimport.io/kube-threadsched/kube-threadsched:testing"

      - name: ctr-import
        image: alpine:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: shared
          mountPath: /workspace
        - name: containerd-socket
          mountPath: /run/containerd/containerd.sock
        command:
        - sh
        - -c
        - |
          apk add --no-cache curl containerd-ctr
       
          echo "[SIDECAR] Waiting for image.tar..."
          while [ ! -f /workspace/image.tar ]; do
            sleep 1
          done
         
          echo "[SIDECAR] Waiting for image.tar size to stabilize..."
          PREV_SIZE=0
          while true; do
            CUR_SIZE=$(stat -c %s /workspace/image.tar)
            if [ "$CUR_SIZE" -eq "$PREV_SIZE" ]; then
              echo "[SIDECAR] image.tar size stable at $CUR_SIZE bytes"
              break
            fi
            PREV_SIZE=$CUR_SIZE
            sleep 2
          done

          echo "[SIDECAR] image.tar found, importing..."
          ctr --namespace k8s.io --address /run/containerd/containerd.sock  image  import /workspace/image.tar --no-unpack --all-platforms --digests

      volumes:
      - name: shared
        emptyDir: {}
      - name: containerd-socket
        hostPath:
          path: /run/containerd/containerd.sock
EOF
```


# Attaching the custom scheduler

The kube-threadsched image is built and imported into the containerd image cache on the control-plane node, and named
```localimport.io/kube-threadsched/kube-threadsched:testing```.


```
cat >kube-namespacedthreadspread-scheduler.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dragonfly-namespacedthreadspread-scheduler-sa
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dragonfly-namespacedthreadspread-scheduler-role
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "pods/binding"]
  verbs: ["get", "list", "watch", "update", "patch", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dragonfly-namespacedthreadspread-scheduler-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dragonfly-namespacedthreadspread-scheduler-role
subjects:
- kind: ServiceAccount
  name: dragonfly-namespacedthreadspread-scheduler-sa
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dragonfly-namespacedthreadspread-scheduler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dragonfly-namespacedthreadspread-scheduler
  template:
    metadata:
      labels:
        app: dragonfly-namespacedthreadspread-scheduler
    spec:
      serviceAccountName: dragonfly-namespacedthreadspread-scheduler-sa
      nodeSelector:
        kubernetes.io/hostname: k8s-cp1
      containers:
      - name: dragonfly-namespacedthreadspread-scheduler
        image: localimport.io/kube-threadsched/kube-threadsched:testing
        imagePullPolicy: Always
EOF
```

# Test the scheduler

```

```


# remove the cluster

```
virsh destroy k8s-cp_1 
virsh destroy k8s_worker1_1 
virsh destroy k8s_worker2_1
virsh undefine k8s-cp_1 --remove-all-storage
virsh undefine k8s_worker1_1 --remove-all-storage
virsh undefine k8s_worker2_1 --remove-all-storage

rm id_ed25519.pub id_ed25519 k8s-ips.txt k8s-names.txt kubeconfig

``` 



