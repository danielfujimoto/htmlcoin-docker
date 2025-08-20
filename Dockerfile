FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y \
    build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils git cmake libgmp-dev \
    curl ca-certificates wget xz-utils software-properties-common \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# ✅ Berkeley DB 4.8.30 de repositório confiável do GitHub
RUN curl -LO https://github.com/jackjack-jj/berkeley-db-4.8/releases/download/v1/db-4.8.30.NC.tar.gz && \
    tar -xzf db-4.8.30.NC.tar.gz && \
    cd db-4.8.30.NC/build_unix && \
    ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/opt/db4 && \
    make -j"$(nproc)" && make install

# Continue com a compilação do HTMLCOIN aqui (adicione os comandos após compilar o Berkeley DB)

