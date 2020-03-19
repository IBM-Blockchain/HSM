FROM s390x/ubuntu:18.04 as builder

ARG VERSION=2032875

### build pkcs11-proxy ###
RUN apt-get update \
    && apt-get -y install \
    make \
    cmake \
    build-essential \
    libtool \
    libssl-dev \
    libseccomp-dev \
    libgflags-dev \
    libgtest-dev \
    libc++-helpers \
    gcc \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/SUNET/pkcs11-proxy && \
    cd pkcs11-proxy && \
    git checkout ${VERSION} && \
    cmake . && \
    make && \
    make install


FROM s390x/ubuntu:18.04

COPY --from=builder /usr/local/bin/pkcs11-daemon /usr/local/bin/pkcs11-daemon
COPY --from=builder /usr/local/lib/libpkcs11-proxy.so.0.1 /usr/local/lib/libpkcs11-proxy.so.0.1
COPY --from=builder /usr/local/lib/libpkcs11-proxy.so.0 /usr/local/lib/libpkcs11-proxy.so.0
COPY --from=builder /usr/local/lib/libpkcs11-proxy.so /usr/local/lib/libpkcs11-proxy.so

### install opencryptoki ###
RUN apt-get update \
    && apt-get -y install \
    libtool \
    libssl-dev \
    libseccomp-dev \
    libgflags-dev \
    libgtest-dev \
    libltdl7 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install opencryptoki library
# There is a bug of opencryptoki v9.8.0 ~ v3.11.0, and there is no /usr/lib/libep11.so, while there is /usr/lib/libep11.so.3
# There is a hard code to look for /usr/lib/libep11.so
RUN curl --silent -O http://public.dhe.ibm.com/security/cryptocards/pciecc3/EP11/3.0.0/libep11_3.0.0-5_s390x.deb \
    && dpkg -i libep11_3.0.0-5_s390x.deb \
    && apt-get -y update \
    && apt-get -y install opencryptoki \
    && ln -s /usr/lib/libep11.so.3 /usr/lib/libep11.so

RUN mkdir -p /install \
    && cp -rf /var/lib/opencryptoki /install \
    && mkdir -p /install/config \
    && cp -rf /etc/opencryptoki/* /install/config/

WORKDIR /install

EXPOSE 2345
ENV PKCS11_DAEMON_SOCKET="tcp://0.0.0.0:2345"
ENV LIBRARY_LOCATION="/usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so"

COPY entrypoint.sh /install/entrypoint.sh
RUN chmod 777 entrypoint.sh

# create the ibp user and group
RUN addgroup --gid 1000 ibp && useradd --uid 1000 --gid 1000 ibp

RUN chmod -R 777 /install

ENTRYPOINT ["./entrypoint.sh"]
