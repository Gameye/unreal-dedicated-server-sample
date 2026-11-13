# Unreal Engine dedicated server sample for Gameye

A minimal Unreal Engine 5 dedicated server that runs on [Gameye](https://gameye.com). It builds the Linux server target inside Epic's container image, packages it in a Docker image and runs one match per server process, which is how Gameye runs sessions.

It goes with the [Unreal Engine guide](https://gameye.com/docs/guides/integrations/unreal/) in the Gameye docs. The project has no content of its own: it boots on the engine's empty Entry map, so the repository is only C++, config and scripts.

## What it shows

- A `Server` build target next to the game and editor targets.
- A game mode that logs `READY`, `JOIN`, `LEAVE` and `MATCH_END` lines to stdout, which is what Gameye's logs endpoint returns.
- One match per process. The server quits when the match ends, which ends the Gameye session and stops billing.
- A clean shutdown on `SIGTERM`, which Gameye sends when you stop a session or its `ttl` runs out.
- A `start.sh` that listens on the right port in bridge or host networking, and a Dockerfile that runs the server as a non-root user.
- A smoke test for all of the above, and a join test with a headless Linux game client.

No Gameye plugin or SDK is involved. The server never holds a Gameye API token.

## Requirements

- Docker, with about 100 GB of free disk for Epic's engine image.
- Access to Epic's container images. Link your Epic Games account to GitHub ([instructions](https://www.unrealengine.com/en-US/ue-on-github)), then log Docker in to `ghcr.io` with a GitHub token that has `read:packages`.
- On Apple Silicon: Docker Desktop with "Use Rosetta for x86_64/amd64 emulation" turned on and at least 16 GB of memory for Docker. Builds run emulated and take longer.
- A Gameye account to deploy. Sign up at [trial.gameye.com](https://trial.gameye.com/).

## Build

```bash
scripts/build-server.sh
```

This runs `BuildCookRun` in `ghcr.io/epicgames/unreal-engine:dev-slim-5.8.4` and writes the server to `build/LinuxServer/`. Set `UE_IMAGE` to build with another engine version, and pin a patch tag.

On Apple Silicon the build runs under Rosetta: correct, but slower. A warm rebuild of this project took about 2 minutes on an M4 Max. A Linux x86-64 machine or CI runner is faster.

To also build the Linux game client used by the join test:

```bash
UE_TARGET=client scripts/build-server.sh
```

The client goes to `build/LinuxClient/`. Server and client build separately, because staging both into one folder mixes their plugin manifests and the client then fails to start.

## Test locally

```bash
scripts/smoke-test.sh
```

The test builds the image and checks that the server logs `READY` on UDP 7777, quits with exit code 0 when a match ends, and shuts down cleanly on `SIGTERM`.

After a `SIGTERM`, Unreal runs its normal quit, then exits with code 143 (128 plus the signal number) on purpose. That is a clean stop. Code 137 would mean the server was killed because it didn't exit in time.

To run it yourself:

```bash
docker build --platform linux/amd64 -t dedicated-server-sample:local .
docker run --rm -p 7777:7777/udp dedicated-server-sample:local '/Engine/Maps/Entry?MatchSeconds=300'
```

Then connect a headless client:

```bash
scripts/join-test.sh
```

It checks that the server logs `JOIN`, then `LEAVE` when the client quits, and then ends the match and exits because no players are left.

## Deploy to Gameye

1. Push the image to Docker Hub or GitHub Container Registry with a new tag for every build:

   ```bash
   docker build --platform linux/amd64 -t <you>/dedicated-server-sample:build-001 .
   docker push <you>/dedicated-server-sample:build-001
   ```

2. In the Gameye Admin Panel, create an application for the image with UDP port `7777` in bridge networking. See [Getting started](https://gameye.com/docs/getting-started/).

3. Start a session from your backend:

   ```bash
   curl -X POST https://api.sandbox-gameye.gameye.net/session \
     -H "Authorization: Bearer $GAMEYE_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "image": "dedicated-server-sample",
       "location": "europe",
       "version": "build-001",
       "args": ["/Engine/Maps/Entry?MatchSeconds=600"],
       "ttl": "30m"
     }'
   ```

   Enterprise accounts use `api.production-gameye.gameye.net`. The response holds `host` and a `ports` list. Players connect to `host` on the `host` port that maps container port 7777, for example with `open 203.0.113.42:49152`.

4. Read the server's logs with [`GET /logs`](https://gameye.com/docs/api-v2/reference/get-logs/), and stop the session early with [`DELETE /session/{id}`](https://gameye.com/docs/api-v2/reference/delete-session/).

## Match options

Pass these on the map URL in the session's `args`:

| Option | Effect |
|---|---|
| `?MatchSeconds=600` | End the match after 600 seconds. `0` or absent means no time limit. |
| `?KeepAlive` | Don't quit when the last player leaves. By default the server quits once every player who joined has left. |

## Files

| Path | What it is |
|---|---|
| `Source/DedicatedServerSample/SampleGameMode.cpp` | The match lifecycle: READY, JOIN and LEAVE, match end, shutdown. |
| `Source/DedicatedServerSampleServer.Target.cs` | The server build target. |
| `Config/DefaultEngine.ini` | Entry map, default game mode, port 7777. |
| `start.sh` | Picks the listen port for bridge or host networking and `exec`s the server. |
| `Dockerfile` | Runtime image for the packaged server. |
| `scripts/build-server.sh` | Builds the server in Epic's container image. |
| `scripts/smoke-test.sh` | Local checks before you deploy. |

## Using this in your own project

Copy the server target, the `start.sh` and the Dockerfile, and move the lifecycle code from `SampleGameMode.cpp` into your own game mode. Report match results to your own backend in `ReportResults`, and let the backend call Gameye.

`start.sh` runs the server under `stdbuf -oL`. Gameye runs containers with a terminal, so its logs endpoint shows lines as they happen either way. Without a terminal, as with plain `docker run`, Docker Compose or a CI runner, Unreal holds stdout in a buffer and `docker logs` falls behind. `stdbuf` keeps those live too, and it replaces itself with the server, so `SIGTERM` still reaches Unreal directly.

The build uses the Development configuration so that logs reach stdout, which is what Gameye's logs endpoint shows. Development suits testing and a first deploy. It keeps debug features such as console commands and runs somewhat slower than Shipping, so decide on your launch build before you go live. A Shipping build (`UE_CONFIG=Shipping scripts/build-server.sh`) compiles log output out: in our test it printed three lines over a whole match. `start.sh` also finds the Shipping binary, which is named `DedicatedServerSampleServer-Linux-Shipping`. To keep logs in Shipping, set `bUseLoggingInShipping = true` and `BuildEnvironment = TargetBuildEnvironment.Unique` in the server target. That rebuilds the engine, so it needs an engine built from source. On Epic's prebuilt container image the setting builds without errors but the server still logs nothing.

## License

MIT. See [LICENSE](LICENSE). Unreal Engine itself is under Epic's own license; this repository contains no engine code or content.
