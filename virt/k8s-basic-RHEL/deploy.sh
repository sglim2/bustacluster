#!/bin/bash 
#

#================================================================================================
# kubeadm
podCIDR=${podCIDR:=192.168.192.0/19}
svcCIDR=${svcCIDR:=192.168.224.0/19}

CLUSTERNAME=${CLUSTERNAME:=k8s}
withCNI=${withCNI:=cilium}
withPROMETHEUS=${withPROMETHEUS:=0}
withMETRICS=${withMETRICS:=0}
kubeVER=${kubeVER:=1.32.0}
maxpods=${maxpods:=110}

nVMS=${nVMS:=3}
IMAGENAME=${IMAGENAME:='rocky9'}

source ../basic/deploy.sh

#================================================================================================
# prepare node with ansible
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../k8s-basic/playbook-k8s.yaml
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../k8s-basic/playbook-k8s.yaml 
#================================================================================================


declare -a nodelist=($( seq -f "${CLUSTERNAME}%g" 1 ${nVMS} ))
echo "=================================="
echo "nodelist        = ${nodelist[@]}"
echo "IPS             = ${IPS[@]}"
echo "CLUSTERNAME     = $CLUSTERNAME"
echo "IMAGENAME       = $IMAGENAME"
echo "nVMS            = $nVMS"
echo "withCNI         = $withCNI"
echo "maxpods         = $maxpods"
echo "withMETRICS     = $withMETRICS"
echo "withPROMETHEUS  = $withPROMETHEUS"
echo "kubeVER         = $kubeVER"
echo "=================================="

# The kubeadm-cluster-install.sh script can, theoretically, be run from any host with passwordless ssh access to all nodes
# However, we avoid running from the host OS in case it makes any undesirable changes to the host OS.
#
# The ansible playboos has already copied the kubeadm-cluster-install.sh script to the first node.
ssh root@${IPS[0]} <<EOF_kubeadm
kubeVER=$kubeVER withMETRICS=$withMETRICS withPROMETHEUS=$withPROMETHEUS CLUSTERNAME=$CLUSTERNAME withCNI=$withCNI maxpods=$maxpods nodes="$(echo ${IPS[@]})" nodesIP="$(echo ${IPS[@]})" /root/kubeadm-cluster-install.sh
EOF_kubeadm

#================================================================================================
# collect kube.config and cluster certs.
ssh root@${IPS[0]} "cat /etc/kubernetes/admin.conf" > kube.config

scp root@${IPS[0]}:/etc/kubernetes/pki/ca.{crt,key} .

echo "Cluster kube-config copied to local directory" | tee instruct-${CLUSTERNAME}.txt
echo "Cluster certs copied to local directory" | tee -a instruct-${CLUSTERNAME}.txt
echo "To use the cluster:" | tee -a instruct-${CLUSTERNAME}.txt
echo "  export KUBECONFIG=$(pwd)/kube.config" | tee -a instruct-${CLUSTERNAME}.txt

#================================================================================================

echo | tee -a instruct-${CLUSTERNAME}.txt
echo "To connect:" | tee -a instruct-${CLUSTERNAME}.txt
for ip in ${IPS[*]}; do
  echo "ssh root@${ip}" | tee -a instruct-${CLUSTERNAME}.txt
done

echo | tee -a instruct-${CLUSTERNAME}.txt
echo "To remove VMs:" | tee -a instruct-${CLUSTERNAME}.txt
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${CLUSTERNAME}${i}" | tee -a instruct-${CLUSTERNAME}.txt
  echo "virsh undefine ${CLUSTERNAME}${i} --remove-all-storage" | tee -a instruct-${CLUSTERNAME}.txt
done


