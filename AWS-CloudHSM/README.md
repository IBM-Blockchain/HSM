# PKCS#11 proxy deployment instructions for AWS CloudHSM
In order for your IBM Blockchain Platform (IBP) nodes to leverage an AWS CloudHSM to manage their enrollment private keys, they must be configured to communicate with the PKCS#11 interface provided by the AWS CloudHSM.  While you can modify the Docker images provided by IBP to include the appropriate PKCS#11 library, this README describes how to build a PKCS#11 proxy image which communicates with the AWS CloudHSM.  IBP nodes include the PKCS#11 library required to communicate with the PKCS#11 proxy.  The path to this library within each container image is `/usr/local/lib/libpkcs11-proxy.so`. 

## Before you begin

- You will need to provision and configure an AWS CloudHSM using the AWS documentation.  You will need the following artifacts from your AWS CloudHSM deployment:
    - `customerCA.crt` which was used to sign the cluster CSR
    - `ENI (elastic network interface) IP` for one of the HSMs in your cluster.  This can be obtained by using the `describe-clusters` command using the AWS CLI
    - Username and password for an HSM user with the CU (crypto user) role
- You will need an environment in which you can build Docker images.

## Build the PKCS#11 proxy image

This repository has a [`Dockerfile`](./Dockerfile) which can be used to build an image which runs a **PKCS#11 proxy daemon (pkcs11-daemon)** as well as the **AWS cloudhsm_client** process.  The proxy daemon uses the AWS CloudHSM PKCS#11 library to communicate with AWS CloudHSM.

The Docker image is based on [Red Hat Universal Base Image (ubi)](https://access.redhat.com/containers/#/registry.access.redhat.com/ubi8/ubi-minimal) but also includes packages from Fedora 30 which are required by the AWS CloudHSM client and PKCS#11 library but are not availabie in the ubi stream.  It uses [docker-entrypoint.sh](./docker-entrypoint.sh) to configure the AWS CloudHSM client and start the `cloudhsm_client` process in the background.  The `pkcs11-daemon` is started in the foreground and is configured to run on port `2345` and the image also exposes this port externally.

To build the images, run the following command in the root directory of this repository:

```
docker build -t pkcs11-proxy-cloudhsm .
```

If you plan to use this image on a remote Docker host or orchestration environment such as Kubernetes, you will need to push this image to a Docker registry which is accessible from the chosen environment:

```
docker login ${REGISTRY_URL}
docker tag pkcs11-proxy-cloudhsm ${REGISTRY_URL}/pkcs11-proxy-cloudhsm
docker login ${REGISTRY_URL}
docker push ${REGISTRY_URL}/pkcs11-proxy-cloudhsm
```

## Deploying the PKCS#11 proxy image

Two inputs are required when launching **pkcs11-proxy-cloudhsm** image created above as a container:
- An environment variable named **`CLOUDHSM_ENI_IP`** set to the **ENI IP** of the HSM cluster.
- **`customerCA.crt`** mounted as `/opt/cloudhsm/etc/customerCA.crt`.

### Running the proxy on Docker engine

To start a container using Docker, run the following command:
```
docker run -e "CLOUDHSM_ENI_IP=${ENI IP}" -v ${CUSTOMERCAPATH}/customerCA.crt:/opt/cloudhsm/etc/customerCA.crt ${REGISTRY_URL}/pkcs11-proxy-cloudhsm
```
For example, assuming `customerCA.crt` is in your current directory and your ENI IP is 10.0.0.2, you would run:
```
docker run -e "CLOUDHSM_ENI_IP=10.0.0.2" -v $PWD/customerCA.crt:/opt/cloudhsm/etc/customerCA.crt ${REGISTRY_URL}/pkcs11-proxy-cloudhsm
```

### Deploying to Kubernetes 

**COMING SOON**

## Configuring the IBM Blockchain images to use the PKCS#11 proxy

The IBM Blockchain peer, orderer and CA images include built-in support for connecting to the PKCS#11 proxy.  The PKCS#11 driver used to communicate with the proxy is installed in each image in the following location: `/usr/local/lib/libpkcs11-proxy.so`.

This section will cover running the IBM Blockchain Platform images on three environments:

- IBM Blockchain Platform
- Kubernetes
- Docker engine


### Running the IBM Blockchain images on Docker engine



In order to communicate with the PKCS#11 proxy, two items must be configured when launching a peer, orderer and/or CA  container:
- An environment variable named **`PKCS11_PROXY_SOCKET`** must be set to a URL of the form `tcp://${HOSTIP}:2345` where `${HOSTIP}` represents the routable address for a running PKCS#11 proxy container.
- The `bccsp` section of the configuration file for each peer (`core.yaml`), orderer (`orderer.yaml`) and/or CA (`fabric-ca-server-config.yaml`) must be configured to use the `pkcs11` cryptographic provider as follows:
    ```
    BCCSP:
        Default: PKCS11
        PKCS11:
            # Location of the PKCS11 module library
            Library: /usr/local/lib/libpkcs11-proxy.so
            # Alternate ID
            AltId: ${ALT_ID}
            # User PIN
            Pin: ${HSM_USER}:${HSM_PASSWORD}
            Hash: SHA2
            Security: 256
    ```
    where `${ALT_ID}` is the PKCS#11 label for the key and `${HSM_USER}` and `${HSM_PASSWORD}` are the credentials for an HSM user with the CU role.

    Note:  If you intend to have the Fabric CA or the Fabric CA client generate the private key for you, then you should specify a unique, secure string for ${ALT_ID} as this will be used to set the PKCS#11 label