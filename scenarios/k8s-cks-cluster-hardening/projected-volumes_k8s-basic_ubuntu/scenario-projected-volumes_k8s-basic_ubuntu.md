
# Projected Volumes


A projected volume lets you combine several different volume sources into one single mounted directory inside a Pod. 
For example, instead of mounting a Secret at one path, a ConfigMap at another path, and Downward API data somewhere else, 
you can `project` selected files from each source into a single filesystem tree.

Kubernetes currently supports these projected sources:
  * secret
  * configMap
  * downwardAPI
  * serviceAccountToken
  * clusterTrustBundle
  * podCertificate


# Basic Projected Volumes example:

Suppose an application needs:
  * non-sensitive configuration from a ConfigMap
  * a password from a Secret
  * its namespace and Pod name from the Downward API

You can project all of these into one directory.

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

And inside the container all mounts would be under the dir `/etc/app`:
```
/etc/app/config/app.conf
/etc/app/secrets/db-password
/etc/app/pod-name
/etc/app/namespace
```

## Step-by-step

### base pod manifest 

Create a pod manifest:

```
kubectl run pod-projvol --image=alpine:latest -oyaml --dry-run=client -- sh -c "sleep infinity" > pod-projvol.yaml
```

Apply this, test it runs successfully, then delete it so we can re-use it later.
```
kubectl apply -f pod-projvol.yaml
# check success then delete
kubectl delete -y pod-projvol.yaml 
```

### Create a configMap

Create a configMap to attach to the pod:
```
kubectl create configmap configmap-projvol --from-literal=class.name=projvol --from-literal=class.user=user9876 -oyaml --dry-run=client > configmap-projvol.yaml
```

### Create a Secret

Create a secret which can be attached to the pod:
```
kubectl create secret generic secret-projvol --from-literal=username=user9876 --from-literal=password=please-not-1234 -oyaml --dry-run=client > secret-projvol.yaml
```
inspecting this output file, you will notice the secret's values are base64 encoded only (i.e. not encrypted), so more care should be taken when using secrets in production.


### Combine all manifests into one file

Three files ahve been created:
  * pod-projvol.yaml
  * configmap-projvol.yaml
  * secret-projvol.yaml

Combine these 3 files, and edit thew result to mount each volume type in its own right on the pod. (i.e. we are not yet creating a projected volume, just mounting each source separately to show the difference).
```
sed -s '1i ---' configmap-projvol.yaml secret-projvol.yaml sa-projvol.yaml pod-projvol.yaml > projvol-combined-base.yaml
```

### Edit the combined manifest to mount each source separately

Copy the combined manifest to a new file, and edit it to mount each source separately on the pod:
```
cp projvol-combined-base.yaml projvol-combined-separate.yaml
```

The resulting manifest should look like this:

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
    volumeMounts:
      - mountPath: /etc/config
        name: configmap-projvol
      - mountPath: /etc/secret
        name: secret-projvol
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




### Edit the combined manifest to create a projected volume

Copy the combined manifest to a new file, and edit it to mount each source separately on the pod:
```
cp projvol-combined-base.yaml projvol-combined-projected.yaml
```

The resulting manifest should look like this:
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
          name: pod-projvol-config
          items:
          - key: class.name
            path: config/class.name
          - key: class.user
            path: config/class.user
      - secret:
          name: pod-projvol-secret
          items:
          - key: username
            path: secret/username
          - key: password
            path: secret/password
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

