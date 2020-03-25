# PKCS #11 deployment instructions

This README describes how to build the PKCS #11 proxy into a Docker image and then deploy the image to your Kubernetes cluster so that your blockchain node can use the IBM Z openCryptoki HSM to manage its private key. After you complete this process, you will have the values of the **HSM proxy endpoint**, **HSM Label**, and **HSM PIN** that are required by the IBM Blockchain Platform node to use the HSM.


## Before you begin

- The following instructions require a Docker Hub account.
- You will need to provide a storage class for your PVC.
- These instructions assume you are comfortable with Kubernetes and `kubectl` commands.
- You should have an [openCryptoki HSM](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_usingep11.html) configured for your Z environment and you know the HSM **EP11_SLOT_TOKEN_LABEL**, **EP11_SLOT_SO_PIN**, and **EP11_SLOT_USER_PIN**.

# Step 1. Build and push PKCS #11 proxy image

Use these steps to build a Docker image that contains the PKCS #11 proxy, which enables communications with the openCryptoki HSM, and push it to your Docker registry.

## Provide your HSM slot configuration

Before you can build the Docker image, you need to provide your HSM slot label, initialization code, and PIN by editing the [`entrypoint.sh`](./docker-image/entrypoint.sh) file.  

Replace the following variables in the file:

- **`<EP11_SLOT_TOKEN_LABEL>`**: Specify the token label of the slot to use. **Record this value because it is required when you configure an IBM Blockchain Platform node to use this HSM.**
- **`<EP11_SLOT_SO_PIN>`**: Specify the initialization code of the slot.
- **`<EP11_SLOT_USER_PIN>`**: Specify the HSM PIN for the slot. **Record this value because it is required when you configure an IBM Blockchain Platform node to use this HSM.**

### `entrypoint.sh` Template
```sh
#!/bin/bash -ux

EXISTED_EP11TOK=$(ls /var/lib/opencryptoki)
if [ -z "$EXISTED_EP11TOK" ]
then
  ## It's empty, then using default token configured
  echo "Copy content for /var/lib/opencryptoki"
  cp -rf /install/opencryptoki/* /var/lib/opencryptoki/
else
  ## using existed configured data
  echo "To use existed configuration!"
fi

EXISTED_CFG=$(ls /etc/opencryptoki)
if [ -z "$EXISTED_CFG" ]
then
  ## It's empty, then using default config
  echo "Copy content for /var/lib/opencryptoki"
  cp -rf /install/config/* /etc/opencryptoki/
else
  ## using existed configured data
  echo "To use existed configuration!"
fi

service pkcsslotd start

SLOT_NO=${EP11_SLOT_NO:-4}
SLOT_TOKEN_LABEL=${EP11_SLOT_TOKEN_LABEL:-"<EP11_SLOT_TOKEN_LABEL>"}
SLOT_SO_PIN=${EP11_SLOT_SO_PIN:-"<EP11_SLOT_SO_PIN>"}
SLOT_USER_PIN=${EP11_SLOT_USER_PIN:-"<EP11_SLOT_USER_PIN>"}

EXISTED_LABEL=$(pkcsconf -t | grep -w ${SLOT_TOKEN_LABEL})
if [ -z "$EXISTED_LABEL" ]
then
  echo "initailized slot: "${SLOT_NO}
  printf "87654321\n${SLOT_TOKEN_LABEL}\n" | pkcsconf -I -c ${SLOT_NO}
  printf "87654321\n${SLOT_SO_PIN}\n${SLOT_SO_PIN}\n" | pkcsconf -P -c ${SLOT_NO}
  printf "${SLOT_SO_PIN}\n${SLOT_USER_PIN}\n${SLOT_USER_PIN}\n" | pkcsconf -u -c ${SLOT_NO}
else
  echo "The slot already initialized!"
fi

pkcs11-daemon /usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so
```

## Build Docker image

Run the following command to build the Docker image:

```
docker build -t pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .
```

This command is also provided in the [docker-image-build.sh](./docker-image/docker-image-build.sh) file.

## Push Docker image

Run the following set of commands to push the Docker image to your Docker Hub repository.

Replace the following variables in the commands:

- **`<DOCKER_HUB>`**: Specify the address of your Docker server.
- **`<DOCKER_HUB_ID>`**: Specify your Docker Hub username or email address.
- **`<DOCKER_HUB_PWD>`**: Specify your Docker Hub password.

```
DOCKER_HUB=<DOCKER_HUB>

docker tag pkcs11-proxy-opencryptoki:s390x-1.0.0 $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
docker login -u <DOCKER_HUB_ID> -p <DOCKER_HUB_PWD> $DOCKER_HUB
docker push $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
```

These commands are also provided in the [docker-image-push.sh](./docker-image/docker-image-push.sh) file.

# Step 2. Deploy the image to Kubernetes

After you have built the image, there are a few additional tasks you need to perform before you can deploy the Docker image.

## Create a Docker registry secret

Run the following commands to create a Kubernetes secret named `ibprepo-key-secret` to store your Docker image pull secret.

Replace the following variables in the commands:

- **`<DOCKER_HUB>`**: Specify the address your Docker server.
- **`<DOCKER_HUB_ID>`**: Specify your Docker Hub username or email address.
- **`<DOCKER_HUB_PWD>`**: Specify your Docker Hub password.
- **`<NAMESPACE>`**: Specify the name of your Kubernetes namespace.

```
DOCKER_HUB=<DOCKER_HUB>
DOCKER_HUB_ID=<DOCKER_HUB_ID>
DOCKER_HUB_PWD=<DOCKER_HUB_PWD>
namespace=<NAMESPACE>

kubectl create secret docker-registry ibprepo-key-secret --docker-server=$DOCKER_HUB   --docker-username=$DOCKER_HUB_ID --docker-password=$DOCKER_HUB_PWD --docker-email=$DOCKER_HUB_ID -n $namespace
```

## Create an image pull policy

Edit the [image-policy.yaml](./deployment/image-policy.yaml) file, replacing **`<DOCKER_HUB>`** with the address your Docker server.

### `imagePolicy.yaml` template
```yaml
apiVersion: securityenforcement.admission.cloud.ibm.com/v1beta1
kind: ImagePolicy
metadata:
  name: image-policy-pkcs11-proxy
spec:
  repositories:
  - name: <DOCKER_HUB>
```

Run the following command to apply this policy to your Kubernetes namespace, replacing **`<NAMESPACE>`** with the name of your Kubernetes namespace.

```
kubectl apply -f image-policy.yaml -n <NAMESPACE>
```

## Create PVC

Edit the [opencryptoki-token-pvc.yaml](./deployment/opencryptoki-token-pvc.yaml) file to provide the name of the storage class for your PVC in the **`<STORAGECLASS_NAME>`** variable.

### `opencryptoki-token-pvc.yaml` template
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: opencryptoki-token-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: <STORAGECLASS_NAME>
```

Run the following command to apply this PVC to your Kubernetes namespace, replacing **`<NAMESPACE>`** with the name of your Kubernetes namespace.

```
kubectl apply -f opencryptoki-token-pvc.yaml -n <NAMESPACE>
```

## Create Security Policy

The Security Policy is based on three configuration files:
- [psp.yaml](./deployment/psp.yaml)
- [clusterrole.yaml](./deployment/clusterrole.yaml)
- [clusterrolebinding.yaml](./deployment/clusterrolebinding.yaml)

No modifications are required for the `psp.yaml` or the `clusterrole.yaml` files. But you do need to edit the [clusterrolebinding.yaml](./deployment/clusterrolebinding.yaml) file and replace
**`<NAMESPACE>`** with the name of your Kubernetes namespace.

### `clusterrolebinding.yaml` template
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pkcs11-proxy-clusterrolebinding
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:serviceaccounts:<NAMESPACE>
roleRef:
  kind: ClusterRole
  name: pkcs11-proxy-clusterrole
  apiGroup: rbac.authorization.k8s.io
```

Deploy the security policy by running the following commands:

```
kubectl apply -f psp.yaml
kubectl apply -f clusterrole.yaml
kubectl apply -f clusterrolebinding.yaml
```

## Create label for Kubernetes node

Create a label for the Kubernetes node where the IBM HSM cryptographic card is installed. The label and value are required in a subsequent step when you deploy the Docker image to your Kubernetes cluster.

1. Run the following command to get information about all the nodes in cluster:

  ```sh
  kubectl get nodes
  ```

2. Create a label for your node on which an IBM HSM cryptographic card is installed.

  ```sh
  kubectl label node <NODENAME> --overwrite=true <LABEL-KEY>=<LABEL-VALUE>
  ```

  Replace the following variables in the command:
  - **`<NODENAME>`**: Specify the name of the node in your cluster where the HSM cryptographic card is installed.
  - **`<LABEL-KEY>`**: Specify the label that you want to assign to this node, for example, `HSM`.
  - **`<LABEL-VALUE>`**: Specify the value of the label key, for example, `installed`.   

  **Important:** Record the `<LABEL-KEY>`:`<LABEL-VALUE>` pair to provide it in a subsequent step.

  For example:
  ```
  kubectl label node worker1 --overwrite=true HSM=installed
  ```

3. Verify that the label was created successfully by running the following command, replacing **`<NODENAME>`** with the name of the node in your cluster where the HSM cryptographic card is installed.

  ```sh
  kubectl get node <NODENAME> --show-labels=true
  ```

## Deploy the image

Edit the [pkcs11-proxy-opencryptoki.yaml](./deployment/pkcs11-proxy-opencryptoki.yaml) file and provide the values from your own environment:

Replace the following variables in the file:
- **`<IBPREPO-KEY-SECRET>`**: Specify the name of the docker-registry secret that you created in the [Create a Docker registry secret](#create-a-docker-registry-secret) step. For example, `ibprepo-key-secret`.
- **`<LABEL-KEY>`**: **`<LABEL-VALUE>`**: Specify the label of the Kubernetes node where the cryptographic card is installed, from the [Create label for Kubernetes node](#create-label-for-kubernetes-node) step.
- **`<IMAGE-TAG>`**: Specify the image tag that was created in the [Push Docker image](#push-docker-image) step. For example, `pkcs11-proxy-opencryptoki:s390x-1.0.0`.

### `pkcs11-proxy-opencryptoki.yaml` template

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: pkcs11-proxy
  labels:
    app: pkcs11
spec:
  ports:
  - name: http
    port: 2345
    protocol: TCP
    targetPort: 2345
  selector:
    app: pkcs11
  type: NodePort

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pkcs11-proxy
  labels:
    app: pkcs11
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pkcs11
  template:
    metadata:
      labels:
        app: pkcs11
    spec:
      imagePullSecrets:
        - name: <IBPREPO-KEY-SECRET>
      securityContext:
        privileged: true
      nodeSelector:
        <LABEL-KEY>: <LABEL-VALUE>
      containers:
      - name: proxy
        image: <IMAGE-TAG>
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 2345
        securityContext:
          privileged: true
          allowPrivilegeEscalation: true
          readOnlyRootFilesystem: false
        livenessProbe:
          tcpSocket:
            port: 2345
          initialDelaySeconds: 15
          timeoutSeconds: 5
          failureThreshold: 5
        readinessProbe:
          tcpSocket:
            port: 2345
          initialDelaySeconds: 15
          timeoutSeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: token-object-storage
          mountPath: /var/lib/opencryptoki
        - name: opencryptoki-config
          mountPath: /etc/opencryptoki
      volumes:
      - name: token-object-storage
        persistentVolumeClaim:
          claimName: opencryptoki-token-pvc
      - name: opencryptoki-config
        emptyDir: {}
```

**Note:** The port `2345` is hard-coded in this file, but you can change it to suit your needs.

Run the following command to deploy the openCryptoki proxy to your Kubernetes cluster, replacing **`<NAMESPACE>`** with the name of your Kubernetes namespace.

```
kubectl apply -f pkcs11-proxy-opencryptoki.yaml -n <NAMESPACE>
```


# Step 3. Test your deployment

After the deployment is completes, you can test and verify the deployment.

## Find your cluster ip address

When you test your HSM, you need to provide the `<IP_ADDRESS>` and `<PORT>` of your HSM's PKCS #11 proxy.
When all of your IBM Blockchain Platform components (CA, peer, ordering nodes) are local to the cluster, you can use either the internal IP address and port or external IP address and port. But if your blockchain components are not local to the cluster, then you must use the external IP address and port. These instructions describe how to get both pairs of values.

### External IP address

First, run the following command to get a list of IP Addresses for all the nodes in your Kubernetes cluster:

```sh
kubectl get node -o wide
```

For example:

```sh
$ kubectl get node -o wide
NAME           STATUS   ROLES                                 AGE   VERSION          INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
9.47.152.220   Ready    worker                                28d   v1.13.9+icp-ee   9.47.152.220   <none>        Ubuntu 18.04.4 LTS   4.15.0-88-generic   docker://18.9.7
9.47.152.235   Ready    etcd,management,master,proxy,worker   28d   v1.13.9+icp-ee   9.47.152.235   <none>        Ubuntu 18.04.4 LTS   4.15.0-88-generic   docker://18.9.7
9.47.152.236   Ready    worker                                28d   v1.13.9+icp-ee   9.47.152.236   <none>        Ubuntu 18.04.4 LTS   4.15.0-88-generic   docker://18.9.7
```

Look for the row that contains the `master` node. In the example above, the `master` node IP Address (indicated by the `EXTERNAL-IP` field) is: `9.47.152.235`.


### INTERNAL IP address and port

Now run the following command to get the CLUSTER-IP address and the internal and external port of the service.

```sh
kubectl get service pkcs11-proxy -n <NAMESPACE>
```
Replacing:
- `<NAMESPACE>` with name of your Kubernetes namespace.

For example:
```sh
$ kubectl get service pkcs11-proxy -n pkcs11-proxy
NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
pkcs11-proxy   NodePort   10.0.163.235   <none>        2345:30846/TCP   20h
```

From the example above, the internal `CLUSTER-IP` is `10.0.163.235` and the `Internal-port` is `2345`. The `External-port` is `30846`.

### Putting it all together

There are two pairs of values that can be used for the PKCS #11 Proxy `<IP_ADDRESS>:<PORT>`: one for `Internal-port`, and the other for `External-port`.

`Internal-port` pair: `<CLUSTER-IP>:<Internal-PORT>`, from the Internal IP address and port example above, this value would be `10.0.163.235:2345`. This pair can be used when the IBM Blockchain Platform components (CA, peer, ordering node) are deployed in the same cluster.

`External-port` pair: `<Master-node-IP>:<External-PORT>`, from the external IP address example above, this value would be `9.47.152.235:30846`.  This pair would be used when the IBM Blockchain Platform components (CA, peer, ordering nodes) are deployed either in the same cluster or are NOT in the same cluster.

## Run the `pkcs11-tool`

Ensure that the PKCS #11 library `/usr/local/lib/libpkcs11-proxy.so` is installed on your local machine. Then, run the following command:
```
PKCS11_PROXY_SOCKET="tcp://<IP_ADDRESS>:<PORT>" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label <EP11_SLOT_TOKEN_LABEL> --pin <EP11_SLOT_USER_PIN> -t

```

Replace the following variables in the command:
- **`<IP_ADDRESS>:<PORT>`**: Specify the value returned from the [Find your cluster IP address](#how-to-find-your-cluster-ip-address) step.
- **`<EP11_SLOT_TOKEN_LABEL>`**: Specify the value that you specified for the `EP11_SLOT_TOKEN_LABEL` variable in the `entrypoint.sh` file.
- **`<EP11_SLOT_USER_PIN>`**: Specify the value that you specified for the `EP11_SLOT_USER_PIN` variable in the `entrypoint.sh` file.

For example:
```
PKCS11_PROXY_SOCKET="tcp://9.47.152.235:30846`" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

```

The output of this command should look similar to:

```
$ PKCS11_PROXY_SOCKET="tcp://9.47.152.235:30846`" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

C_SeedRandom() and C_GenerateRandom():
  seeding (C_SeedRandom) not supported
  seems to be OK
Digests:
  all 4 digest functions seem to work
  SHA-1: OK
Signatures: not implemented
Verify (currently only for RSA)
  testing key 0 (05f67dba7b52cadc23164f7126b40a54f2772a31d9d9ffeb5f71225fe19f4813) -- non-RSA, skipping
  testing key 1 (467d6c353163e5b3c8571efda38102daa619f6cf48fc78674cb57f409d2f980f) with 1 mechanism -- non-RSA, skipping
  testing key 2 (411761070a0aa7e80654a626ecaf908f9e56ec418f653c41ff0d1ff1dec30656) with 1 mechanism -- non-RSA, skipping
Unwrap: not implemented
Decryption (currently only for RSA)
  testing key 0 (05f67dba7b52cadc23164f7126b40a54f2772a31d9d9ffeb5f71225fe19f4813)  -- non-RSA, skipping
  testing key 1 (467d6c353163e5b3c8571efda38102daa619f6cf48fc78674cb57f409d2f980f)  -- non-RSA, skipping
  testing key 2 (411761070a0aa7e80654a626ecaf908f9e56ec418f653c41ff0d1ff1dec30656)  -- non-RSA, skipping
No errors
```

If the slot is already in use by another session, you might see the following output, which is reasonable:

```
$ PKCS11_PROXY_SOCKET="tcp://9.47.152.235:30846`" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

error: PKCS11 function C_Login failed: rv = CKR_USER_ALREADY_LOGGED_IN (0x100)
Aborting.
```

**Note:**  Save the address of the `PKCS11_PROXY_SOCKET` because it is required when you configure an IBM Blockchain Platform node to use this HSM. Namely it is the value of the **HSM proxy endpoint**.
