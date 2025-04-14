#!/bin/bash 
#

#================================================================================================

CLUSTERNAME=${CLUSTERNAME:=slurm}
slurmVERSION=${slurmVERSION:="23.11.10"}

nVMS=${nVMS:=3}
IMAGENAME=${IMAGENAME:='rocky9'}

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
  ssh root@$ip "echo -n" || true
done

echo "headnode: create a scratch volume"
qemu-img create -f qcow2 -o lazy_refcounts=on,preallocation=metadata  ${CLUSTERNAME}1-scratch.qcow2 100G

echo "headnode: attach scratch disk"
virsh attach-disk --domain ${CLUSTERNAME}1 --source ${PWD}/${CLUSTERNAME}1-scratch.qcow2 --target vdb --persistent

#================================================================================================
echo "headnode: mount the disks" 
ssh root@${IPS[0]} << EOF_headnode
parted /dev/vdb mklabel gpt
parted -a optimal /dev/vdb mkpart primary 0% 100%
mkfs.xfs  /dev/vdb1

mkdir -p /mnt/scratch
mount /dev/vdb1 /mnt/scratch
echo "UUID=$(blkid -o value /dev/vdb1 -s UUID) /mnt/scratch xfs defaults 0 0" >> /etc/fstab

EOF_headnode

#================================================================================================
# create ansible inventory file
echo "headnode: create ansible inventory file"

python_interpreter_rocky8=""
if [[ $osinfo == "rocky8" ]]; then
  python_interpreter_rocky8="ansible_python_interpreter=/usr/bin/python3.9"
fi

cat > inventory <<EOF_inventory
[headnode]
${CLUSTERNAME}1 ansible_host=${IPS[0]} ansible_user=root ${python_interpreter_rocky8}

[computenodes]
EOF_inventory

for i in $(seq 2 $nVMS) ; do
  echo "${CLUSTERNAME}${i} ansible_host=${IPS[$((i - 1))]} ansible_user=root ${python_interpreter_rocky8}" | tee -a inventory
done

# create the ansible playbook
echo "headnode: create the ansible playbook"
cat > playbook_control.yaml <<EOF_ansible
---
- name: Setup SLURM Cluster
  hosts: all
  vars:
    slurm_version: ${slurmVERSION}
    ansible_python_interpreter: /usr/bin/python3.9
  tasks:
    - include_tasks: playbook.yaml
EOF_ansible

# prepare node with ansible
#echo ansible-playbook -i $( echo "${IPS[*]}" ) ../slurm/playbook_control.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args=\"-o StrictHostKeyChecking=no\"
#ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../slurm/playbook_control.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args="-o StrictHostKeyChecking=no"
echo ansible-playbook -i inventory ../slurm/playbook_control.yaml 
ansible-playbook -i inventory ../slurm/playbook_control.yaml 

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


#================================================================================================


