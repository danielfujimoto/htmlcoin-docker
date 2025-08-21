# syntax=docker/dockerfile:1

############################################
# 1) Builder: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Ferramentas de build e libs
RUN apt-get update && apt-get install -y \
  build-essential libtool autotools-dev automake pkg-config \
  libssl-dev libevent-dev libboost-all-dev \
  cmake m4 xz-utils ca-certificates git wget curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# -----------------------------------------------------------
# A) GMP 6.2.1 (com C++ bindings) - corrigido
# -----------------------------------------------------------
RUN wget -q https://gmplib.org/download/gmp/gmp-6.2.1.tar.xz \
 && tar -xf gmp-6.2.1.tar.xz \
 && cd gmp-6.2.1 \
 && ./configure --enable-cxx --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig

# -----------------------------------------------------------
# B) Berkeley DB 4.8 (corrigido)
# -----------------------------------------------------------
RUN wget -q http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz \
  && echo '12edc0df75bf9abd7f82f821795bcee50f42cb2e5f76a6a281b85732798364ef db-4.8.30.NC.tar.gz' | sha256sum -c \
  && tar -xzf db-4.8.30.NC.tar.gz \
  && cd db-4.8.30.NC \
  && sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' dbinc/atomic.h \
  && cd build_unix \
  && ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 \
  && make -j$(nproc) \
  && make install

ENV BDB_PREFIX=/opt/db4

# -----------------------------------------------------------
# C) HTMLCOIN Core (corrigido)
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
RUN git clone --recursive --depth=1 --shallow-submodules \
    -b ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN

# Corrigindo a configuração para encontrar libgmp
RUN ./autogen.sh && \
    ./configure \
      --without-gui \
      CPPFLAGS="-I/usr/local/include -I${BDB_PREFIX}/include" \
      LDFLAGS="-L/usr/local/lib -L${BDB_PREFIX}/lib -Wl,-rpath,/usr/local/lib" \
      LIBS="-lgmp -lgmpxx -ldb_cxx-4.8" \
    && make -j"$(nproc)" \
    && strip src/htmlcoind src/htmlcoin-cli src/test/test_htmlcoin || true

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

# DB4 e GMP do builder
COPY --from=builder /opt/db4 /opt/db4
COPY --from=builder /usr/local/lib/libgmp* /usr/local/lib/
RUN ldconfig

# Binários HTMLCOIN (com verificação de existência)
RUN mkdir -p /usr/local/bin
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Verifica se os binários existem
RUN test -f /usr/local/bin/htmlcoind && test -f /usr/local/bin/htmlcoin-cli

# Usuário e diretório de dados
RUN useradd -m -d /home/htmlcoin -s /usr/sbin/nologin htmlcoin \
 && mkdir -p /home/htmlcoin/.htmlcoin \
 && chown -R htmlcoin:htmlcoin /home/htmlcoin

VOLUME ["/home/htmlcoin/.htmlcoin"]

# Portas
EXPOSE 4888 4889

# Libs no runtime
ENV LD_LIBRARY_PATH="/usr/local/lib:/opt/db4/lib:${LD_LIBRARY_PATH}"

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
