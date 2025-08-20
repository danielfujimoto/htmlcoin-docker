#!/usr/bin/env bash
set -euo pipefail

DATADIR="${HTMLCOIN_DATA:-/home/htmlcoin/.htmlcoin}"
CONF="${DATADIR}/htmlcoin.conf"

mkdir -p "$DATADIR"

# Se não existir, cria um htmlcoin.conf básico (sem expor RPC)
if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<'EOF'
server=1
printtoconsole=1
rpcallowip=127.0.0.1
# seeds (opcional) para bootstrap
addnode=seed4.htmlcoin.com
addnode=38.242.203.173
EOF
fi

exec "$@"
