#!/bin/bash

# create the AWS CloudHSM client config
/opt/cloudhsm/bin/configure -a ${CLOUDHSM_ENI_IP}

# start CloudHSM client
echo -n "* Starting CloudHSM client ... "
/opt/cloudhsm/bin/cloudhsm_client /opt/cloudhsm/etc/cloudhsm_client.cfg &> /tmp/cloudhsm_client_start.log &

# wait for CloudHSM client to be ready
while true
do
    if grep 'libevmulti_init: Ready !' /tmp/cloudhsm_client_start.log &> /dev/null
    then
        echo "[OK]"
        break
    fi
    sleep 0.5
done
echo -e "\n* CloudHSM client started successfully ... \n"

exec "$@"