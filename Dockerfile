FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Unreal servers refuse to run as root.
RUN useradd -m gameserver
USER gameserver
WORKDIR /home/gameserver

COPY --chown=gameserver:gameserver build/LinuxServer/ ./
COPY --chown=gameserver:gameserver --chmod=755 start.sh ./

EXPOSE 7777/udp
ENTRYPOINT ["./start.sh"]
