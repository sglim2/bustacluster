#!/bin/bash 
#
## deploy an nfs srever

CLUSTERNAME=${CLUSTERNAME:='nfs'}

IMAGENAME=${IMAGENAME:='rocky8-bustacluster'}
nVMS=${nVMS:=1}

source ../basic/deploy.sh

#================================================================================================

declare -a nodelist=($( seq -f "${CLUSTERNAME}%g" 1 ${nVMS} ))
echo "=================================="
echo "nodelist        = ${nodelist[@]}"
echo "IPS             = ${IPS[@]}"
echo "CLUSTERNAME     = $CLUSTERNAME"
echo "IMAGENAME       = $IMAGENAME"
echo "nVMS            = $nVMS"
echo "slurmVERSION    = $slurmVERSION"
echo "=================================="

for ip in ${IPS[*]}; do
  # remove any possible offending host keys from known_hosts
  ssh-keygen -R $ip
  # (re)populate known_hosts
  ssh -o StrictHostKeyChecking=no -i ../repo-builder/imgs/bustacluster-key root@$ip "echo -n" || true
done

echo "headnode: create a scratch volume"
qemu-img create -f qcow2 -o lazy_refcounts=on,preallocation=metadata  ${CLUSTERNAME}1-scratch.qcow2 100G

echo "headnode: attach scratch disk"
virsh attach-disk --domain ${CLUSTERNAME}1 --source ${PWD}/${CLUSTERNAME}1-scratch.qcow2 --target vdb --persistent

#================================================================================================
echo "headnode: mount the disks" 
ssh -o StrictHostKeyChecking=no -i ../repo-builder/imgs/bustacluster-key root@${IPS[0]} << EOF_headnode
parted /dev/vdb mklabel gpt
parted -a optimal /dev/vdb mkpart primary 0% 100%
mkfs.xfs  /dev/vdb1

mkdir -p /mnt/scratch
mount /dev/vdb1 /mnt/scratch
echo "UUID=$(blkid -o value /dev/vdb1 -s UUID) /mnt/scratch xfs defaults 0 0" >> /etc/fstab

EOF_headnode

#================================================================================================
echo "=================================="
echo "Deploying NFS"                                                                                            
echo "=================================="
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../nfs/playbook-nfs.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args=\"-o StrictHostKeyChecking=no\"
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../nfs/playbook-nfs.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args="-o StrictHostKeyChecking=no"


#================================================================================================

echo | tee instruct-${IMAGENAME}.txt
echo "To connect:" | tee -a instruct-${IMAGENAME}.txt
for ip in ${IPS[*]}; do
  echo "ssh -i ../repo-builder/imgs/footloose3-cluster-key -o StrictHostKeyChecking=no root@${ip}" | tee -a instruct-${IMAGENAME}.txt
done

echo
echo "To remove VMs:" | tee -a instruct-${IMAGENAME}.txt
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${IMAGENAME}${i}" | tee -a instruct-${IMAGENAME}.txt
  echo "virsh undefine ${IMAGENAME}${i} --remove-all-storage" | tee -a instruct-${IMAGENAME}.txt
done


