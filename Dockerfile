# syntax=docker/dockerfile:1

############################
# 1) Builder (Ubuntu 22.04)
############################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils git cmake libgmp-dev \
    curl ca-certificates wget xz-utils software-properties-common \
 && rm -rf /var/lib/apt/lists/*

# Compila Berkeley DB 4.8 (necessário para wallet)
WORKDIR /tmp
RUN curl -fsSL https://raw.githubusercontent.com/bitcoin/bitcoin/24.x/contrib/install_db4.sh -o install_db4.sh \
 && mkdir -p /opt/db4 \
 && bash install_db4.sh /opt/db4 \
 && rm -rf /tmp/*

# ⬇️ ATENÇÃO: o script instala em /opt/db4/db4
ENV BDB_PREFIX=/opt/db4/db4

# Código do HTMLCOIN (ajuste os ARGs se quiser outro fork/branch/tag)
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master

WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN
WORKDIR /build/HTMLCOIN

# Autotools padrão
RUN ./autogen.sh \
 && ./configure \
      BDB_CFLAGS="-I${BDB_PREFIX}/include" \
      BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
 && make -j"$(nproc)" \
 && strip src/htmlcoind src/htmlcoin-cli || true

############################
# 2) Runtime (Ubuntu 22.04)
############################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libevent-2.1-7 libgmp10 libssl3 \
    libboost-system1.74.0 libboost-filesystem1.74.0 \
    libboost-program-options1.74.0 libboost-thread1.74.0 \
 && rm -rf /var/lib/apt/lists/*

# DB4 do builder
COPY --from=builder /opt/db4 /opt/db4
ENV LD_LIBRARY_PATH="/opt/db4/db4/lib:${LD_LIBRARY_PATH}"

# Binários
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Usuário e diretórios
RUN useradd -m -d /home/htmlcoin -s /usr/sbin/nologin htmlcoin \
 && mkdir -p /home/htmlcoin/.htmlcoin

VOLUME ["/home/htmlcoin/.htmlcoin"]

# Sem su/su-exec; processa direto
ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
