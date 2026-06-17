```
#> cd virt/k8s-basic
#> DISKSIZE=20G kubeVER=1.36.0 withCNI=cilium CLUSTERNAME=k8s-ubuntu IMAGENAME=ubuntu24.04 CLUSTEROSVARIANT=ubuntunoble nVMS=3 bash deploy-ubuntu.sh
#> cat instruct-k8s-ubuntu.txt 
Cluster kube-config copied to local directory
Cluster certs copied to local directory
To use the cluster:
  export KUBECONFIG=/home/sacim/repos/bustacluster/virt/k8s-basic/kube.config

To connect:
ssh root@.........
ssh root@.......
ssh root@....
.
.
.
```



