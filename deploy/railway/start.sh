#!/bin/sh
# Railway entrypoint for the self-hosted server image. Runs as root only long
# enough to hand the (root-owned) /data volume to `maus`, then runs Caddy and
# the server as `maus`. The server keeps binding 127.0.0.1 (loopback trust);
# Caddy is the only thing listening on the public port.
set -eu

mkdir -p /data && chown -R maus:maus /data

cd /app

setpriv --reuid=maus --regid=maus --init-groups \
  /usr/local/bin/caddy run --config /app/deploy/railway/Caddyfile --adapter caddyfile &
caddy_pid=$!

setpriv --reuid=maus --regid=maus --init-groups \
  node dist-server/server-launcher.js &
server_pid=$!

stopping=0
term() {
  stopping=1
  kill -TERM "$caddy_pid" "$server_pid" 2>/dev/null || true
}
trap term TERM INT

# Poll rather than `wait`, so a signal is handled promptly and the loop ends
# as soon as either child exits.
while kill -0 "$caddy_pid" 2>/dev/null && kill -0 "$server_pid" 2>/dev/null; do
  sleep 1
done

# One child is gone: stop the other and collect both.
kill -TERM "$caddy_pid" "$server_pid" 2>/dev/null || true
wait "$caddy_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true

# A requested shutdown is a clean exit; either child dying on its own is not.
if [ "$stopping" -eq 1 ]; then
  exit 0
fi
exit 1
