#!/bin/bash 
#
## deploy a basic server


CLUSTERNAME=${CLUSTERNAME:='basic'}
IMAGENAME=${IMAGENAME:='rocky10'}
CLUSTEROSVARIANT=${CLUSTEROSVARIANT:-${IMAGENAME%%-*}}
CLUSTERRAM=${CLUSTERRAM:=8192}
CLUSTERVCPUS=${CLUSTERVCPUS:=6}
DISKSIZE=${DISKSIZE:=10G}
nVMS=${nVMS:=1}

# create a vm image
for i in $(seq 1 $nVMS); do
  virt-builder ${IMAGENAME} --format qcow2 --root-password password:virtpassword --size=${DISKSIZE} -o ${CLUSTERNAME}${i}.qcow2
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
  IPS=($(for i in $(seq 1 $nVMS) ; do virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | awk '
      $1 != "lo" && $3 == "ipv4" {
        split($4, a, "/")
        print a[1]
        exit
      }
    ' ; done ))
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
 hostIP=$(virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | awk '
      $1 != "lo" && $3 == "ipv4" {
        split($4, a, "/")
        print a[1]
        exit
      }
    ')
 echo "${CLUSTERNAME}${i} ${hostIP}"
 ssh root@${hostIP} hostnamectl set-hostname ${CLUSTERNAME}${i}
done

#================================================================================================
# set /etc/hosts
echo "Setting /etc/hosts"
for i in $(seq 1 $nVMS)
do
  connectIP=$(virsh domifaddr ${CLUSTERNAME}${i} --source agent --full | awk '
      $1 != "lo" && $3 == "ipv4" {
        split($4, a, "/")
        print a[1]
        exit
      }
    ')
  echo "${connectIP} ${CLUSTERNAME}${i}"
  for j in $(seq 1 $nVMS)
  do
    hostIP=$(virsh domifaddr ${CLUSTERNAME}${j} --source agent --full | awk '
      $1 != "lo" && $3 == "ipv4" {
        split($4, a, "/")
        print a[1]
        exit
      }
    ')
    ssh root@${connectIP} "echo ${hostIP} ${CLUSTERNAME}${j} >> /etc/hosts"
  done
done

#================================================================================================
# prepare node with ansible
echo ansible-playbook -i $( echo "${IPS[*]}" ) ../basic/playbook.yaml 
ansible-playbook -i "$( IFS=$','; echo "${IPS[*]}", )"  ../basic/playbook.yaml 


#================================================================================================

echo
echo "To connect:"
for ip in ${IPS[*]}; do
  echo "ssh  root@${ip}"
done

echo
echo "To remove VMs:"
for i in $(seq 1 $nVMS); do
  echo "virsh destroy ${CLUSTERNAME}${i}"
  echo "virsh undefine ${CLUSTERNAME}${i} --remove-all-storage"
done


