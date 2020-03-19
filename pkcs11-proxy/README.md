# Before you begin

- The following instructions require a Docker Hub account.
- You will need to provide a PVC storage class.

# Build and push PKCS #11 proxy image

Change the DOCKER_HUB configuration according to your environment.

```
docker build -t ibmcom/pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .

#DOCKER_HUB=us.icr.io/ibp-temp
DOCKER_HUB=<DOCKER_HUB>
DOCKER_HUB_ID=<DOCKER_HUB_ID>
DOCKER_HUB_PWD=<DOCKER_HUB_PWD>

docker tag ibmcom/pkcs11-proxy-opencryptoki:s390x-1.0.0 $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
docker login -u <DOCKER_HUB_ID> -p <DOCKER_HUB_PWD> $DOCKER_HUB
docker push $DOCKER_HUB/pkcs11-proxy-opencryptoki:s390x-1.0.0
```

Then run:

```
cd docker-image
./docker-image-build.sh
./docker-image-push.sh
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
- <namespace> with your Kubernetes namespace

## Create an image pull policy

Edit the file named ./deployment/image-policy-ibmcom.yaml. Replace
`<DOCKER_HUB>` with the address your docker server.

```
apiVersion: securityenforcement.admission.cloud.ibm.com/v1beta1
kind: ImagePolicy
metadata:
  name: image-policy-ibmcom
spec:
  repositories:
  - name: <DOCKER_HUB>
```

Apply this policy to your Kubernetes namespace.

```
cd ./deployment
kubectl apply -f image-policy-ibmcom.yaml -n <namespace>
```

## Log in to the container registry

<!-- Need more instructions here -->

## Create PVC

Edit the file ./deployment/opencryptoki-token-pvc.yaml.
Replace `<storageclass-name>` with the name of your storage class.

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

example
```
cd ./deployment
kubectl apply -f opencryptoki-token-pvc.yaml -n <namespace>
```

## Deploy the image

Edit the ./deployment/pkcs11-proxy-opencryptoki.yaml file.

<!-- These variables do not exist in the .yaml file -->
Replace the following variables:

\<label-key\>: \<label-value\>  : This is the kubernates node label, on which crypto card is installed
<!-- Where is this in the .yaml?-->

\<image-tag\> : It's the image tag used used
<!-- Where is this in the .yaml?-->


\<slotno\> : It's the slot no of your environment, default is '4', if you want to change the value, you need put opencyrptoki config under a customized volume 'opencryptoki-config'

<!-- Do you mean EP11_SLOT_NO -->

\<token-label\>: It's the token label you want to initialized, default is 'PKCS11'

<!-- Do you mean EP11_SLOT_TOKEN_LABEL -->

\<so-pin\>: defualt is '87654313'

<!-- Do you mean EP11_SLOT_SO_PIN -->

\<user-pin\>: defualt is '87654312'

<!-- Do you mean EP11_SLOT_USER_PIN -->

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
        - name: ibprepo-key-secret
      securityContext:
        privileged: true
      nodeSelector:
        <label-key>: <label-value>
      containers:
      - name: proxy
        image: <image-tag>
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
        env:
        - name: EP11_SLOT_NO
          value: <slotno>
        - name: EP11_SLOT_TOKEN_LABEL
          value: <token-label>
        - name: EP11_SLOT_SO_PIN
          value: <so-pin>
        - name: EP11_SLOT_USER_PIN
          value: <user-pin>
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

```
cd ./deployment
kubectl apply -f pkcs11-proxy-opencryptoki.yaml -n <namespace>
```

# Test your deployment

Run the pkcs11-tool to test the setup. Ensure that /usr/local/lib/libpkcs11-proxy.so is installed on your local machine.

```
PKCS11_PROXY_SOCKET="tcp://<ip address>:2345" pkcs11-tool --module=<libpkcs11-proxy dll path> --token-label <token-label> --pin <user-pin> -t

```

Replace
- `<token-label>` with the value that you specified in the `EP11_SLOT_TOKEN_LABEL` parameter in the pkcs11-proxy-opencryptoki.yaml file.
- `<user-pin>` with the value that you specified in the `EP11_SLOT_USER_PIN` parameter in the pkcs11-proxy-opencryptoki.yaml file.

For example:
```
PKCS11_PROXY_SOCKET="tcp://127.0.0.1:2345" pkcs11-tool --module=/usr/local/lib/libpkcs11-proxy.so --token-label PKCS11 --pin 87654312 -t

```

The output of this command would be similar to:
