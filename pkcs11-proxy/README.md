# Deployment instructions

This README describes how to build the PKCS #11 proxy and Docker image for openCryptoki HSM and then deploy it to your Kubernetes cluster so that your blockchain node can use the HSM to manage its private key. After you complete this process you will have the values of the **HSM proxy endpoint**, **HSM Label**, and **HSM PIN** that are required by the IBM Blockchain Platform node to use the HSM.

## Before you begin

- The following instructions require a Docker Hub account.
- You will need to provide a storage class for your PVC.

# Build and push PKCS #11 proxy image

Use these steps to build a Docker image that contains the PKCS #11 proxy that enables communications with the HSM and push it to your Docker registry.

## Provide your HSM slot configuration

Before you can build the Docker image, you need to provide your HSM slot label, PIN, and initialization code by editing the [`entrypoint.sh`](./docker-image/entrypoint.sh) file.  

Replace the following variables:

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
  echo "The slot already initailized!"
fi

pkcs11-daemon /usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so
```

## Build Docker image

Run the following command to build the Docker image:

```
docker build -t pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .
```

## Push Docker image

Run the following set of commands to push the Docker image to your Docker Hub repository.

Replace:

  - `<DOCKER_HUB>` with the address your Docker server.
  - `<DOCKER_HUB_ID>` with your Docker Hub username or email address.
  - `<DOCKER_HUB_PWD>` with your Docker Hub password.

```
DOCKER_HUB=<DOCKER_HUB>

docker tag pkcs11-proxy-opencryptoki:s390x-1.0.0 $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
docker login -u <DOCKER_HUB_ID> -p <DOCKER_HUB_PWD> $DOCKER_HUB
docker push $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
```

Examples of these commands are provided in the following files:

- [docker-image-build.sh](./docker-image/docker-image-build.sh)
- [docker-image-push.sh](./docker-image/docker-image-push.sh)

# Deploy the image to Kubernetes

After you have built the image, there are a few additional tasks you need to perform before you can deploy the Docker image.

## Create a Docker registry secret

Run the following commands to create a Kubernetes secret named `ibprepo-key-secret` to store your Docker image pull secret.

```
DOCKER_HUB=<DOCKER_HUB>
DOCKER_HUB_ID=<DOCKER_HUB_ID>
DOCKER_HUB_PWD=<DOCKER_HUB_PWD>
namespace=<NAMESPACE>

kubectl create secret docker-registry ibprepo-key-secret --docker-server=$DOCKER_HUB   --docker-username=$DOCKER_HUB_ID --docker-password=$DOCKER_HUB_PWD --docker-email=$DOCKER_HUB_ID -n $namespace
```

Replacing:
- `<DOCKER_HUB>` with the address your Docker server.
- `<DOCKER_HUB_ID>` with your Docker Hub username or email address.
- `<DOCKER_HUB_PWD>` with your Docker Hub password.
- `<NAMESPACE>` with name of your Kubernetes namespace.

## Create an image pull policy

Edit the [image-policy.yaml](./deployment/image-policy.yaml) file replacing `<DOCKER_HUB>` with the address your Docker server.

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

Run the following command to apply this policy to your Kubernetes namespace:

```
kubectl apply -f image-policy.yaml -n <NAMESPACE>
```
Replacing:
- `<NAMESPACE>` with name of your Kubernetes namespace.

## Create PVC

Edit the [opencryptoki-token-pvc.yaml](./deployment/opencryptoki-token-pvc.yaml) file to provide the name of the storage class for your PVC in the `<STORAGECLASS_NAME>` variable.

### `opencryptoki-token-pvc.yaml` template
```
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

Run the following command to apply this PVC to your Kubernetes namespace:

```
kubectl apply -f opencryptoki-token-pvc.yaml -n <NAMESPACE>
```

Replacing:
- `<NAMESPACE>` with name of your Kubernetes namespace.

## Create Security Policy

The Security Policy is based on three configuration files:
- [psp.yaml](./deployment/psp.yaml)
- [clusterrole.yaml](./deployment/clusterrole.yaml)
- [clusterrolebinding.yaml](./deployment/clusterrolebinding.yaml)

No modifications are required for the `psp.yaml` or the `clusterrole.yaml` files. But you do need to edit the [clusterrolebinding.yaml](./deployment/clusterrolebinding.yaml) file and replace
`<NAMESPACE>` with the namespace of your Kubernetes cluster.

### `clusterrolebinding.yaml` template
```
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

## Deploy the image

Edit the [pkcs11-proxy-opencryptoki.yaml](./deployment/pkcs11-proxy-opencryptoki.yaml) file and provide the values from your own environment:

Replace:
- `<IBPREPO-KEY-SECRET>` with the name of the docker-registry secret that you created in a previous [step](#create-a-docker-registry-secret). For example, `ibprepo-key-secret`.
- `<LABEL-KEY>` with
- `<LABEL-VALUE>` with the label of the Kubernetes node where the cryptographic card is installed.
- `<IMAGE-TAG>` with the image tag that was created in the [Push Docker image](#push-docker-image) step. For example, `pkcs11-proxy-opencryptoki:s390x-1.0.0`.

### `pkcs11-proxy-opencryptoki.yaml` template

```
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

**Note:** The port `2345` is hard-coded in this file but you can change it to suit your needs.

Run the following command to deploy the openCryptoki proxy to your Kubernetes cluster:

```
kubectl apply -f pkcs11-proxy-opencryptoki.yaml -n <NAMESPACE>
```
Replacing:
- `<NAMESPACE>` with name of your Kubernetes namespace.


# Test your deployment

Run the pkcs11-tool to test the setup. Ensure that `/usr/local/lib/libpkcs11-proxy.so` is installed on your local machine.

Run the following command:
```
PKCS11_PROXY_SOCKET="tcp://<IP_ADDRESS>:2345" pkcs11-tool --module=<libpkcs11-proxy dll path> --token-label <EP11_SLOT_TOKEN_LABEL> --pin <EP11_SLOT_USER_PIN> -t

```

Replacing:
- `<IP_ADDRESS>` with the ip address of the node where the proxy is running.
- `<EP11_SLOT_TOKEN_LABEL>` with the value that you specified for the `EP11_SLOT_TOKEN_LABEL` in the `entrypoint.sh` file.
- `<EP11_SLOT_USER_PIN>` with the value that you specified for the `EP11_SLOT_USER_PIN` in the `entrypoint.sh` file.

**Note:** If you changed the values of the port in the `pkcs11-proxy-opencryptoki.yaml` file, you would need to specify that value here in place of `2345`.

For example:
```
PKCS11_PROXY_SOCKET="tcp://127.0.0.1:2345" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

```

The output of this command should look similar to:


**Note:**  Save the address of the `PKCS11_PROXY_SOCKET` because because it is required when you configure an IBM Blockchain Platform node to use this HSM. Namely it is the value of the **HSM proxy endpoint**.
