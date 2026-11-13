#!/usr/bin/env bash
# Connect a headless Linux game client to the server and check the match
# lifecycle: the server logs JOIN, then LEAVE when the client quits, and then
# ends the match and exits with code 0 because no players are left.
#
#   UE_TARGET=client scripts/build-server.sh   # once, builds build/LinuxClient/
#   scripts/join-test.sh
set -euo pipefail

SRV=dss-join-srv-$$ CLI=dss-join-cli-$$
cleanup() { docker rm -f "$SRV" "$CLI" >/dev/null 2>&1 || true; }
trap cleanup EXIT
fail() { printf "join-test: FAIL %s\n" "$*" >&2; docker logs "$SRV" 2>&1 | grep LogSampleServer >&2 || true; docker logs "$CLI" 2>&1 | tail -n 8 >&2 || true; exit 1; }
pass() { printf 'join-test: ok   %s\n' "$*"; }
server_log_has() { docker logs "$SRV" 2>&1 | grep -c -- "$1" >/dev/null; }
wait_for() { local i; for ((i = 0; i < $2; i++)); do server_log_has "$1" && return 0; sleep 1; done; return 1; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -d build/LinuxServer/DedicatedServerSample ]] || fail "no server build; run scripts/build-server.sh"
[[ -d build/LinuxClient/DedicatedServerSample ]] || fail "no client build; run UE_TARGET=client scripts/build-server.sh"

docker build --platform linux/amd64 -q -t dedicated-server-sample:join-server . >/dev/null
printf '%s\n' 'FROM ubuntu:24.04' \
  'RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 && rm -rf /var/lib/apt/lists/* && useradd -m player' \
  'USER player' 'WORKDIR /home/player' 'COPY --chown=player:player . ./' \
  | docker build --platform linux/amd64 -q -t dedicated-server-sample:join-client -f - build/LinuxClient >/dev/null
pass "server and client images built"

docker run -d --name "$SRV" --platform linux/amd64 dedicated-server-sample:join-server >/dev/null
wait_for 'READY port=7777' 120 || fail "server did not log READY"

# The client shares the server container's network, so it connects over
# localhost, the same UDP path a player takes to the mapped port.
docker run -d --name "$CLI" --network "container:$SRV" --platform linux/amd64 \
  --entrypoint ./DedicatedServerSample/Binaries/Linux/DedicatedServerSample \
  dedicated-server-sample:join-client DedicatedServerSample 127.0.0.1:7777 -nullrhi -nosound -unattended -nosplash -log >/dev/null
wait_for 'JOIN ' 120 || fail "client did not join"
pass "client joined"

docker stop --timeout 20 "$CLI" >/dev/null
wait_for 'LEAVE ' 60 || fail "no LEAVE after the client quit"
wait_for 'MATCH_END reason="all players left"' 30 || fail "match did not end when the last player left"
code=$(docker wait "$SRV")
[[ "$code" == 0 ]] || fail "server exit code $code"
pass "client left, match ended and the server exited with code 0"
