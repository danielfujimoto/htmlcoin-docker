# syntax=docker/dockerfile:1

############################################
# 1) Builder: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Ferramentas de build e libs de desenvolvimento
RUN apt-get update && apt-get install -y \
  build-essential libtool autotools-dev automake pkg-config \
  libssl-dev libevent-dev libboost-all-dev \
  wget curl git ca-certificates m4 xz-utils \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# -----------------------------------------------------------
# A) GMP 6.2.1 (com C++ bindings)
# -----------------------------------------------------------
RUN wget -q https://gmplib.org/download/gmp/gmp-6.2.1.tar.xz \
 && tar -xf gmp-6.2.1.tar.xz \
 && cd gmp-6.2.1 \
 && ./configure --enable-cxx --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig

# -----------------------------------------------------------
# B) Berkeley DB 4.8 com atomics em assembly (evita patch)
# -----------------------------------------------------------
RUN wget -q http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz \
 && tar -xzf db-4.8.30.NC.tar.gz

ENV BDB_PREFIX=/opt/db4
# dica: define a detecção de atomics e mutex p/ evitar __atomic_compare_exchange
ENV db_cv_atomic=x86/gcc-assembly
RUN cd db-4.8.30.NC/build_unix \
 && ../dist/configure --enable-cxx --disable-shared --with-pic \
      --with-mutex=x86_64/gcc-assembly --prefix=${BDB_PREFIX} \
 && make -j"$(nproc)" \
 && make install

# -----------------------------------------------------------
# C) HTMLCOIN Core (branch master-2.5)
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
RUN git clone --depth=1 --branch ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN

# Alguns ambientes falham na detecção do GMP -> força o cache de autoconf
ENV ac_cv_lib_gmp___gmpn_sub_n=yes

RUN ./autogen.sh && \
    ./configure \
      --without-gui \
      CPPFLAGS="-I/usr/local/include -I${BDB_PREFIX}/include" \
      LDFLAGS="-L/usr/local/lib -L${BDB_PREFIX}/lib -Wl,--no-as-needed" \
      LIBS="-lgmp -lgmpxx -ldb_cxx-4.8" \
    && make -j"$(nproc)" \
    && strip src/htmlcoind src/htmlcoin-cli || true

############################################
# 2) Runtime: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

# Somente libs necessárias em runtime
RUN apt-get update && apt-get install -y \
  libevent-2.1-7 libssl3 \
  libboost-system1.74.0 libboost-filesystem1.74.0 \
  libboost-program-options1.74.0 libboost-thread1.74.0 \
  && rm -rf /var/lib/apt/lists/*

# DB4 do builder e GMP (caso linke dinâmico)
COPY --from=builder /opt/db4 /opt/db4
COPY --from=builder /usr/local/lib/libgmp* /usr/local/lib/
RUN ldconfig

# Binários HTMLCOIN
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Usuário e diretório de dados
RUN useradd -m -d /home/htmlcoin -s /usr
