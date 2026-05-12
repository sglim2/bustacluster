# Authentication for k8s - x509 certs

x509 client certificates are a common method for authenticating to the Kubernetes API server. 

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

It is useful to understand that x509 authentication happens at the HTTPS/TLS layer before Kubernetes authorization decisions are made. 

Use curl with the client certificate and key:

```
curl \
  --cacert /etc/kubernetes/pki/ca.crt \
  --cert testuser.crt \
  --key testuser.key \
  "$APISERVER/api"
```

If authentication is successful, you should get a response from the API server. For example, a successful authenticated request to a permitted endpoint may return JSON similar to:

```
{
  "kind": "APIVersions",
  "versions": [
    "v1"
  ]
}
```

Try a protected endpoint:

```
curl \
  --cacert /etc/kubernetes/pki/ca.crt \
  --cert testuser.crt \
  --key testuser.key \
  "$APISERVER/api/v1/namespaces/default/svc"
```

This should fail with a permissions error, because the certificate is valid for authentication, but the user does not have authorization to list services in the default namespace. The response may look like:

```
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "svc is forbidden: User \"testuser\" cannot list resource \"svc\" in API group \"\" in the namespace \"default\"",
  "reason": "Forbidden",
  "details": {
    "kind": "svc"
  },
  "code": 403
}
```

This is useful because it proves that Kubernetes API access is ultimately HTTPS API access. 'kubectl' packages this up nicely, but the same authentication material can be used with lower-level tools.


## Inspect the certificate identity
Inspect the subject:
```
openssl x509 -in testuser.crt -noout -subject
```

Example output:
```
subject=CN = testuser, O = testgroup
```

Inspect issuer:
```
openssl x509 -in testuser.crt -noout -issuer
```

Expected issuer should match the Kubernetes cluster CA.

Inspect validity dates:
```
openssl x509 -in testuser.crt -noout -dates
```

Example:
```
notBefore=May 11 10:30:00 2026 GMT
notAfter=May 11 10:30:00 2027 GMT
```

Inspect the full certificate:
```
openssl x509 -in testuser.crt -text -noout
```

Useful fields to review:
```
Subject
Issuer
Validity
Public-Key
X509v3 extensions
Signature Algorithm
```

## Verify the certificate against the Kubernetes CA

Use OpenSSL to verify that the certificate chains back to the Kubernetes CA:
```
openssl verify -CAfile /etc/kubernetes/pki/ca.crt testuser.crt
```

Expected output:

```
testuser.crt: OK
```

If the certificate was signed by a different CA, verification would fail. For example:
```
error 20 at 0 depth lookup: unable to get local issuer certificate
error testuser.crt: verification failed
```

In Kubernetes terms, this would mean the API server would not trust the certificate for authentication.

## Create a certificate with multiple groups

In the context of Kubernetes, the Organization `O` field in the certificate subject can be used to specify multiple groups by including multiple `O` values. For example, in this CSR:

```
openssl req -new -key testuser.key -out testuser.csr -subj "/CN=testuser/O=group1/O=group2"
``` 

What this means is that the `user` associated with the certificate can be referenced in RBAC rules using either `group1` or `group2`. This allows for flexible group-based authorization, allowing the same user to be granted permissions through multiple group memberships.


Create a new key:

```
mkdir -p ~/k8s-client-certs/multigroup
cd ~/k8s-client-certs/multigroup
openssl genrsa -out multigroup.key 4096
chmod 600 multigroup.key
```

Create a CSR with multiple organizations (groups):

```
openssl req -new \
  -key multigroup.key \
  -out multigroup.csr \
  -subj "/CN=multigroup-user/O=devs/O=auditors/O=platform"
```

Sign it:

```
openssl x509 -req \
  -in multigroup.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out multigroup.crt \
  -days 365
```


Inspect the subject:

```
openssl x509 -in multigroup.crt -noout -subject
```

Expected output:

```
subject=CN = multigroup-user, O = devs, O = auditors, O = platform
```

Kubernetes will treat this approximately as:

```
Username: multigroup-user
Groups: devs, auditors, platform
```

This is relevant to RBAC because RoleBindings and ClusterRoleBindings can refer to either users or groups. For example:

```
kubectl create rolebinding example-group-rolebinding --role=dev-role --group=devs --namespace=default -oyaml --dry-run=client
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: example-group-rolebinding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: dev-role
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: devs
```


This would authorize any authenticated client certificate containing:
```
O=devs
```

## Important security implications

Possession of a trusted client certificate and private key is equivalent to possession of that Kubernetes identity. For example, anyone with these two files can authenticate as testuser:

```
testuser.crt
testuser.key
```

If those files are embedded into a kubeconfig, then the kubeconfig itself is a credential:

```
testuser.kubeconfig
```

Protect it accordingly:
```
chmod 600 testuser.kubeconfig
```

  * Do not store private keys in shared directories.
  * Do not copy kubeconfigs into container images.
  * Do not commit kubeconfigs, client certificates, or private keys into Git.
  * Do not email private keys.
  * Do not leave /etc/kubernetes/pki/ca.key accessible to non-privileged users.

The most sensitive file in this tutorial is:

```
/etc/kubernetes/pki/ca.key
```
Anyone with this key can sign a client certificate for any Kubernetes identity. For example, an attacker with access to the CA key could create a certificate with:

```
CN=attacker
O=system:masters
```
On many kubeadm clusters, `system:masters` is bound to the cluster-admin role. That would effectively grant full administrative access to the cluster.

For this reason, the Kubernetes CA private key should be treated as cluster-root-level secret material.

Private key files should generally be readable only by root or by the specific service account that needs them.


## Check API server client CA configuration

Inspect the API server manifest:
```
grep client-ca-file /etc/kubernetes/manifests/kube-apiserver.yaml
```

Expected kubeadm-style output:
```
 - --client-ca-file=/etc/kubernetes/pki/ca.crt
```

This controls which CA the API server uses to validate client certificates.

You can also check the running API server process:
```
ps aux | grep kube-apiserver | grep client-ca-file
```

This helps confirm the live configuration.


## Common failure modes

### 1. Certificate signed by the wrong CA
Symptom:
```
Unable to connect to the server: tls: failed to verify certificate
```
or:
```
Unauthorized
```
Check:
```
openssl verify -CAfile /etc/kubernetes/pki/ca.crt testuser.crt
```
If this does not return OK, the certificate was not signed by the CA trusted by the API server.

### 2. Wrong CN
If the certificate has the wrong common name, Kubernetes will authenticate the wrong username.

Check:
```
openssl x509 -in testuser.crt -noout -subject
```
For example:
```
subject=CN = wronguser, O = testgroup
```

Kubernetes will treat this as:
```
Username: wronguser
```

### 3. Missing group
If the certificate has no `O` field, the user will not be placed into the expected group.

Check:
```
openssl x509 -in testuser.crt -noout -subject
```
If you expected:
```
O = testgroup
```
but it is missing, then group-based RBAC bindings will not match.

### 4. Expired certificate
Check dates:
```
openssl x509 -in testuser.crt -noout -dates
```
If the certificate is expired, authentication will fail.

### 5. Kubeconfig points to the wrong cluster
Check the server endpoint:
```
kubectl config view --kubeconfig=testuser.kubeconfig --minify
```
If the kubeconfig points to a different API server, the certificate may not be trusted by that cluster.

### 6. Private key does not match certificate
Check that the private key and certificate match:
```
openssl x509 -noout -modulus -in testuser.crt | openssl md5
openssl rsa  -noout -modulus -in testuser.key | openssl md5
```
The hashes should match. If they do not match, the certificate and private key are not a pair.


## Signing Certificates using Kubernetes CSR API


So far, this scenario has signed the certificate directly using the Kubernetes CA key:

```
openssl x509 -req \
  -in testuser.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out testuser.crt \
  -days 365
```

This is can be useful, but it requires direct access to the CA private key - either sysadmin access to the cluster control plane, or distributing the CA key among the sysadmins.

Instead of manually signing certificates with the cluster CA key, Kubernetes provides a CertificateSigningRequest (CSR) API that allows users to submit CSRs for approval. 
This is a more secure and auditable way to manage client certificates, as it does not require direct access to the CA private key, or passing around signed certificates manually.

Create a new key and CSR:
```
mkdir -p ~/k8s-client-certs/csr-user
cd ~/k8s-client-certs/csr-user
openssl genrsa -out csr-user.key 4096
chmod 600 csr-user.key
openssl req -new -key csr-user.key -out csr-user.csr -subj "/CN=csr-user/O=csr-group"
```

Now create a Kubernetes CSR object using the contents of the CSR file:

```
cat > csr-user.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: csr-user
spec:
  request: $(base64 -w0 < csr-user.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000 # 1 year
  usages:
  - client auth
EOF
```

Apply the CSR to the cluster:
```
kubectl apply -f csr-user.yaml
```

View the csr:
```
kubectl get csr
```

It should be in the `Pending` state, waiting for approval. Approve the CSR:
```
kubectl certificate approve csr-user
```

The CSR kubernetes object will now be in the `Approved,Issued` state, and the certificate will be signed by the Kubernetes cluster CA. Retrieve the signed certificate:
```
kubectl get csr csr-user -o jsonpath='{.status.certificate}' | base64 -d > csr-user.crt
```

And inspect it if necessary:

```
openssl x509 -in csr-user.crt -text -noout
```

Once the `.crt` files is retrieved, it can be used, together with the corresponding `.key`, in a kubeconfig file for authentication, just like the manually signed certificate in the previous sections.


## x509 Certs and Security Relevance to Kubernetes

x509 certificates are worth understanding because they sit underneath several important Kubernetes security topics:
  * API server authentication
  * TLS trust relationships
  * kubeconfig security
  * private key protection
  * cluster CA protection
  * static pod API server configuration
  * distinguishing authentication failures from authorization failures
  * understanding how users and groups reach RBAC


## Useful commands summary

```
# Inspect certificate subject:
openssl x509 -in testuser.crt -noout -subject

# Inspect certificate issuer:
openssl x509 -in testuser.crt -noout -issuer

# Inspect certificate dates:
openssl x509 -in testuser.crt -noout -dates

# Inspect full certificate:
openssl x509 -in testuser.crt -text -noout

# Verify certificate against CA:
openssl verify -CAfile /etc/kubernetes/pki/ca.crt testuser.crt

# Check API server client CA:
grep client-ca-file /etc/kubernetes/manifests/kube-apiserver.yaml

# Check Kubernetes identity:
kubectl --kubeconfig=testuser.kubeconfig auth whoami

# Test access:
kubectl --kubeconfig=testuser.kubeconfig get pods

# Test with curl:
APISERVER=$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')
curl --cacert /etc/kubernetes/pki/ca.crt --cert testuser.crt --key testuser.key "$APISERVER/api"

# Find Kubernetes private keys:
find /etc/kubernetes/pki -type f -name "*.key" -exec ls -l {} \;
```

## Key learning points

  * x509 client certificates authenticate Kubernetes API clients.
  * The certificate CN becomes the Kubernetes username.
  * The certificate O fields become Kubernetes groups.
  * The client private key must remain private.
  * The Kubernetes CA private key is extremely sensitive.
  * A valid certificate does not automatically grant permissions.
  * A Forbidden error usually means authentication succeeded but authorization failed.
  * A kubeconfig containing embedded client key data is itself a sensitive credential.

Security conscious sysadmins should be comfortable inspecting certificate subjects, issuers, validity dates, key permissions, kubeconfig contents, and API server trust configuration.
