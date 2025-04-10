#!/bin/bash

#
# some useful info before provisioning:
#  kubeVER: get latest releases from https://kubernetes.io/releases/
#
# calico: If local file ./calico.yaml exists, this will be used. Otherwise the
#         manifest https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml will be used.
#
# some useful test commands after provisioning:
#
# Examples:
#   # note see calico test for examples on downloading/editing the calico.yaml manifest
#   $> maxpods=220 withMETRICS=1 withCNI=calico withPROMETHEUS=v0.11.0 kubeVER=1.24.2 nodes="dfcomp1 dfcomp2" nodesIP="192.168.42.181 192.168.42.182" bash  ./kubeadm-cluster-install.sh
#
#   # cilium
#   $> maxpods=220 withMETRICS=1 withCNI=cilium withPROMETHEUS=0 kubeVER=1.27.2 nodes="dfcomp1 dfcomp2 dfcomp3 dfcomp4" nodesIP="192.168.42.181 192.168.42.182 192.168.42.183 192.168.42.184" bash ./kubeadm-cluster-install.sh
#
# iperf:
#   kubectl run rocky --image=rockylinux/rockylinux:8.4 --port=8000 -- bash -c "dnf install -y iperf3 ; iperf3 -s -p 8000"
#   kubectl expose pod rocky --port=8000 --type=NodePort
#   dnf install -y iperf3
#   iperf3 -c [host] -p [nodeport]
#
# ssh:
#   kubectl run ssh --image=bigr.bios.cf.ac.uk:4567/teaching/docker-ssh-x-bi3008-2021:ac121153 --port=22
#   kubectl expose pod ssh --port=22 --type=NodePort
#   ssh -i ~/cloudkey -o StrictHostKeyChecking=no -p [nodeport] centos@[host] dd if=/dev/zero bs=16k count=16k > /dev/null
#
#
#
#

# withCNI=[none,calico,cilium]
withCNI=${withCNI:=cilium}

# prometheus
# ==========
# Note: this method of prometheus install does not use persistent storage
#
# check https://github.com/prometheus-operator/kube-prometheus for compatibility.
# 
# k8s  prometheus
# 1.22   v1.10.0  
# 1.23   v1.10.0  v1.11.0  
# 1.24   v1.11.0
#withPROMETHEUS=[v0.10.0,v0.11.0,main]
withPROMETHEUS=${withPROMETHEUS:=0}

# metrics server
withMETRICS=${withMETRICS:=0}

# 1.21.5
# 1.22.2
kubeVER=${kubeVER:=1.23.7}
# get the major version, e.g. 1.23.7 -> 1.23 
#   (1.23 -> 1.23  also works with the below code)
kubeMAJVER=$(echo $kubeVER | cut -d. -f1,2)

# maxpods per kubelet
# (kubelet default is 110)
# 
maxpods=${maxpods:=110}


podCIDR=${podCIDR:=192.168.192.0/19}
svcCIDR=${svcCIDR:=192.168.224.0/19}


#####
# no default hostnames/IPs are set. Make sure they are defined before running this script
#
###declare -a nodes=(anax1.bios.cf.ac.uk anax2.bios.cf.ac.uk anax3.bios.cf.ac.uk)
###declare -a nodesIP=(192.168.2.221 192.168.2.222 192.168.2.223)
declare -a nodes=($nodes)
declare -a nodesIP=($nodesIP)


if [ -z "$nodes" ]; then 
echo "Error: array nodes is empty or not defined."
echo "Usage:"
echo "  nodes="hostname1 hostname2 [..hostnameN]" nodesIP="nodeIP1 nodeIP2 [..nodeIPN]" bash $0"
exit 1
fi

if [ -z "$nodesIP" ]; then 
echo "Error: array nodesIP is empty or not defined."
echo "Usage:"
echo "  nodes="hostname1 hostname2 [..hostnameN]" nodesIP="nodeIP1 nodeIP2 [..nodeIPN]"  bash $0"
exit 1
fi

#check nodes and nodesIP ranges match
if [ ! ${#nodes[@]} -eq ${#nodesIP[@]} ]; then
echo "Error: length of arrays nodes and nodesIP do not match"
echo "  nodes="hostname1 hostname2 [..hostnameN]" nodesIP="nodeIP1 nodeIP2 [..nodeIPN]" bash $0" 
exit 1
fi



# set up the default IP for the localhost - this is needed if running prometheus so correct endpoints (IPs/interfaces) are assigned
#for i in ${nodes[@]} ; do ssh $i echo 


# basic packages
echo "install base packages"
for i in ${nodes[@]} ; do ssh $i dnf install -y epel-release  git openssh-clients python3 python3-pip  bash-completion nfs-utils; done 

# Firewall from k8s internal networks =====================
for i in ${nodes[@]} ; do ssh $i "( systemctl enable --now firewalld )" ; done
for i in ${nodes[@]} ; do ssh $i "( firewall-cmd --zone=trusted --add-source=${podCIDR})" ; done
for i in ${nodes[@]} ; do ssh $i "( firewall-cmd --zone=trusted --add-source=${svcCIDR})" ; done
for i in ${nodes[@]} 
do
  for j in ${nodesIP[@]} 
  do 
    ssh $i "( firewall-cmd --zone=trusted --add-source=$j)" 
  done
done
for i in ${nodes[@]} ; do ssh $i "( firewall-cmd --runtime-to-permanent)" ; done
# ==========================================================

# for testing only
#echo "set trusted network"
#for i in ${nodes[@]} ; do ssh $i "( systemctl enable --now firewalld )" ; done
#for i in ${nodes[@]} ; do ssh $i "( firewall-cmd --set-default-zone trusted )" ; done


# disable swap 
echo disable swap
for i in ${nodes[@]} ; do ssh $i "(swapoff -a; sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab)" ; done

echo "install container runtime"
for i in ${nodes[@]} ; do 
ssh $i <<EOF_allnodes

dnf install -y yum-utils

echo "###################"
echo "disable SELINUX"
echo "###################"
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config


echo "###################"
echo "install k8s yum repo"
echo "###################"

# old repo location ( 2023 and earlier)
#sudo tee /etc/yum.repos.d/kubernetes.repo<<EOF
#[kubernetes]
#name=Kubernetes
#baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
#enabled=1
#gpgcheck=1
#repo_gpgcheck=1
#gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
#EOF

# new repo location - 2024 onwards
sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kubeMAJVER}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kubeMAJVER}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF


echo "###################"
echo "install k8s docker repo (for containerd)"
echo "###################"
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo "###################"
echo "install packages"
echo "###################"
dnf -y install epel-release vim git curl wget tar
dnf update -y 
dnf install -y containerd.io
dnf install -y kubelet-${kubeVER} kubeadm-${kubeVER} kubectl-${kubeVER} --disableexcludes=kubernetes
dnf install -y yum-utils device-mapper-persistent-data lvm2


sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

echo "###################"
echo "install containerd"
echo "###################"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# rocky9 now seems to need this setting..
#   tested with rocky9/k8s1.29.13
# (tells containerd to use systemd for managing control 
#  groups - which is what kubelet now expects by default)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl enable --now  containerd

systemctl enable --now kubelet


EOF_allnodes
done


echo "=================================="
echo "Install kubernetes with kubeadm on controller node"
echo "=================================="

#controllerIP=$(host $(hostname) | awk '{print $NF}')
controllerIP=${nodesIP[0]}
for i in ${nodes[0]} ; do ssh $i <<EOF_controller

kubeadm config images pull
echo "########"
echo kubeadm init --pod-network-cidr=${podCIDR} --service-cidr=${svcCIDR} --apiserver-advertise-address=${controllerIP}
kubeadm init --pod-network-cidr=${podCIDR} --service-cidr=${svcCIDR} --apiserver-advertise-address=${controllerIP}
echo "########"

# should really be a non-root user
mkdir -p \$HOME/.kube
cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config
chown \$(id -u):\$(id -g) \$HOME/.kube/config

EOF_controller
done


# get join command
JOINCOMMAND=$(ssh ${nodes[0]} kubeadm token create --print-join-command)

# join the additional nodes
for i in ${nodes[@]:1} ; do
  echo "=================================="
  echo "Joining node $i"
  echo "=================================="
  ssh $i $JOINCOMMAND
done


# remove taint
for i in ${nodes[0]} ; do ssh $i kubectl taint node --all node-role.kubernetes.io/control-plane:NoSchedule- ; done


#if [ ${withCNI} -eq "1"  ] ; then
if [ ${withCNI,,} == "calico"  ] ; then
  echo "=================================="
  echo "Deploying calico CNI"
  echo "=================================="
  # apply the cni
  if [[ -f "./calico.yaml" ]]; then
    # Note, this is often needed to help calico choose the correct host NICs.
    #
    # For example, the following...
    #   curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml | sed 's/^\([[:space:]]*\)  \(value: \"autodetect\"\)/\1  \2\n\1- name: IP_AUTODETECTION_METHOD\n\1  value: \"can-reach=8.8.8.8\"/' > calico.yaml
    # adds the lines..
    #             - name: IP_AUTODETECTION_METHOD
    #               value: "can-reach=8.8.8.8"
    #  
    echo "Found file calico.yaml, using this manifest."
    scp ./calico.yaml ${nodes[0]}:/tmp/calico.yaml
    ssh ${nodes[0]} kubectl apply -f /tmp/calico.yaml
  else
    ssh ${nodes[0]} kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml
  fi
  echo "=================================="
  echo "calico CNI deployed"
  echo hostname.....
  hostname
  echo "=================================="
fi

if [ ${withCNI,,} == "cilium"  ] ; then
  echo "=================================="
  echo "Deploying cilium CNI"
  echo "=================================="
  # apply the cni

  ssh ${nodes[0]} <<EOF_cilium
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
#
#
# Note: without the '--helm-set ipam.mode=kubernetes' flag, cilium will not honour the k8s podCIDR settings,
#       instead will default to it's own cidr range which is shared across the cluster (ipam.mode=kubernetes 
#       uses subset ranges for each cluster node)
cilium install --helm-set ipam.mode=kubernetes
EOF_cilium
 
  echo "=================================="
  echo "cilium CNI deployed"
  echo hostname.....
  hostname
  echo "=================================="
fi

for i in ${nodes[@]} ; do ssh $i "(echo maxPods: $maxpods >> /var/lib/kubelet/config.yaml ; systemctl restart kubelet )" ; done


#########################################
if [ ${withMETRICS} -eq "1"  ] ; then


ssh ${nodes[0]} <<EOF_metrics

curl -L -o metrics-server-components.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# no tls...
sed  's/args:/&\n        - --kubelet-insecure-tls/' metrics-server-components.yaml > metrics-server-components_edit.yaml 
kubectl apply -f metrics-server-components_edit.yaml

#
# You may need to trust the cluster cidr network, e.g. mallet method would be..
# [note the cluster-cidr can be obtained from file /etc/kubernetes/manifests/kube-controller-manager.yaml]
#  firewall-cmd --zone=trusted --add-source=[whatever]  [--permanent]

EOF_metrics

fi

#########################################
if [ "${withPROMETHEUS}x" != "0x"  ] ; then

ssh ${nodes[0]} <<EOF_prometheus

git clone https://github.com/prometheus-operator/kube-prometheus.git
cd kube-prometheus
#
# docs: docs/kube-prometheus-on-kubeadm.md
#   this changes the cluster config - allowing prometheus to work correctly, apparently
sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-controller-manager.yaml
sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-scheduler.yaml

export NAMESPACE='monitoring'
kubectl create namespace "$NAMESPACE"

kubectl apply --server-side -f manifests/setup
kubectl apply -f manifests/


echo "
Reaching Prometheus Endpoints:
=============================
kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090
Then access via http://localhost:9090

kubectl --namespace monitoring port-forward svc/grafana 3000
Then access via http://localhost:3000 and use the default grafana user:password of admin:admin (change imediately)

kubectl --namespace monitoring port-forward svc/alertmanager-main 9093
Then access via http://localhost:9093
=============================
"

EOF_prometheus

fi




