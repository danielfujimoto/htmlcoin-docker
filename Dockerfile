# syntax=docker/dockerfile:1

########## 1) BUILDER ##########
FROM ubuntu:18.04 AS builder

# Ubuntu 18.04 é EOL -> usa old-releases
RUN sed -i -E 's|archive.ubuntu.com|old-releases.ubuntu.com|g; s|security.ubuntu.com|old-releases.ubuntu.com|g' /etc/apt/sources.list \
 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils git cmake libboost-all-dev libgmp-dev \
    software-properties-common ca-certificates curl gnupg \
 && add-apt-repository -y ppa:bitcoin/bitcoin \
 && apt-get update && apt-get install -y libdb4.8-dev libdb4.8++-dev

# Compila HTMLCOIN Core v2.5.3
WORKDIR /src
RUN git clone --depth=1 --branch v2.5.3 https://github.com/htmlcoin/HTMLCOIN.git .
RUN ./autogen.sh \
 && ./configure --without-gui --disable-tests --with-boost-libdir=/usr/lib/x86_64-linux-gnu \
 && make -j"$(nproc)"

########## 2) RUNTIME ##########
FROM ubuntu:18.04

# Ubuntu 18.04 é EOL -> usa old-releases
RUN sed -i -E 's|archive.ubuntu.com|old-releases.ubuntu.com|g; s|security.ubuntu.com|old-releases.ubuntu.com|g' /etc/apt/sources.list \
 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl netcat-openbsd \
    libevent-2.1-6 libgmp10 \
    libboost-system1.65.1 libboost-filesystem1.65.1 \
    libboost-program-options1.65.1 libboost-thread1.65.1 \
    software-properties-common \
 && add-apt-repository -y ppa:bitcoin/bitcoin \
 && apt-get update && apt-get install -y libdb4.8 libdb4.8++ \
 && rm -rf /var/lib/apt/lists/*

# Diretório de dados
ENV HTMLCOIN_DATA=/home/htmlcoin/.htmlcoin
RUN mkdir -p "${HTMLCOIN_DATA}"

# Binaries
COPY --from=builder /src/src/htmlcoind /usr/local/bin/htmlcoind
COPY --from=builder /src/src/htmlcoin-cli /usr/local/bin/htmlcoin-cli
COPY --from=builder /src/src/htmlcoin-tx /usr/local/bin/htmlcoin-tx

# Entrypoint simples (cria conf se não existir e sobe o daemon em foreground)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/home/htmlcoin/.htmlcoin"]
# Expose é opcional; não mapearemos no compose
EXPOSE 4888 4889

ENTRYPOINT ["/entrypoint.sh"]
CMD ["htmlcoind", "-datadir=/home/htmlcoin/.htmlcoin", "-printtoconsole=1"]
