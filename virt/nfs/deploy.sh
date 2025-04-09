#!/bin/bash 
#
## deploy an nfs srever

CLUSTERNAME=${CLUSTERNAME:='nfs'}

IMAGENAME=${IMAGENAME:='rocky9'}
nVMS=${nVMS:=1}
SCRATCHDISKSIZE=${SCRATCHDISKSIZE:=30G}

source ../basic/deploy.sh

#================================================================================================

declare -a nodelist=($( seq -f "${CLUSTERNAME}%g" 1 ${nVMS} ))
echo "=================================="
echo "nodelist        = ${nodelist[@]}"
echo "IPS             = ${IPS[@]}"
echo "CLUSTERNAME     = $CLUSTERNAME"
echo "IMAGENAME       = $IMAGENAME"
echo "nVMS            = $nVMS"
echo "=================================="

echo "nfs: create a new data volume"
qemu-img create -f qcow2 -o lazy_refcounts=on,preallocation=metadata  ${CLUSTERNAME}1-data.qcow2 ${SCRATCHDISKSIZE}

echo "nfs: attach data disk"
virsh attach-disk --domain ${CLUSTERNAME}1 --source ${PWD}/${CLUSTERNAME}1-data.qcow2 --target vdb --persistent

#================================================================================================
echo "nfs: mount the disks" 
ssh root@${IPS[0]} << EOF_nfs
parted /dev/vdb mklabel gpt
parted -a optimal /dev/vdb mkpart primary 0% 100%
mkfs.xfs  /dev/vdb1

mkdir -p /mnt/data
mount /dev/vdb1 /mnt/data
echo "UUID=$(blkid -o value /dev/vdb1 -s UUID) /mnt/data xfs defaults 0 0" >> /etc/fstab

EOF_nfs

#================================================================================================
echo "=================================="
echo "Deploying NFS"                                                                                            
echo "=================================="
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../nfs/playbook-nfs.yaml 
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../nfs/playbook-nfs.yaml 


#================================================================================================

echo | tee instruct-${CLUSTERNAME}.txt
echo "To connect:" | tee -a instruct-${CLUSTERNAME}.txt
for ip in ${IPS[*]}; do
  echo "ssh root@${ip}" | tee -a instruct-${CLUSTERNAME}.txt
done

echo
echo "To remove VMs:" | tee -a instruct-${CLUSTERNAME}.txt
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${CLUSTERNAME}${i}" | tee -a instruct-${CLUSTERNAME}.txt
  echo "virsh undefine ${CLUSTERNAME}${i} --remove-all-storage" | tee -a instruct-${CLUSTERNAME}.txt
done


