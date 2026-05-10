# Authentication for k8s - Static Token Files

Static token files are a simple authentication mechanism in Kubernetes that allows you to create static tokens for users or service accounts. These 
tokens can be used to authenticate to the Kubernetes API server. This method is often used for testing, development, or in scenarios where a 
simple authentication mechanism is sufficient. Static tokens are not typically used in production environments due to security concerns.


## Adjust a runnng kubeadm cluster to use static token files for authentication. 

```
e.g.
nodes=(192.168.122.48 192.168.122.240 192.168.122.44)
```

```
ssh ${nodes[0]}
```

Create the token file with the following content:

```
# the 'system:masters' group grants full admin privileges to the user associated with the token.
echo "my-static-token,admin,admin,system:masters" | sudo tee /etc/kubernetes/static-tokens.csv
```

Edit the API server manifest file on the control plane node, and add the following flag to the command section:

```
--token-auth-file=/etc/kubernetes/static-tokens.csv
```

Add the necessary volume and volume mount to the API server manifest file:

```
    volumeMounts:
    - mountPath: /etc/kubernetes/static-tokens.csv
      name: static-token-file
      readOnly: true
#
  volumes:
  - hostPath:
      path: /etc/kubernetes/static-tokens.csv
      type: File
    name: static-token-file
```

The `kube-apiserver` should auto-restart.

If the cluster is HA, repeat the above steps on all control plane nodes.

Note, the above changes would likely not survice a cluster upgrade.

Additionally, these are 'static' tokens, meaning th

a few things to keep in mind:
  * The tokens are read on kube-apiserver startup, so any changes to the token file would require a restart of the API server to take effect.
  * They do not have an expirations, and are not auto-rotated (but thwen again, i don't think anything on k8s is auto-rotated?).
  * Authentication and authorization are separate. The token proves “this is user admin”; RBAC still decides what admin can do.
  * Static tokens are long-lived bearer secrets. Anyone with the token has that user’s access until you remove the token and restart the API server. For real clusters, prefer client certificates, OIDC, webhook token auth, or short-lived service account tokens.


## Testing the static token authentication

```
curl -k -H "Authorization: Bearer my-static-token" https://127.0.0.1:6443/
curl -k -H "Authorization: Bearer my-static-token" https://127.0.0.1:6443/api
```

Test changing the token password:
```
curl -k -H "Authorization: Bearer my-static-tokeN" https://127.0.0.1:6443/
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
```

### contexts

Instead of typing the token in the curl command, you can also create a kubeconfig `context` that uses the static token for authentication:

```
# kubectl config set-credentials static-admin --token=my-static-token
# kubectl config set-context static-admin --cluster=kubernetes --user=static-admin 
# kubectl config get-contexts
CURRENT   NAME                          CLUSTER      AUTHINFO           NAMESPACE
*         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin   
          static-admin                  kubernetes   static-admin 
kubectl --context=static-admin get nodes
# success
```


```
apiVersion: v1
kind: Config
clusters:
- name: my-cluster
  cluster:
    server: https://127.0.0.1:6443
    certificate-authority-data: <base64-encoded-ca-cert>
```

### kubeconfig file

Additionally a kubeconfig file can be created with the static token for authentication:

```
TOKEN="my-static-token"
APISERVER="https://[${nodes[0]}]:6443"   # pointing to 127.0.0.1 may fail, since any cert validation may need to match against the IP of the control plane node
OUT="./static-token.kubeconfig"

kubectl config --kubeconfig "$OUT" set-cluster test-cluster --server="$APISERVER" --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
kubectl config --kubeconfig "$OUT" set-credentials static-token-user --token="$TOKEN"
kubectl config --kubeconfig "$OUT" set-context static-token-context --cluster=test-cluster --user=static-token-user
kubectl config --kubeconfig "$OUT" use-context static-token-context
```

```
# KUBECONFIG=./static-token.kubeconfig kubectl get nodes
NAME          STATUS   ROLES           AGE   VERSION
k8s-ubuntu1   Ready    control-plane   8d    v1.36.0
k8s-ubuntu2   Ready    <none>          8d    v1.36.0
k8s-ubuntu3   Ready    <none>          8d    v1.36.0
```





