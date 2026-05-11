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

This creates the client certificate `testuser.crt`, which is signed by the Kubernetes cluster CA, so is therefore trusted by the api-server for this cluster. The certificate will be valid for 365 days.

Inspect the crt with:
```
openssl x509 -in testuser.crt -text -noout
``` 
..and look for the `Subject` field, which should show the `CN` and `O` values we specified.


## Use the client certificate with kubectl

At this point we have created three files:

```
testuser.key
testuser.csr
testuser.crt
```

The CSR was only needed for certificate creation. For day-to-day authentication to Kubernetes, the useful files are:
```
testuser.key : the client private key, which should be kept secure and private
testuser.crt : the client certificate, which can be shared with the API server for authentication
ca.crt : the cluster CA certificate, which is needed to verify the API server's identity during TLS handshake, and can be embedded in kubeconfig files
```

Kubernetes client-certificate authentication works by presenting the client certificate during the TLS connection to the API server. The API server checks that the certificate was
signed by a trusted `CA`, then maps the certificate subject into a Kubernetes identity. The `CN` becomes the username and the `O` field becomes the group membership. 
Kubernetes then passes that identity to the authorization layer, such as RBAC. 

Authentication and authorization are separate, so a valid certificate proves that `testuser` is a real Kubernetes identity, but it does not automatically grant any permissions.

### Create a kubeconfig for the x509 user

A kubeconfig contains:
  * cluster details
  * user credentials
  * context information tying the user to the cluster

Create a dedicated kubeconfig for testuser:

```
APISERVER=$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')
echo "$APISERVER"
```

Now create the kubeconfig. All of the following 4 commands are required to set up a working kubeconfig file.

The following sets up the server credentials only:

```
kubectl config set-cluster testcluster \
  --server="$APISERVER" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig=testuser.kubeconfig
```

Now add the x509 user credentials:

```
kubectl config set-credentials testuser \
  --client-certificate=testuser.crt \
  --client-key=testuser.key \
  --embed-certs=true \
  --kubeconfig=testuser.kubeconfig
```

Create a context:

```
kubectl config set-context testuser@testcluster \
  --cluster=testcluster \
  --user=testuser \
  --kubeconfig=testuser.kubeconfig
```

Set the context as default:

```
kubectl config use-context testuser@testcluster \
  --kubeconfig=testuser.kubeconfig
```

This is now a complete kubeconfig file that can be used to authenticate to the Kubernetes API server as `testuser` using the x509 client certificate.

Inspect the kubeconfig:

```
kubectl config view --kubeconfig=testuser.kubeconfig
```

Because `--embed-certs=true` was used, the certificate and key data are embedded directly in the kubeconfig as base64-encoded values:

```
client-certificate-data: ...
client-key-data: ...
certificate-authority-data: ...
```

This is convenient for portability, but it also means the kubeconfig now contains private key material. Treat this file as sensitive.

Set safer permissions:

```
chmod 600 testuser.kubeconfig
```

## Test Authentication with the new kubeconfig

Try to query the cluster using the new kubeconfig:

```
kubectl get nodes --kubeconfig=testuser.kubeconfig
```

THis should fail with a permissions error. Something like:

```
Error from server (Forbidden): nodes is forbidden: User "testuser" cannot list resource "nodes" in API group "" at the cluster scope
```

This is expected, Kubernetes recognised the certificate identity as testuser, but RBAC has not granted that user permission to list pods.

## Confirm the Kubernetes identity

Use kubectl `auth whoami`:

```
kubectl --kubeconfig=testuser.kubeconfig auth whoami
```

Expected output is:

```
ATTRIBUTE                                           VALUE
Username                                            testuser
Groups                                              [testgroup system:authenticated]
Extra: authentication.kubernetes.io/credential-id   [X509SHA256=........]
```

Note: Kubernetes also commonly adds authenticated users to the built-in group `system:authenticated`.

## Brief RBAC test

It is useful to prove that the certificate identity can be authorized. Create a very limited Role allowing testuser to list pods in the default namespace:

```
kubectl create role testuser-pod-reader --verb=get,list,watch --resource=pods --namespace=default
```

Bind the Role to the x509 user:

```
kubectl create rolebinding testuser-pod-reader-rolebinding --role=testuser-pod-reader --user=testuser --namespace=default
```

Now try:

```
kubectl --kubeconfig=testuser.kubeconfig get pods -n default
```

You should witness a successful response, even if no pods are present. Test witha different kubernetes resouce:

```
kubectl --kubeconfig=testuser.kubeconfig get secrets -n default
```

The command is expected to fail with a permissions error, because the Role does not allows access to secrets:


## Test the Certificate directly with curl







