# syntax=docker/dockerfile:1

############################################
# 1) Builder: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Ferramentas de build + headers/libs necessárias (inclui GMP!)
RUN apt-get update && apt-get install -y \
  build-essential libtool autotools-dev automake pkg-config \
  libssl-dev libevent-dev libboost-all-dev libgmp-dev \
  wget curl git ca-certificates xz-utils m4 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# -----------------------------------------------------------
# Berkeley DB 4.8 + patch para GCC modernos
# -----------------------------------------------------------
RUN wget -q http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz \
 && tar -xzf db-4.8.30.NC.tar.gz

# Patch: renomeia __atomic_compare_exchange para evitar conflito com builtins do GCC
RUN sed -i 's/static inline int __atomic_compare_exchange/static inline int __atomic_compare_exchange_db/' db-4.8.30.NC/dbinc/atomic.h \
 && sed -i 's/__atomic_compare_exchange(/__atomic_compare_exchange_db(/g' db-4.8.30.NC/dbinc/atomic.h

# Compila DB4.8 (estático desabilitado; usamos shared no runtime)
RUN cd db-4.8.30.NC/build_unix \
 && ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 \
 && make -j"$(nproc)" \
 && make install

ENV BDB_PREFIX=/opt/db4

# -----------------------------------------------------------
# HTMLCOIN Core (branch master-2.5)
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN

# Alguns ambientes falham no link-test de GMP; garantimos via cache var.
ENV ac_cv_lib_gmp___gmpn_sub_n=yes

# Autotools + flags do DB4; sem GUI (Qt) para binários de servidor
RUN ./autogen.sh && \
    ./configure \
      --without-gui \
      BDB_CFLAGS="-I${BDB_PREFIX}/include" \
      BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
      CPPFLAGS="-I/usr/include" \
      LDFLAGS="-L/usr/lib/x86_64-linux-gnu" \
    && make -j"$(nproc)" \
    && strip src/htmlcoind src/htmlcoin-cli || true


############################################
# 2) Runtime: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

# Somente libs necessárias em runtime (inclui libgmp10)
RUN apt-get update && apt-get install -y \
  libevent-2.1-7 libssl3 libgmp10 \
  libboost-system1.74.0 libboost-filesystem1.74.0 \
  libboost-program-options1.74.0 libboost-thread1.74.0 \
  && rm -rf /var/lib/apt/lists/*

# DB4 do builder (para compatibilidade de carteiras antigas)
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

# Portas (opcional)
EXPOSE 4888 4889

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
