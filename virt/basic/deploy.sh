#!/bin/bash 
#
## deploy a basic server


CLUSTERNAME=${CLUSTERNAME:='basic'}
IMAGENAME=${IMAGENAME:='rocky9'}
CLUSTEROSVARIANT=${CLUSTEROSVARIANT:-${IMAGENAME%%-*}}
CLUSTERRAM=${CLUSTERRAM:=8192}
CLUSTERVCPUS=${CLUSTERVCPUS:=6}
DISKRESIZE=${DISKRESIZE:=10}
nVMS=${nVMS:=1}

# create a vm image
for i in $(seq 1 $nVMS); do
  virt-builder ${IMAGENAME} --format qcow2 --root-password password:virtpassword -o ${CLUSTERNAME}${i}.qcow2
  qemu-img resize ${CLUSTERNAME}${i}.qcow2 +${DISKRESIZE} 
  qemu-img info ${CLUSTERNAME}${i}.qcow2
  virt-install --name ${CLUSTERNAME}${i} --memory ${CLUSTERRAM} --noautoconsole --vcpus ${CLUSTERVCPUS} --disk  ${CLUSTERNAME}${i}.qcow2 --import --os-variant ${CLUSTEROSVARIANT} --network bridge=virbr0
done

# wait for VMs to get an IP address, then we can continue
sleeptime=10
steplimit=30
istep=0
declare -a IPS=()
until [ ${#IPS[@]} -eq "$nVMS" ]
do
  echo "Checking for existence of VM IPs.."
  IPS=($(for i in $(seq 1 $nVMS) ; do virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | grep "eth0" | grep "ipv4" | awk '{print $4}' | awk -F'/' '{print $1}' | tr '\n' ' ' ; done ))
  echo "${IPS[*]}"
  sleep 10
  if [ $istep -ge "$steplimit" ] ; then
    echo "step limit reached while waiting for VM IPs" >&2
    exit 1
  fi
done


#================================================================================================
# set hostname(s)
echo "Setting hostname(s)"
for i in $(seq 1 $nVMS)
do
 hostIP=$(virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | grep "eth0" | grep "ipv4" | awk '{print $4}' | awk -F'/' '{print $1}' | tr '\n' ' ' )
 echo "${CLUSTERNAME}${i} ${hostIP}"
 ssh -i  ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${hostIP} hostnamectl set-hostname ${CLUSTERNAME}${i}
done

#================================================================================================
# set /etc/hosts
echo "Setting /etc/hosts"
for i in $(seq 1 $nVMS)
do
  connectIP=$(virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | grep "eth0" | grep "ipv4" | awk '{print $4}' | awk -F'/' '{print $1}' | tr '\n' ' ' )
  echo "${connectIP} ${CLUSTERNAME}${i}"
  for j in $(seq 1 $nVMS)
  do
    hostIP=$(virsh domifaddr ${CLUSTERNAME}${j} --source agent --full | grep "eth0" | grep "ipv4" | awk '{print $4}' | awk -F'/' '{print $1}' | tr '\n' ' ')
    ssh -i  ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${connectIP} "echo ${hostIP} ${CLUSTERNAME}${j} >> /etc/hosts"
  done
done

#================================================================================================
# prepare node with ansible
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../basic/playbook.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args=\"-o StrictHostKeyChecking=no\"
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../basic/playbook.yaml --private-key ../repo-builder/imgs/bustacluster-key --ssh-extra-args="-o StrictHostKeyChecking=no"


#================================================================================================

echo
echo "To connect:"
for ip in ${IPS[*]}; do
  echo "ssh -i ../repo-builder/imgs/bustacluster-key -o StrictHostKeyChecking=no root@${ip}"
done

echo
echo "To remove VMs:"
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${CLUSTERNAME}${i}"
  echo "virsh undefine ${CLUSTERNAME}${i} --remove-all-storage"
done


