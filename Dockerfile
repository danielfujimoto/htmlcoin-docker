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
# A) GMP 6.2.1 (com C++ bindings) -> evita "libgmp missing"
# -----------------------------------------------------------
RUN wget -q https://gmplib.org/download/gmp/gmp-6.2.1.tar.xz \
 && tar -xf gmp-6.2.1.tar.xz \
 && cd gmp-6.2.1 \
 && ./configure --enable-cxx --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig

# -----------------------------------------------------------
# B) Berkeley DB 4.8 + patch para GCC modernos
# -----------------------------------------------------------
RUN wget -q http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz \
 && tar -xzf db-4.8.30.NC.tar.gz

# Renomeia o símbolo __atomic_compare_exchange para evitar conflito
RUN sed -i 's/\<__atomic_compare_exchange\>/__atomic_compare_exchange_db/g' \
       db-4.8.30.NC/dbinc/atomic.h

# Compila DB4.8 (estático recomendado)
RUN cd db-4.8.30.NC/build_unix \
 && ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 \
 && make -j"$(nproc)" \
 && make install

ENV BDB_PREFIX=/opt/db4

# -----------------------------------------------------------
# C) HTMLCOIN Core (branch master-2.5) + submódulos
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
# ⚠️ IMPORTANTE: --recursive para trazer libethashseal e demais submódulos
RUN git clone --recursive --depth=1 --shallow-submodules \
    -b ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN

# Autotools + flags do DB4 e do GMP (link explícito)
# --without-gui evita dependências Qt no servidor
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

# DB4 e GMP do builder
COPY --from=builder /opt/db4 /opt/db4
COPY --from=builder /usr/local/lib/libgmp* /usr/local/lib/
RUN ldconfig

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

# Libs no runtime
ENV LD_LIBRARY_PATH="/usr/local/lib:/opt/db4/lib:${LD_LIBRARY_PATH}"

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin","-printtoconsole"]
