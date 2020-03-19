#!/bin/bash -ux

docker run -it -d --name=pkcs11-proxy-opencryptoki \
    -v /home/icpcrypto/hsm/token/opencryptoki:/var/lib/opencryptoki \
    --device=/dev/z90crypt:/dev/z90crypt \
    -e EP11_SLOT_NO=4 \
    -e EP11_SLOT_TOKEN_LABEL=PKCS11 \
    -e EP11_SLOT_SO_PIN=87654313 \
    -e EP11_SLOT_USER_PIN=87654312 \
    -p 2345:2345 \
    ibmcom/pkcs11-proxy-opencryptoki:s390x-1.0.0
