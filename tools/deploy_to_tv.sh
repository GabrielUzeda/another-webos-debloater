#!/bin/sh
set -e
TV_IP="10.1.1.11"
REPO_DIR="/home/gsuzeda/Projects/anotherwebosdebloat"
HOST_IP=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('$TV_IP',23));print(s.getsockname()[0])")

cd "$REPO_DIR"
tar -czf wc_update.tar.gz bin init lib
python3 -m http.server 8765 --bind 0.0.0.0 >/dev/null 2>&1 &
PID=$!
sleep 1
(
  echo "cd /tmp && wget -q -O wc.tar.gz http://$HOST_IP:8765/wc_update.tar.gz && tar -xzf wc.tar.gz -C /tmp/wc/ && echo DEPLOY_OK"
) | "$REPO_DIR/test/tv_exec.sh"
kill $PID 2>/dev/null || true
rm -f "$REPO_DIR/wc_update.tar.gz"
