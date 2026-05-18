# Projected Volumes

This scenario will describe Kubernetes projected volumes based on a 3 node cluster running on ubuntu 24.04 OS 

Projected volumes are relevant to cluster hardening because they are often used to deliver sensitive or identity-related material into Pods, 
especially the modern approach to ServiceAccount tokens. They also provide a useful way to control exactly which files from ConfigMaps, Secrets, 
the Downward API , and token projections etc. are exposed to a pod/container.

A projected volume lets you combine several different volume sources into a single mounted directory inside a Pod.

For example, instead of mounting:

- a ConfigMap at one path,
- a Secret at another path,
- Downward API data somewhere else,
- and a ServiceAccount token at a separate location,

you can project selected files from each source into one filesystem tree.

Kubernetes currently supports the following projected volume sources:

- `secret`
- `configMap`
- `downwardAPI`
- `serviceAccountToken`
- `clusterTrustBundle`
- `podCertificate`

For this tutorial, we will exemplify:

- `configMap`
- `secret`
- `downwardAPI`
- `serviceAccountToken`

Note: Projected volume sources must be in the same namespace as the Pod.

Projected volumes are not only a storage convenience. They are also relevant to `cluster hardening`.

The most important reason is that modern Kubernetes ServiceAccount tokens are delivered to Pods using token projection. These projected tokens can be:

- short-lived,
- automatically rotated,
- audience-bound,
- mounted read-only,
- and scoped to a specific ServiceAccount identity.

This is safer than relying on older long-lived ServiceAccount token Secrets.

Projected volumes also encourage a least-privilege approach to file exposure. For example, rather than mounting an entire Secret or ConfigMap, you can project only selected keys into the container.

The hardening principles are:

- do not expose credentials to Pods unless they need them;
- disable automatic ServiceAccount token mounting where API access is not required;
- use short-lived projected ServiceAccount tokens where API access or workload identity is required;
- mount sensitive material read-only;
- expose only the specific keys or files required by the application.

---

## Inspect the default ServiceAccount token mount

Before creating a custom projected volume, first inspect what Kubernetes does automatically.

Create a basic Pod:

```
kubectl run pod-projvol --image=alpine:latest -oyaml --dry-run=client -- sh -c "sleep infinity" > pod-projvol.yaml
```

Apply it:

```
kubectl apply -f pod-projvol.yaml
```

Inspect the Pod:

```
kubectl get pod pod-projvol -o yaml
```

On a modern Kubernetes cluster, you will usually see a volume with a generated name similar to this:

```
volumes:
- name: kube-api-access-xxxxx
  projected:
    defaultMode: 420
    sources:
    - serviceAccountToken:
        expirationSeconds: 3607
        path: token
    - configMap:
        name: kube-root-ca.crt
        items:
        - key: ca.crt
          path: ca.crt
    - downwardAPI:
        items:
        - path: namespace
          fieldRef:
            fieldPath: metadata.namespace
```

You will also usually see a matching volume mount:

```
volumeMounts:
- mountPath: /var/run/secrets/kubernetes.io/serviceaccount
  name: kube-api-access-xxxxx
  readOnly: true
```

Inside the container, this typically appears as:

```
/var/run/secrets/kubernetes.io/serviceaccount/token
/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
/var/run/secrets/kubernetes.io/serviceaccount/namespace
```

You can inspect this inside the Pod:

```
kubectl exec -it pod-projvol -- sh
```

Then run:

```
df -h /var/run/secrets/kubernetes.io/serviceaccount
ls -l /var/run/secrets/kubernetes.io/serviceaccount
cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
head -c 40 /var/run/secrets/kubernetes.io/serviceaccount/token
```

This default projected volume is created because, unless configured otherwise, Kubernetes automatically gives Pods credentials for the namespace's default ServiceAccount.

Delete the Pod before continuing:

```
kubectl delete -f pod-projvol.yaml
```

---

## Hardening: disable automatic ServiceAccount token mounting

Many Pods do not need to talk to the Kubernetes API. In that case, a useful hardening step is to prevent Kubernetes from automatically mounting a ServiceAccount token.

Create the following manifest.

Save as `pod-projvol-no-automount.yaml`:

```
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
  name: pod-projvol
spec:
  automountServiceAccountToken: false    # <= this is the hardening difference
  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

Apply it:

```
kubectl apply -f pod-projvol-no-automount.yaml
```

Inspect the Pod:

```
kubectl get pod pod-projvol -o yaml
```

Check inside the container:

```
kubectl exec -it pod-projvol -- sh
```

Then:

```
ls -l /var/run/secrets/kubernetes.io/serviceaccount
```

You should not see the usual automatically mounted token directory.

Delete the Pod:

```
kubectl delete -f pod-projvol-no-automount.yaml
```

This demonstrates an important hardening principle:

> Do not automatically provide Kubernetes API credentials to workloads that do not need them.

---

## Basic projected volumes example

Suppose an application needs:

- non-sensitive configuration from a ConfigMap;
- a password from a Secret;
- its namespace and Pod name from the Downward API.

You can project all of these into one directory.

```
# example imperitive command to create the supporting objects
kubectl create configmap app-config --from-literal=log_level=info --from-literal=feature_x=true -oyaml --dry-run=client
kubectl create secret generic app-secret --from-literal=db-password=supersecret -oyaml --dry-run=client
```

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  app.conf: |
    log_level=info
    feature_x=true
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  db-password: supersecret
---
apiVersion: v1
kind: Pod
metadata:
  name: projected-volume-demo
  labels:
    app: demo
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "ls -l /etc/app && cat /etc/app/pod-name && sleep 3600"]
    volumeMounts:
    - name: app-projected
      mountPath: /etc/app
      readOnly: true

  volumes:
  - name: app-projected
    projected:
      sources:
      - configMap:
          name: app-config
          items:
          - key: app.conf
            path: config/app.conf

      - secret:
          name: app-secret
          items:
          - key: db-password
            path: secrets/db-password

      - downwardAPI:
          items:
          - path: pod-name
            fieldRef:
              fieldPath: metadata.name
          - path: namespace
            fieldRef:
              fieldPath: metadata.namespace
```

Inside the container, all files would appear under `/etc/app`:

```
/etc/app/config/app.conf
/etc/app/secrets/db-password
/etc/app/pod-name
/etc/app/namespace
```

---

# Step-by-step exercise

The following exercise builds up projected volumes incrementally.

You will create:

- a base Pod;
- a ConfigMap;
- a Secret;
- a ServiceAccount;
- separate volume mounts;
- a custom projected ServiceAccount token;
- a final combined projected volume.

---

## Create a base Pod manifest

Generate a basic Pod manifest:

```
kubectl run pod-projvol --image=alpine:latest -o yaml --dry-run=client -- sh -c "sleep infinity" > pod-projvol.yaml
```

The generated manifest should look similar to this:

```
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
  name: pod-projvol
spec:
  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Apply it:

```
kubectl apply -f pod-projvol.yaml
```

Check that it is running:

```
kubectl get pod pod-projvol
```

Delete it so that the same Pod name can be reused later:

```
kubectl delete -f pod-projvol.yaml
```

---

## Create a ConfigMap

Create a ConfigMap manifest:

```
kubectl create configmap configmap-projvol --from-literal=class.name=projvol --from-literal=class.user=user9876 -o yaml --dry-run=client > configmap-projvol.yaml
```

The manifest should look similar to this:

```
apiVersion: v1
data:
  class.name: projvol
  class.user: user9876
kind: ConfigMap
metadata:
  name: configmap-projvol
```

Apply it:

```
kubectl apply -f configmap-projvol.yaml
```

Inspect it:

```
kubectl describe configmap configmap-projvol
```

---

## Create a Secret

Create a Secret manifest:

```
kubectl create secret generic secret-projvol --from-literal=username=user9876 --from-literal=password=please-not-1234 -o yaml --dry-run=client > secret-projvol.yaml
```

The generated manifest should look similar to this:

```
apiVersion: v1
data:
  password: cGxlYXNlLW5vdC0xMjM0
  username: dXNlcjk4NzY=
kind: Secret
metadata:
  name: secret-projvol
type: Opaque
```

Apply it:

```
kubectl apply -f secret-projvol.yaml
```

Inspect it:

```
kubectl describe secret secret-projvol
```

The Secret values in the manifest are base64 encoded. This is not encryption. Anyone with permission to read the Secret object can decode the values.

For example:

```
echo 'cGxlYXNlLW5vdC0xMjM0' | base64 -d
```

In production, Secrets require careful handling. At a minimum, consider:

- restricting RBAC access to Secrets;
- enabling encryption at rest for Secrets in etcd;
- avoiding unnecessary Secret mounts;
- projecting only the specific Secret keys needed by a workload.

---

## Create a ServiceAccount

Create a ServiceAccount manifest:

```
kubectl create serviceaccount sa-projvol -o yaml --dry-run=client > sa-projvol.yaml
```

The manifest should look similar to this.

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-projvol
```

Apply it:

```
kubectl apply -f sa-projvol.yaml
```

Inspect it:

```
kubectl describe serviceaccount sa-projvol
```

This ServiceAccount will be used later when demonstrating projected ServiceAccount tokens.

---

## Combine the base manifests

At this stage, you should have four files:

- `configmap-projvol.yaml`
- `secret-projvol.yaml`
- `sa-projvol.yaml`
- `pod-projvol.yaml`

Combine them into one base file:

```
sed -s '1i ---' configmap-projvol.yaml secret-projvol.yaml sa-projvol.yaml pod-projvol.yaml > projvol-combined-base.yaml
```

This file gives you a convenient starting point for the later examples.

---

## Mount ConfigMap and Secret separately

In this step, the ConfigMap and Secret are mounted as separate volumes. This is not yet a projected volume.

Copy the base file:

```
cp projvol-combined-base.yaml projvol-combined-separate.yaml
```

Edit `projvol-combined-separate.yaml` so that it looks like this:

```
---
apiVersion: v1
data:
  class.name: projvol
  class.user: user9876
kind: ConfigMap
metadata:
  name: configmap-projvol
---
apiVersion: v1
data:
  password: cGxlYXNlLW5vdC0xMjM0
  username: dXNlcjk4NzY=
kind: Secret
metadata:
  name: secret-projvol
type: Opaque
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-projvol
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
  name: pod-projvol
spec:
  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
    volumeMounts:
    - mountPath: /etc/config
      name: configmap-projvol
      readOnly: true
    - mountPath: /etc/secret
      name: secret-projvol
      readOnly: true
  volumes:
  - name: configmap-projvol
    configMap:
      name: configmap-projvol
  - name: secret-projvol
    secret:
      secretName: secret-projvol
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Apply it:

```
kubectl apply -f projvol-combined-separate.yaml
```

Inspect the mounted files:

```
kubectl exec -it pod-projvol -- sh
```

Inside the container:

```
ls -l /etc/config
cat /etc/config/class.name ; echo
cat /etc/config/class.user ; echo

ls -l /etc/secret
cat /etc/secret/username ; echo
cat /etc/secret/password ; echo
```

You should see:

```
/etc/config/class.name
/etc/config/class.user
/etc/secret/username
/etc/secret/password
```

Delete the Pod before continuing:

```
kubectl delete -f projvol-combined-separate.yaml
```

---

## Mount a custom ServiceAccount token as a projected volume

A `serviceAccountToken` is not a standalone volume type. It must be used under a `projected` volume.

This is valid:

```
volumes:
- name: token-volume
  projected:
    sources:
    - serviceAccountToken:
        path: token
        audience: tutorial
        expirationSeconds: 3600
```

The `expirationSeconds` field belongs specifically to the `serviceAccountToken` projection source. It is not a general projected volume setting, and it cannot be applied to ConfigMaps, Secrets, or ordinary volumes.

Important points:

- `expirationSeconds` controls the requested lifetime of the projected ServiceAccount token.
- It defaults to one hour.
- It must be at least 600 seconds.
- The API server administrator may also set a maximum allowed token lifetime.
- The `audience` field identifies the intended recipient of the token.
- A system receiving the token should reject it if the audience does not match what it expects.

Create a manifest for a Pod that uses the `sa-projvol` ServiceAccount and mounts a custom projected token.

Save as `projvol-serviceaccount-token.yaml`:

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-projvol
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
  name: pod-projvol
spec:
  serviceAccountName: sa-projvol
  automountServiceAccountToken: false

  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
    volumeMounts:
    - name: token-volume
      mountPath: /etc/tutorial/token
      readOnly: true

  volumes:
  - name: token-volume
    projected:
      sources:
      - serviceAccountToken:
          path: token
          audience: tutorial
          expirationSeconds: 3600

  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Apply it:

```
kubectl apply -f projvol-serviceaccount-token.yaml
```

Inspect it:

```
kubectl get pod pod-projvol -o yaml
```

Check the mounted token:

```
kubectl exec -it pod-projvol -- sh
```

Inside the container:

```
ls -l /etc/tutorial/token
cat /etc/tutorial/token/token ; echo 
```

You should see a JWT-like token beginning with text similar to:

```
eyJ...
```

Also check that the default automatic token mount has not been added:

```
ls -l /var/run/secrets/kubernetes.io/serviceaccount
```

Because the Pod has:

```
automountServiceAccountToken: false
```

the default automatic mount should not be present. Only the explicit custom projected token should be mounted.

Delete the Pod:

```
kubectl delete pod pod-projvol
```

---

## Create a projected volume from ConfigMap and Secret

Now create a projected volume containing the ConfigMap and Secret.

Copy the base file:

```
cp projvol-combined-base.yaml projvol-combined-projected.yaml
```

Edit `projvol-combined-projected.yaml` so that it looks like this:

```
---
apiVersion: v1
data:
  class.name: projvol
  class.user: user9876
kind: ConfigMap
metadata:
  name: configmap-projvol
---
apiVersion: v1
data:
  password: cGxlYXNlLW5vdC0xMjM0
  username: dXNlcjk4NzY=
kind: Secret
metadata:
  name: secret-projvol
type: Opaque
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-projvol
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
  name: pod-projvol
spec:
  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
    volumeMounts:
    - name: projected-volume
      mountPath: /etc/tutorial/projected
      readOnly: true

  volumes:
  - name: projected-volume
    projected:
      sources:
      - configMap:
          name: configmap-projvol
          items:
          - key: class.name
            path: config/class.name
          - key: class.user
            path: config/class.user

      - secret:
          name: secret-projvol
          items:
          - key: username
            path: secret/username
          - key: password
            path: secret/password

  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Apply it:

```
kubectl apply -f projvol-combined-projected.yaml
```

Inspect the mounted files:

```
kubectl exec -it pod-projvol -- sh
```

Inside the container:

```
find /etc/tutorial/projected -type f -maxdepth 3 -print
```

Expected files:

```
/etc/tutorial/projected/config/class.name
/etc/tutorial/projected/config/class.user
/etc/tutorial/projected/secret/username
/etc/tutorial/projected/secret/password
```

Read the files:

```
cat /etc/tutorial/projected/config/class.name
cat /etc/tutorial/projected/config/class.user
cat /etc/tutorial/projected/secret/username
cat /etc/tutorial/projected/secret/password
```

Delete the Pod:

```
kubectl delete pod pod-projvol
```

---

## Create a projected volume from ConfigMap, Secret, Downward API, and ServiceAccount token

This final example combines all of the tutorial sources into one projected volume:

- ConfigMap keys;
- Secret keys;
- Downward API fields;
- a custom ServiceAccount token.

Save as `projvol-combined-final.yaml`:

```
---
apiVersion: v1
data:
  class.name: projvol
  class.user: user9876
kind: ConfigMap
metadata:
  name: configmap-projvol
---
apiVersion: v1
data:
  password: cGxlYXNlLW5vdC0xMjM0
  username: dXNlcjk4NzY=
kind: Secret
metadata:
  name: secret-projvol
type: Opaque
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-projvol
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod-projvol
    tutorial: projected-volumes
  name: pod-projvol
spec:
  serviceAccountName: sa-projvol
  automountServiceAccountToken: false

  containers:
  - args:
    - sh
    - -c
    - sleep infinity
    image: alpine:latest
    name: pod-projvol
    resources: {}
    volumeMounts:
    - name: projected-volume
      mountPath: /etc/tutorial/projected
      readOnly: true

  volumes:
  - name: projected-volume
    projected:
      defaultMode: 0400
      sources:
      - configMap:
          name: configmap-projvol
          items:
          - key: class.name
            path: config/class.name
          - key: class.user
            path: config/class.user

      - secret:
          name: secret-projvol
          items:
          - key: username
            path: secret/username
          - key: password
            path: secret/password

      - downwardAPI:
          items:
          - path: pod/pod-name
            fieldRef:
              fieldPath: metadata.name
          - path: pod/namespace
            fieldRef:
              fieldPath: metadata.namespace
          - path: pod/labels
            fieldRef:
              fieldPath: metadata.labels

      - serviceAccountToken:
          path: token/token
          audience: tutorial
          expirationSeconds: 3600

  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Apply it:

```
kubectl apply -f projvol-combined-final.yaml
```

Inspect the Pod:

```
kubectl get pod pod-projvol -o yaml
```

Check the mounted files:

```
kubectl exec -it pod-projvol -- sh
```

Inside the container:

```
find /etc/tutorial/projected -type f -maxdepth 4 -print
```

Expected files:

```
/etc/tutorial/projected/config/class.name
/etc/tutorial/projected/config/class.user
/etc/tutorial/projected/secret/username
/etc/tutorial/projected/secret/password
/etc/tutorial/projected/pod/pod-name
/etc/tutorial/projected/pod/namespace
/etc/tutorial/projected/pod/labels
/etc/tutorial/projected/token/token
```

Read the ConfigMap data:

```
cat /etc/tutorial/projected/config/class.name
cat /etc/tutorial/projected/config/class.user
```

Read the Secret data:

```
cat /etc/tutorial/projected/secret/username
cat /etc/tutorial/projected/secret/password
```

Read the Downward API data:

```
cat /etc/tutorial/projected/pod/pod-name
cat /etc/tutorial/projected/pod/namespace
cat /etc/tutorial/projected/pod/labels
```

Inspect the ServiceAccount token:

```
head -c 40 /etc/tutorial/projected/token/token
echo
```

---

## Important syntax differences

There are small but important syntax differences between standalone volumes and projected volume sources.

A standalone Secret volume uses `secretName`:

```
volumes:
- name: secret-volume
  secret:
    secretName: secret-projvol
```

A projected Secret source uses `name`:

```
volumes:
- name: projected-volume
  projected:
    sources:
    - secret:
        name: secret-projvol
```

A standalone ConfigMap volume and a projected ConfigMap source both use `name`:

```
volumes:
- name: configmap-volume
  configMap:
    name: configmap-projvol
```

```
volumes:
- name: projected-volume
  projected:
    sources:
    - configMap:
        name: configmap-projvol
```

A ServiceAccount token projection must be inside a projected volume:

```
volumes:
- name: token-volume
  projected:
    sources:
    - serviceAccountToken:
        path: token
        audience: tutorial
        expirationSeconds: 3600
```

---

## Notes on `expirationSeconds`

`expirationSeconds` is a property of the `serviceAccountToken` projection source only.

Valid:

```
volumes:
- name: token-volume
  projected:
    sources:
    - serviceAccountToken:
        path: token
        audience: tutorial
        expirationSeconds: 3600
```

The `expirationSeconds` field does not apply to ConfigMaps, Secrets, Downward API data, or general volumes.

Some newer projected sources, such as `podCertificate`, also deal with expiring credential material, but they use their own fields and lifecycle. Do not confuse those with `serviceAccountToken.expirationSeconds`.

---

## Notes on file permissions

Projected volumes support `defaultMode` at the projected volume level:

```
volumes:
- name: projected-volume
  projected:
    defaultMode: 0400
    sources:
    - secret:
        name: secret-projvol
        items:
        - key: password
          path: secret/password
```

You can also specify a mode for individual projected files:

```
volumes:
- name: projected-volume
  projected:
    sources:
    - secret:
        name: secret-projvol
        items:
        - key: password
          path: secret/password
          mode: 0400
```

For hardening, sensitive files such as tokens and passwords should normally be mounted read-only and with restrictive permissions.

---

## Notes on updates

Projected volume contents can be updated by the kubelet when the underlying source changes.

For example:

- ConfigMap changes may eventually be reflected in the mounted files.
- Secret changes may eventually be reflected in the mounted files.
- projected ServiceAccount tokens are rotated by Kubernetes.

However, a container using a projected volume source through a `subPath` mount will not receive updates for those sources.


> Avoid using `subPath` for mounted Secret, ConfigMap, or projected credential material if you expect updates or rotation to be visible inside the container.

---

## Cleanup

Remove the Pod and supporting objects:

```
kubectl delete pod pod-projvol --ignore-not-found
kubectl delete pod projected-volume-demo --ignore-not-found
kubectl delete configmap configmap-projvol --ignore-not-found
kubectl delete configmap app-config --ignore-not-found
kubectl delete secret secret-projvol --ignore-not-found
kubectl delete secret app-secret --ignore-not-found
kubectl delete serviceaccount sa-projvol --ignore-not-found
```

---

# Summary

Projected volumes let Kubernetes combine several sources into one mounted directory.

They are useful for application layout, but they are also important for cluster hardening because they control how sensitive files and identity material are delivered into Pods.

The key security lessons are:

- ServiceAccount tokens are commonly delivered using projected volumes.
- Custom ServiceAccount token projections allow `audience` and `expirationSeconds` to be set.
- `expirationSeconds` applies only to `serviceAccountToken` projections.
- Pods that do not need Kubernetes API access should set `automountServiceAccountToken: false`.
- Secrets are base64 encoded by default, not encrypted in the manifest.
- Only mount the specific ConfigMap or Secret keys that a workload needs.
- Mount sensitive projected content read-only.
- Avoid `subPath` where token rotation or updates are required.

