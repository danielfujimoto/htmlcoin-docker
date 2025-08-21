# syntax=docker/dockerfile:1

############################################
# 1) Builder: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Ferramentas de build e dev-libs (inclui boost, event, openssl)
RUN apt-get update && apt-get install -y \
  build-essential libtool autotools-dev automake pkg-config \
  libssl-dev libevent-dev libboost-all-dev \
  wget curl git ca-certificates m4 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# -----------------------------------------------------------
# A) COMPILE GMP (corrige o "libgmp missing" no configure)
# -----------------------------------------------------------
# Usamos 6.2.x (mesma série que o Ubuntu 22.04 fornece)
RUN wget https://gmplib.org/download/gmp/gmp-6.2.1.tar.xz \
 && tar -xf gmp-6.2.1.tar.xz \
 && cd gmp-6.2.1 \
 && ./configure --enable-cxx --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install

# Garante que o linker veja /usr/local/lib durante o build
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"

# -----------------------------------------------------------
# B) COMPILE BERKELEY DB 4.8 + patch para GCC modernos
# -----------------------------------------------------------
RUN wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz \
 && tar -xzf db-4.8.30.NC.tar.gz

# Patch: renomeia o símbolo __atomic_compare_exchange em atomic.h
RUN sed -i 's/static inline int __atomic_compare_exchange/static inline int __atomic_compare_exchange_db/' db-4.8.30.NC/dbinc/atomic.h \
 && sed -i 's/__atomic_compare_exchange(/__atomic_compare_exchange_db(/g' db-4.8.30.NC/dbinc/atomic.h

# Compila DB4.8 estático (recomendado para carteiras antigas)
RUN cd db-4.8.30.NC/build_unix \
 && ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 \
 && make -j"$(nproc)" \
 && make install

ENV BDB_PREFIX=/opt/db4

# -----------------------------------------------------------
# C) CLONE + BUILD HTMLCOIN (branch master-2.5)
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN
# Passamos flags do DB4 e forçamos o linker a ver o GMP
RUN ./autogen.sh && \
    ./configure \
      BDB_CFLAGS="-I${BDB_PREFIX}/include" \
      BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
      CPPFLAGS="-I/usr/local/include" \
      LDFLAGS="-L/usr/local/lib" \
      LIBS="-lgmp" \
    && make -j"$(nproc)" \
    && strip src/htmlcoind src/htmlcoin-cli || true

############################################
# 2) Runtime: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

# Libs de runtime necessárias (boost/event/openssl/gmp)
RUN apt-get update && apt-get install -y \
  libevent-2.1-7 libssl3 libgmp10 \
  libboost-system1.74.0 libboost-filesystem1.74.0 \
  libboost-program-options1.74.0 libboost-thread1.74.0 \
  && rm -rf /var/lib/apt/lists/*

# DB4 do builder (somente libs necessárias para carteira antiga)
COPY --from=builder /opt/db4 /opt/db4
ENV LD_LIBRARY_PATH="/opt/db4/lib:${LD_LIBRARY_PATH}"

# Binários HTMLCOIN
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Usuário e diretório de dados
RUN useradd -m -d /home/htmlcoin -s /usr/sbin/nologin htmlcoin \
 && mkdir -p /home/htmlcoin/.htmlcoin \
 && chown -R htmlcoin:htmlcoin /home/htmlcoin

VOLUME ["/home/htmlcoin/.htmlcoin"]

# Porta P2P 4888 e RPC 4889 (expor é opcional)
EXPOSE 4888 4889

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
