#!/bin/bash 
#

#================================================================================================
# kubeadm
podCIDR=${podCIDR:=192.168.192.0/19}
svcCIDR=${svcCIDR:=192.168.224.0/19}

CLUSTERNAME=${CLUSTERNAME:=lh}
withCNI=${withCNI:=cilium}
withPROMETHEUS=${withPROMETHEUS:=0}
withMETRICS=${withMETRICS:=0}
kubeVER=${kubeVER:=1.28.7}
maxpods=${maxpods:=110}


nVMS=${nVMS:=3}
IMAGENAME=${IMAGENAME:='rocky8-bustacluster'}

longhornVER=${longhornVER:=v1.6.2}
longhornDISKSIZE=${longhornDISKSIZE:=50G}

source ../k8s-basic/deploy.sh


#================================================================================================
# prepare node with ansible
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../k8s-longhorn/playbook.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args=\"-o StrictHostKeyChecking=no\"
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../k8s-longhorn/playbook.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args="-o StrictHostKeyChecking=no"
#================================================================================================


#================================================================================================
# add in single extra disks per VM
for i in $(seq 1 $nVMS); do
  qemu-img create -f qcow2 -o lazy_refcounts=on,preallocation=metadata ${CLUSTERNAME}${i}-mnt1.qcow2  ${longhornDISKSIZE}
  virsh attach-disk ${CLUSTERNAME}${i} --source $(pwd)/${CLUSTERNAME}${i}-mnt1.qcow2 --target vdb --persistent
done

for i in $(seq 1 $nVMS); do
  ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${IPS[$((i - 1))]} <<'EOF'
mkdir -p /var/lib/longhorn
parted -s /dev/vdb mklabel gpt
parted -a optimal /dev/vdb mkpart primary 0% 100%
mkfs.xfs /dev/vdb1
#
#
EOF
  ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${IPS[$((i - 1))]} <<'EOF'
echo "UUID=$(lsblk -no UUID /dev/vdb1) /var/lib/longhorn xfs defaults 0 0" >> /etc/fstab
systemctl daemon-reload
mount -a 
EOF
done

# control-plane only
ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${IPS[0]} "kubectl taint node ${CLUSTERNAME}1 node-role.kubernetes.io/control-plane:NoSchedule-"

# check longhorn is installable
ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${IPS[0]} <<EOF
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v1.1.2/scripts/environment_check.sh | bash
EOF

## get lonhorn yaml
ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${IPS[0]} <<EOF
curl -L https://raw.githubusercontent.com/longhorn/longhorn/${longhornVER}/deploy/longhorn.yaml | sed "/default-setting.yaml: |-/ a \    default-data-path: /var/lib/longhorn/" > longhorn.yaml
kubectl apply -f longhorn.yaml
EOF

#================================================================================================


echo | tee -a instruct-${CLUSTERNAME}.txt
echo "To connect:" | tee -a instruct-${CLUSTERNAME}.txt
for ip in ${IPS[*]}; do
  echo "ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${ip}" | tee -a instruct-${CLUSTERNAME}.txt
done

echo | tee -a instruct-${CLUSTERNAME}.txt
echo "To remove VMs:" | tee -a instruct-${CLUSTERNAME}.txt
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${CLUSTERNAME}${i}" | tee -a instruct-${CLUSTERNAME}.txt
  echo "virsh undefine ${CLUSTERNAME}${i} --remove-all-storage" | tee -a instruct-${CLUSTERNAME}.txt
done

