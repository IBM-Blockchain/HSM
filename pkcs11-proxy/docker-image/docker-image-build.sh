#!/bin/bash -ux

docker build -t ibmcom/pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .

