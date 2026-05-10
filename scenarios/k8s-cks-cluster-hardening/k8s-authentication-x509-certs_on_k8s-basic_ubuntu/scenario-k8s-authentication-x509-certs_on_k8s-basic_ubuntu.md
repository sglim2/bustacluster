# Authentication for k8s - x509 certs

Use x509 certs for authentication to the kube-apiserver. This is a common method for authenticating to the Kubernetes API server, especially for service accounts. X509 certs are also perfectly valid for human
user authentiction, but for managed Kubernetes services, it is often more common to use other authentication methods such as cloud provider IAM roles or OIDC tokens.


```
# e.g.
nodes=(192.168.122.48 192.168.122.240 192.168.122.44)
```

```
ssh ${nodes[0]}
```

For x509 client certs, Kubernetes uses the certificate `Common Name` (`CN`) as the Kubernetes username, and the certificate `Organization` (`O`) fields as Kubernetes groups. 
In kubeadm clusters, the main Kubernetes CA material is normally under /etc/kubernetes/pki, which is kubeadm’s default certificate directory. 

The important parts are:

  * Client private key  -> stays with the client
  * Client certificate  -> sent to the API server during TLS auth
  * Cluster CA cert     -> trusted by the API server
  * Cluster CA key      -> used to sign trusted client certificates

In a kubeadm cluster, the API server is already configured to trust certificates signed by the Kubernetes cluster CA. That CA is usually:

```
/etc/kubernetes/pki/ca.crt
/etc/kubernetes/pki/ca.key
```
The ca.crt file is public trust material. It can be embedded into kubeconfig files.

The ca.key file is extremely sensitive. Anyone with it can sign a certificate for any Kubernetes identity, including privileged identities.



## Create a client certificate and key

We will create an x509 cert for a user named `testuser` in the group `testgroup`. 
```
CN=testuser
O=testgroup
```

Kubernetees will interpret this as 
```
Username: testuser`
Groups: testgroup
```

The certificate will be signed by the Kubernetes cluster CA, so it will be trusted by the API server for authentication.

While authenticstion will be configured for `testuser`, authorization will be met elsewhere. That is, RBAC rules will need to be created to allow `testuser` to perform actions in the cluster. This is a separate step from authentication, and is not covered in this scenario.

Create the client key
```
mkdir -p ~/k8s-client-certs/testuser
cd ~/k8s-client-certs/testuser
openssl genrsa -out testuser.key 4096
chmod 600 testuser.key
```

This creates the client private key `testuser.key`. This key should be kept private, and delivered to the any human users securely. It should not be shared or exposed. 

Create the Certificate Signing Request (CSR)
```
openssl req -new -key testuser.key -out testuser.csr -subj "/CN=testuser/O=testgroup"
```

The CSR provides enough information for the CA to sign the certificate, with identity:
```
CN=testuser
O=testgroup
```
The CSR will not include the client key, only the public key derived from it, and the requested identity information.

Sign the client certificate with the Kubernetes cluster CA
```
openssl x509 -req -in testuser.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out testuser.crt -days 365
```

This creates the client certificate `testuser.crt`, which is signed by the Kubernetes cluster CA, so is therefore trusted by the api-server for this cluster. The certificate will be valid for 365 days, and will use SHA-256 for signing. 
inspect the crt with:
```
openssl x509 -in testuser.crt -text -noout
``` 
..and look for the Subject field, which should show the CN and O values we specified.
```












Create a client certificate and key for authentication to the kube-apiserver. The kubernetes cluster itself will have a certificate authority (CA) that can be used to sign the client certificate.

```
# Generate a private key for the client certificate
openssl genrsa -out client.key 2048
# Create a certificate signing request (CSR) for the client certificate
openssl req -new -key client.key -out client.csr -subj "/CN=client/O=group"
# Sign the client certificate with the Kubernetes cluster's CA
openssl x509 -req -in client.csr -CA /path/to/ca.crt -CAkey /path/to/ca.key -CAcreateserial -out client.crt -days 365
```
