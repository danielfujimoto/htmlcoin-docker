# syntax=docker/dockerfile:1

############################################
# 1) Builder (Ubuntu 22.04)
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils git cmake libgmp-dev \
    wget curl xz-utils software-properties-common \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# 1) Baixa diretamente do site oficial da Oracle (link estável)
RUN wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz && \
    tar -xzf db-4.8.30.NC.tar.gz

# 2) Aplica patch para evitar conflito de símbolo no build do DB4.8
RUN sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' db-4.8.30.NC/dbinc/atomic.h

# 3) Compila o Berkeley DB 4.8 com suporte C++
RUN cd db-4.8.30.NC/build_unix && \
    ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 && \
    make -j"$(nproc)" && make install

ENV BDB_PREFIX=/opt/db4

# 4) Clonar e compilar o HTMLCOIN Core
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=HEAD  # Usa o branch padrão da repo

WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN
RUN ./autogen.sh && \
    ./configure \
      BDB_CFLAGS="-I${BDB_PREFIX}/include" \
      BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" && \
    make -j"$(nproc)" && \
    strip src/htmlcoind src/htmlcoin-cli || true

############################################
# 2) Runtime (Ubuntu 22.04)
############################################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libevent-2.1-7 libgmp10 libssl3 \
    libboost-system1.74.0 libboost-filesystem1.74.0 \
    libboost-program-options1.74.0 libboost-thread1.74.0 \
 && rm -rf /var/lib/apt/lists/*

# Copia Berkeley DB compilado
COPY --from=builder /opt/db4 /opt/db4
ENV LD_LIBRARY_PATH="/opt/db4/lib:${LD_LIBRARY_PATH}"

# Copia binários compilados do HTMLCOIN
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Cria usuário e diretório de dados
RUN useradd -m -d /home/htmlcoin -s /usr/sbin/nologin htmlcoin \
 && mkdir -p /home/htmlcoin/.htmlcoin

VOLUME ["/home/htmlcoin/.htmlcoin"]

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin", "-printtoconsole"]
