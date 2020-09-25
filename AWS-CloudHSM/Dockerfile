########## Build the pkcs11 proxy ##########
FROM registry.access.redhat.com/ubi8/ubi-minimal as builder
ARG ARCH=amd64

ARG VERSION=2032875

RUN microdnf install -y \
   git \
   make \
   cmake \
   openssl-devel \
   libseccomp-devel \
   gcc;

RUN git clone https://github.com/SUNET/pkcs11-proxy && \
   cd pkcs11-proxy && \
   git checkout ${VERSION} && \
   cmake . && \
   make && \
   make install;

# proxy with CloudHSM client
FROM registry.access.redhat.com/ubi8/ubi-minimal
ARG ARCH=amd64

RUN microdnf update -y \
   && microdnf install -y \
    libedit \
    make \
    ncurses-compat-libs \
    python36 \
    shadow-utils;

# install dependencies not available in ubi stream
RUN if [ "${ARCH}" == "amd64" ]; then ARCH="x86_64"; fi \
   && rpm -ivh https://kojipkgs.fedoraproject.org/packages/compat-openssl10/1.0.2o/5.fc30/${ARCH}/compat-openssl10-1.0.2o-5.fc30.${ARCH}.rpm;


# install AWS CloudHSM client
RUN rpm -ivh https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/EL7/cloudhsm-client-latest.el7.x86_64.rpm \
    && rpm -ivh https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/EL7/cloudhsm-client-pkcs11-latest.el7.x86_64.rpm;

RUN chown -R hsmuser:hsmuser /opt/cloudhsm/etc

RUN ln -s /usr/lib64/libjson-c.so.4 usr/lib64/libjson-c.so.2;
RUN ln -s /usr/bin/python3 /usr/bin/python

# copy daemon from builder
COPY --from=builder /usr/local/bin/pkcs11-daemon /usr/local/bin/pkcs11-daemon

# pkcs-daemon listen port
ENV PKCS11_DAEMON_SOCKET tcp://0.0.0.0:2345
# pkcs11 library
ENV LIBRARY_LOCATION /opt/cloudhsm/lib/libcloudhsm_pkcs11.so

EXPOSE 2345

ADD docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT [ "/usr/local/bin/docker-entrypoint.sh" ]

CMD [ "pkcs11-daemon", "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so", "-"]