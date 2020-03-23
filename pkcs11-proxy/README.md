# Before you begin

- The following instructions require a Docker Hub account.
- You will need to provide a PVC storage class.

# build and push image

## Change your HSM slot configuration

Before build docker images, some HSM configuraitons in **`entrypoint.sh`** are required to adapt according to your environmment, copy below [`entrypoint.sh`](#template-of-entrypointsh-file) template and then update the following variables (you can take [entrypoint.sh](!.../../docker-image/entrypoint.sh) as reference)

**\<EP11_SLOT_TOKEN_LABEL\>**: Specify the token label of the slot to use, which can be referenced as "HSM label" of IBP HSM configuration panel

**\<EP11_SLOT_SO_PIN\>**: Specify the initialization code of the slot

**\<EP11_SLOT_USER_PIN\>**: Specify the user pin of the slot, which can be referenced as "HSM PIN" of IBP HSM configuration panel

### Template of `entrypoint.sh` file
```
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

## Build docker image

```
docker build -t pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .
```

## Push docker image

```
DOCKER_HUB=<DOCKER_HUB>
DOCKER_HUB_ID=<DOCKER_HUB_ID>
DOCKER_HUB_PWD=<DOCKER_HUB_PWD>

docker tag pkcs11-proxy-opencryptoki:s390x-1.0.0 $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
docker login -u <DOCKER_HUB_ID> -p <DOCKER_HUB_PWD> $DOCKER_HUB
docker push $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
```

Take below as example to build and push docker image

```
./docker-image/docker-image-build.sh
./docker-image/docker-image-push.sh
```

# Deploy the image to Kubernates

## Create a Docker registry secret

```
DOCKER_HUB=<DOCKER_HUB>
DOCKER_HUB_ID=<DOCKER_HUB_ID>
DOCKER_HUB_PWD=<DOCKER_HUB_PWD>
namespace=<namespace>

kubectl create secret docker-registry ibprepo-key-secret --docker-server=$DOCKER_HUB   --docker-username=$DOCKER_HUB_ID --docker-password=$DOCKER_HUB_PWD --docker-email=$DOCKER_HUB_ID -n $namespace
```

Replace
- `<DOCKER_HUB>` with the address your docker server.
- `<DOCKER_HUB_ID>` with your Docker Hub username or email address.
- `<DOCKER_HUB_PWD>` with your Docker Hub password
- `<namespace>` with your Kubernetes namespace

## Create an image pull policy

Copy below [ImagePolicy tempalte](#template-of-imangepolicy) and then replace `<DOCKER_HUB>` with the address your docker server. Can take [image-policy-ibmcom.yaml](!./deployment/image-policy-ibmcom.yaml) as reference.

### Template of ImangePolicy
```
apiVersion: securityenforcement.admission.cloud.ibm.com/v1beta1
kind: ImagePolicy
metadata:
  name: image-policy-ibmcom
spec:
  repositories:
  - name: <DOCKER_HUB>
```

Apply this policy to your Kubernetes namespace, take [image-policy-ibmcom.yaml](!./deployment/image-policy-ibmcom.yaml) as an example.

```
kubectl apply -f image-policy-ibmcom.yaml -n <namespace>
```

## Create PVC

Copy below [PVC tempalte](#template-of-pvc) and then replace `<storageclass-name>` with the name of your storage class. Can take [opencryptoki-token-pvc.yaml](!./deployment/opencryptoki-token-pvc.yaml) as reference.

### Template of PVC
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
  storageClassName: <storageclass-name>
```

Apply this pvc to your Kubernetes namespace, take [opencryptoki-token-pvc.yaml](!./deployment/opencryptoki-token-pvc.yaml) as an example.

```
kubectl apply -f opencryptoki-token-pvc.yaml -n <namespace>
```

## Deploy the image

Copy below [yaml file](#template-of-yaml-file) as deployment template, and you can take [pkcs11-proxy-opencryptoki.yaml](deployment/pkcs11-proxy-opencryptoki.yaml) as a reference.

Need to replace the following variables in template, and put the values of your own env:

\<IBPREPO-KEY-SECRET\> : This is the name of created [docker-registry secret](#create-a-docker-registry-secret) of above step.

\<LABEL-KEY\>: \<LABEL-VALUE\>  : This is the kubernates node label, on which crypto card is installed

\<IMAGE-TAG\> : It's the image tag created at step: [Push docker image](#push-docker-image)

### Template of yaml file

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

Run the following commands to deploy the proxy to your cluster:

Take [pkcs11-proxy-opencryptoki.yaml](deployment/pkcs11-proxy-opencryptoki.yaml) as an example:
```
kubectl apply -f pkcs11-proxy-opencryptoki.yaml -n <namespace>
```

# Test your deployment

Run the pkcs11-tool to test the setup. Ensure that /usr/local/lib/libpkcs11-proxy.so is installed on your local machine.

```
PKCS11_PROXY_SOCKET="tcp://<ip address>:2345" pkcs11-tool --module=<libpkcs11-proxy dll path> --token-label <EP11_SLOT_TOKEN_LABEL> --pin <EP11_SLOT_USER_PIN> -t

```

Replace
- `<EP11_SLOT_TOKEN_LABEL>` with the value that you specified in the `EP11_SLOT_TOKEN_LABEL` in the `entrypoint.sh` file.
- `<EP11_SLOT_USER_PIN>` with the value that you specified in the `EP11_SLOT_USER_PIN` in the `entrypoint.sh` file.

For example:
```
PKCS11_PROXY_SOCKET="tcp://127.0.0.1:2345" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

```

The output of this command would be similar to:
