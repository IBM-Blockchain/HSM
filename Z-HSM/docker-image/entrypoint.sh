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
  echo "initialized slot: "${SLOT_NO}
  printf "87654321\n${SLOT_TOKEN_LABEL}\n" | pkcsconf -I -c ${SLOT_NO}
  printf "87654321\n${SLOT_SO_PIN}\n${SLOT_SO_PIN}\n" | pkcsconf -P -c ${SLOT_NO}
  printf "${SLOT_SO_PIN}\n${SLOT_USER_PIN}\n${SLOT_USER_PIN}\n" | pkcsconf -u -c ${SLOT_NO}
else
  echo "The slot already initialized!"
fi

pkcs11-daemon /usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so
