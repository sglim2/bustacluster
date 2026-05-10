# etcd Security Walkthrough (CKS-Oriented)

## Discover etcd: location, ports, certs

```
nodes=(192.168.122.97 192.168.122.24 192.168.122.49)
```

```
ssh ${nodes[0]}
```

In a kubeadm cluster, etcd is often a static pod running on the controlplane node.
```
ps aux | grep etcd
ls -l /etc/kubernetes/manifests/etcd.yaml
```
However, it doesn't have to be. It could be an external etcd cluster for instance.

### Inspect the static pod manifest 

```
cat /etc/kubernetes/manifests/etcd.yaml
```
This will show the etcd client port (default 2379) and peer port (default 2380). It will also show the command line arguments, which may include TLS configuration.
The client port is used for communication with the kube-apiserver and other clients, while the peer port is used for communication between etcd members in a cluster.

Some further useful information to look for in the manifest:

- listen-client-urls: This specifies the URLs that etcd listens on for client connections. It may include both HTTP and HTTPS URLs.
- data-dir: This specifies the directory where etcd stores its data. This is important for backup and recovery purposes.
- cert-file and --key-file: These specify the paths to the TLS certificate and key files used for secure communication. If these are present, it indicates that etcd is configured to use TLS for client communication.
- trusted-ca-file: This specifies the path to the CA certificate file that etcd uses to verify client certificates. If this is present, it indicates that etcd is configured to require client certificates for authentication.

Confirm the listening ports:

```
netstat -tunlp | grep etcd
```

### Inspect the TLS configuration

#### Certificate inspection

```
openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -text -noout
```

This will show the details of the TLS certificate, including the subject, issuer, validity period, and SANs (Subject Alternative Names). The SANs will indicate the DNS names and IP addresses that the certificate is valid for.

## Security Assessment

### Encryption at Rest

Check if etcd data is encrypted at rest. If this is configured it will likely be shown in the kube-apiserver manifest with the `--encryption-provider-config` flag, which points to a file that specifies the encryption providers and resources to encrypt.

```
# data is likely not encrypted at rest, for default kubeadm setup, so this usually returns fails..
grep encryption-provider-config /etc/kubernetes/manifests/kube-apiserver.yaml
# or more simply:
grep encryption /etc/kubernetes/manifests/kube-apiserver.yaml
```

Inspect the raw etcd DB:

```
strings /var/lib/etcd/member/snap/db 
```

This is often return lots of plain text, meaning the data is not encrypted at rest. **Note, this is an important CKS exam concept**.


### Encryption in Transit

Check if TLS is used:

```
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
```
simple result:
- https -> TLS is used for client communication
- http -> TLS is not used for client communication


#### What TLS means here

TLS ensures:
- Encrytion of traffic between clients and etcd, preventing eavesdropping.
- Server identity verification, ensuring clients are communicating with the legitimate etcd server.
- Optional client authentication, where clients can present certificates to authenticate themselves to the etcd server.

Without TLS:
- Data can be sniffed
- Credentials exposed
- MITM attacks possible



## Interacting with etcd (etcdctl)


Downwload and install the binaries directly from the github page:

```
curl -L https://github.com/etcd-io/etcd/releases/download/v3.6.11/etcd-v3.6.11-linux-amd64.tar.gz | tar -C /tmp -xzf - 
mv /tmp/etcd-v*/{etcd,etcdctl,etcdutl} /usr/local/bin/
```

Add data:
```
export ETCDCTL_API=3
etcdctl put funmessage "This message is not part of kubernetes"
```
This command fails. This is because the kubernetes-controlled etcd servcie requires TLS for encryption (by default), with valid client certs for authentication. These etcd manifest settings concerning this is:
```
--client-cert-auth=true
```
These required keys are available to us on the control-plane node..

```
etcdctl --endpoints=https://127.0.0.1:2379 --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --cacert=/etc/kubernetes/pki/etcd/ca.crt put course "This message is not part of kubernetes"
```

Get data (again cert flags are required):
```
etcdctl --endpoints=https://127.0.0.1:2379 --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --cacert=/etc/kubernetes/pki/etcd/ca.crt get course
``` 

### Exercise: On a node that is not already running etcd, download binaries and start an etcd service. Try interacting with this etcd instance with and without TLS. If the messages are unencrypted, try sniffing the traffic with tcpdump. Then enable TLS and repeat the process, observing the differences in the captured traffic.

Log out of the control-plane node and log into a worker node, which is not running etcd. Download and install the etcd binaries and start an etcd instance with TLS disabled:

```
ssh ${nodes[1]}
```
Then, on the worker node:
```
# obtain latest version from https://github.com/etcd-io/etcd/releases
curl -L https://github.com/etcd-io/etcd/releases/download/v3.6.11/etcd-v3.6.11-linux-amd64.tar.gz | tar -C /tmp -xzf -
cp /tmp/etcd-v*/{etcd,etcdctl,etcdutl} /usr/local/bin/
etcd &
# now interact with this etcd instance without TLS:
export ETCDCTL_API=3
etcdctl put message "This is an unencrypted message"
etcdctl get message
```
The message is stored and retrieved in plain text. Now, let's sniff the traffic with tcpdump:

```

```


Before meaving, tidy up and remove the etcd instance (be sure to do it on the worker node!):
```
killall etcd
```




