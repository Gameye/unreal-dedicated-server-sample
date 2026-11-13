#!/bin/bash
# Starts the server on the right port in either Gameye network mode.
# Bridge (default): listen on the container port, 7777. Gameye maps it.
# Host: listen on the port Gameye assigns. Set GAMEYE_NETWORK=host in the
# session env when the application uses host networking.
PORT=7777
if [ "$GAMEYE_NETWORK" = "host" ]; then
  PORT="$GAMEYE_PORT_UDP_7777"
fi
# exec makes the server the container's main process, so SIGTERM reaches it.
# stdbuf flushes stdout after every line. Gameye runs containers with a
# terminal, so its logs are live either way, but plain `docker run`, compose
# and CI give stdout a pipe, and Unreal then holds log lines in a buffer.
# Development builds name the binary DedicatedServerSampleServer; Shipping
# builds add -Linux-Shipping.
SERVER=./DedicatedServerSample/Binaries/Linux/DedicatedServerSampleServer
[ -x "$SERVER" ] || SERVER="$SERVER-Linux-Shipping"
exec stdbuf -oL -eL "$SERVER" -port="$PORT" -log "$@"
