# Etapa 1: Builder
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Variáveis
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=main

# Dependências
RUN apt-get update && apt-get install -y \
  git curl wget build-essential autoconf libtool pkg-config \
  libssl-dev libevent-dev libboost-all-dev \
  libminiupnpc-dev libzmq3-dev libdbus-1-dev \
  libgmp-dev  # <=== ESSENCIAL PARA GMP (__gmpn_sub_n)
  
# Berkeley DB 4.8
WORKDIR /tmp
RUN wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz && \
    tar -xzf db-4.8.30.NC.tar.gz && \
    cd db-4.8.30.NC/build_unix && \
    ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 && \
    make -j"$(nproc)" && make install

# Clone do HTMLCOIN
WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN
WORKDIR /build/HTMLCOIN

# Compilação
RUN ./autogen.sh && \
    ./configure --with-incompatible-bdb --with-gmp --with-gmp-lib=/usr/lib/x86_64-linux-gnu/ --with-gmp-include=/usr/include/ && \
    make -j"$(nproc)"

# Etapa 2: Runtime
FROM ubuntu:22.04

# Dependências mínimas
RUN apt-get update && apt-get install -y \
  libssl3 libevent-2.1-7 libboost-system1.74.0 libboost-filesystem1.74.0 \
  libboost-program-options1.74.0 libboost-thread1.74.0 libgmp10 && \
  rm -rf /var/lib/apt/lists/*

# Copia BerkeleyDB
COPY --from=builder /opt/db4 /opt/db4

# Copia binários HTMLCOIN
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Cria usuário e diretório de dados
RUN useradd -m -s /bin/bash htmlcoin && mkdir -p /data && chown htmlcoin:htmlcoin /data
USER htmlcoin
WORKDIR /data

# Executável padrão
ENTRYPOINT ["htmlcoind"]

