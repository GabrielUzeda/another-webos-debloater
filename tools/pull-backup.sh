#!/bin/sh
# tools/pull-backup.sh - Traz o backup de estado da TV para este computador.
#
#   ./tools/pull-backup.sh <ip-da-tv> [pasta-destino]
#
# Faz duas coisas numa tacada:
#   1. abre um receptor na porta TCP 9000 deste computador;
#   2. entra no shell root da TV (telnet, porta 23) e manda ela empacotar os
#      diretorios de estado e mandar por nc para ca.
#
# Nada e escrito no disco da TV: o tar sai pelo pipe direto para o seu PC.
# Le apenas /var/preferences, /var/luna/preferences, /var/db,
# /var/lib/webosbrew e /var/lib/webos-clean.
#
# Nao inclui firmware/rootfs de proposito: copiar o rootfs assinado nao ajuda a
# recuperar nada, e regravar particao a mao brickа a TV (aviso do webosbrew).
# A volta de firmware e o modo de recuperacao da LG (USB), nao dd.
set -eu

TV="${1:-}"
DEST="${2:-$PWD}"
PORT="${PORT:-9000}"

[ -n "$TV" ] || { echo "uso: $0 <ip-da-tv> [pasta-destino]" >&2; exit 2; }
command -v nc >/dev/null || { echo "precisa de nc (netcat)" >&2; exit 2; }
mkdir -p "$DEST"

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$DEST/webos-clean-state-$STAMP.tar.gz"
PATHS="/var/preferences /var/luna/preferences /var/db /var/lib/webosbrew /var/lib/webos-clean"

# IP deste computador na rota da TV
HOST_IP=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('$TV',23));print(s.getsockname()[0])" 2>/dev/null || true)
[ -n "$HOST_IP" ] || HOST_IP=$(ip route get "$TV" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -n "$HOST_IP" ] || { echo "nao consegui descobrir o IP local" >&2; exit 2; }

echo "==> Recebendo em $HOST_IP:$PORT -> $OUT"
# -l escuta; -q 1 sai quando o emissor fechar
( nc -l -p "$PORT" > "$OUT" 2>/dev/null || nc -l "$PORT" > "$OUT" 2>/dev/null ) &
LISTENER=$!
sleep 1

echo "==> Pedindo o pacote para a TV $TV"
{
  printf 'tar czf - %s 2>/dev/null | nc %s %s\n' "$PATHS" "$HOST_IP" "$PORT"
  printf 'echo __DONE__\n'
  printf 'exit\n'
} | nc -w 120 "$TV" 23 >/dev/null 2>&1 || true

# espera o receptor terminar (ate ~2 min)
i=0
while kill -0 "$LISTENER" 2>/dev/null && [ "$i" -lt 120 ]; do sleep 1; i=$((i + 1)); done
kill "$LISTENER" 2>/dev/null || true

if [ ! -s "$OUT" ] || ! gzip -t "$OUT" 2>/dev/null; then
  echo "FALHOU: pacote vazio ou corrompido ($OUT)" >&2
  exit 1
fi

sha256sum "$OUT" > "$OUT.manifest"
echo "==> OK: $OUT ($(du -k "$OUT" | awk '{print $1}') KB)"
echo "    manifesto: $OUT.manifest"
