# syntax=docker/dockerfile:1

############################################
# 1) Builder: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Instalar todas as dependências necessárias conforme o README
RUN apt-get update && apt-get install -y \
  build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 \
  libgmp3-dev libssl-dev libevent-dev \
  libboost-system-dev libboost-filesystem-dev libboost-chrono-dev \
  libboost-test-dev libboost-thread-dev libboost-all-dev \
  cmake m4 xz-utils ca-certificates git wget curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# -----------------------------------------------------------
# Berkeley DB 4.8 (usando o script oficial de instalação)
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
# HTMLCOIN Core (com patches para compatibilidade)
# -----------------------------------------------------------
ARG HTMLCOIN_REPO=https://github.com/HTMLCOIN/HTMLCOIN.git
ARG HTMLCOIN_REF=master-2.5

WORKDIR /build
RUN git clone --recursive --depth=1 --shallow-submodules \
    -b ${HTMLCOIN_REF} ${HTMLCOIN_REPO} HTMLCOIN

WORKDIR /build/HTMLCOIN

# Aplicar patch para compatibilidade com GMP moderno se necessário
RUN if [ -f "contrib/gmp-patch" ]; then patch -p1 < contrib/gmp-patch; fi || true

# Configurar e compilar com flags otimizadas
RUN ./autogen.sh && \
    ./configure \
      --without-gui \
      --disable-wallet \
      --with-gmp=yes \
      --with-gmp-prefix=/usr \
      CPPFLAGS="-I${BDB_PREFIX}/include" \
      LDFLAGS="-L${BDB_PREFIX}/lib -Wl,-rpath,${BDB_PREFIX}/lib" \
      CXXFLAGS="--param ggc-min-expand=1 --param ggc-min-heapsize=32768" \
    || (cat config.log && exit 1)

RUN make -j"$(nproc)" && \
    strip src/htmlcoind src/htmlcoin-cli || true

############################################
# 2) Runtime: Ubuntu 22.04
############################################
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

# Dependências de runtime mínimas
RUN apt-get update && apt-get install -y \
  libevent-2.1-7 libssl3 libgmp10 \
  libboost-system1.74.0 libboost-filesystem1.74.0 \
  libboost-program-options1.74.0 libboost-thread1.74.0 \
  && rm -rf /var/lib/apt/lists/*

# Copiar Berkeley DB
COPY --from=builder /opt/db4 /opt/db4
RUN ldconfig

# Copiar binários
RUN mkdir -p /usr/local/bin
COPY --from=builder /build/HTMLCOIN/src/htmlcoind /usr/local/bin/
COPY --from=builder /build/HTMLCOIN/src/htmlcoin-cli /usr/local/bin/

# Verificar se os binários existem
RUN test -f /usr/local/bin/htmlcoind && test -f /usr/local/bin/htmlcoin-cli

# Configurar usuário e diretórios
RUN useradd -m -d /home/htmlcoin -s /bin/bash htmlcoin \
 && mkdir -p /home/htmlcoin/.htmlcoin \
 && chown -R htmlcoin:htmlcoin /home/htmlcoin

VOLUME ["/home/htmlcoin/.htmlcoin"]
EXPOSE 4888 4889

ENV LD_LIBRARY_PATH="/opt/db4/lib:${LD_LIBRARY_PATH}"

ENTRYPOINT ["/usr/local/bin/htmlcoind"]
CMD ["-datadir=/home/htmlcoin/.htmlcoin", "-printtoconsole"]
