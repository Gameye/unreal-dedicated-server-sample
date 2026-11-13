#!/usr/bin/env bash
# Build, cook and stage the Linux dedicated server inside Epic's Unreal Engine
# container image. No local Unreal install is needed.
#
#   scripts/build-server.sh
#
# Output: build/LinuxServer/ (the archived server) and build/logs/ (UAT logs).
#
# One-time setup:
#   1. Link your Epic Games account to GitHub and accept the invitation to the
#      EpicGames organization: https://www.unrealengine.com/en-US/ue-on-github
#   2. Log Docker in to ghcr.io with a GitHub token that has read:packages:
#        printf %s "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
#   3. On Apple Silicon, turn on "Use Rosetta for x86_64/amd64 emulation" in
#      Docker Desktop and give Docker 16 GB of memory and about 100 GB of disk.
#
# Environment (optional):
#   UE_IMAGE      engine image (default ghcr.io/epicgames/unreal-engine:dev-slim-5.8.4).
#                 Pin a patch tag. dev-slim-5.8.1 and the floating dev-slim-5.8 tag were
#                 reported to contain a 1 TB sparse file that fills the disk on pull.
#   UE_CONFIG     server build configuration (default Development)
#   UE_TARGET     server (default) or client. client builds the Linux game into
#                 build/LinuxClient/, which scripts/join-test.sh uses as a headless client.
#   UE_NO_UBA     1 turns off UnrealBuildAccelerator detouring (default 1 on arm64 hosts,
#                 where detoured builds hang under Rosetta)
set -euo pipefail

readonly DEFAULT_IMAGE="ghcr.io/epicgames/unreal-engine:dev-slim-5.8.4"
readonly PROJECT=DedicatedServerSample

die() { printf 'build-server: %s\n' "$*" >&2; exit 1; }
note() { printf 'build-server: %s\n' "$*" >&2; }

in_container() {
  local ue_root=${UE_ROOT:-/home/ue4/UnrealEngine}
  local uat="$ue_root/Engine/Build/BatchFiles/RunUAT.sh"
  [[ -x "$uat" ]] || die "RunUAT not found at $uat"
  mkdir -p /out/logs
  trap 'cp -R "$HOME/Library/Logs/Unreal Engine/LocalBuildLogs" /out/logs/uat 2>/dev/null || true' EXIT

  local uba=true
  [[ "${UE_NO_UBA:-0}" == 1 ]] && uba=false
  local cfg="$HOME/.config/Unreal Engine/UnrealBuildTool"
  mkdir -p "$cfg"
  cat >"$cfg/BuildConfiguration.xml" <<XML
<?xml version="1.0" encoding="utf-8" ?>
<Configuration xmlns="https://www.unrealengine.com/BuildConfiguration">
  <BuildConfiguration>
    <bAllCores>true</bAllCores>
    <bAllowUBAExecutor>$uba</bAllowUBAExecutor>
  </BuildConfiguration>
</Configuration>
XML

  # Build from a container-local copy: the project is mounted read-only, and
  # Intermediate/ on an emulated bind mount is slow.
  local work=/tmp/$PROJECT
  rm -rf "$work" && mkdir -p "$work"
  tar -C /project --exclude=./Binaries --exclude=./Intermediate --exclude=./Saved \
    --exclude=./DerivedDataCache --exclude=./build -cf - . | tar -C "$work" -xf -

  # Server and client archive to separate folders: staging both into one folder
  # mixes their plugin manifests, and the client then fails to boot.
  local target=(-server -serverplatform=Linux -noclient -serverconfig="${UE_CONFIG:-Development}") dest=/out/LinuxServer
  if [[ "${UE_TARGET:-server}" == client ]]; then
    target=(-clientconfig="${UE_CONFIG:-Development}")
    dest=/out/LinuxClient
  fi
  rm -rf "$dest"
  set +e
  "$uat" BuildCookRun \
    -project="$work/$PROJECT.uproject" \
    -noP4 -unattended -utf8output \
    -platform=Linux \
    "${target[@]}" \
    -map=/Engine/Maps/Entry \
    -build -cook -stage -pak -archive \
    -archivedirectory="$dest" 2>&1 | tee /out/logs/build.log
  local status=${PIPESTATUS[0]}
  set -e
  if ((status != 0)); then
    grep -nE '(: (fatal )?error[: ])|(^ERROR:)|(BUILD FAILED)|(ExitCode=[1-9])' /out/logs/build.log | head -n 40 >&2 || true
    die "BuildCookRun failed (exit $status), full log in build/logs/build.log"
  fi
}

on_host() {
  command -v docker >/dev/null 2>&1 || die "docker not found"
  local repo out image platform=linux/amd64 arch no_uba
  repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  out="$repo/build"
  mkdir -p "$out"
  image=${UE_IMAGE:-$DEFAULT_IMAGE}
  arch=$(docker info --format '{{.Architecture}}' 2>/dev/null) || die "docker daemon not reachable"
  no_uba=${UE_NO_UBA:-0}
  if [[ "$arch" == aarch64 || "$arch" == arm64 ]]; then
    note "host is $arch: building $platform under emulation"
    no_uba=${UE_NO_UBA:-1}
  fi
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    note "pulling $image (tens of GB)"
    docker pull --platform "$platform" "$image" \
      || die "cannot pull $image: link your Epic account to GitHub and log in to ghcr.io (see the top of this script)"
  fi
  note "image $image, output $out"
  docker run --rm --platform "$platform" --entrypoint /bin/bash \
    -v "$repo:/project:ro" -v "$out:/out" \
    -e UE_CONFIG="${UE_CONFIG:-Development}" -e UE_TARGET="${UE_TARGET:-server}" -e UE_NO_UBA="$no_uba" \
    "$image" /project/scripts/build-server.sh --in-container
  if [[ "${UE_TARGET:-server}" == client ]]; then note "done: $out/LinuxClient"; else note "done: $out/LinuxServer"; fi
}

if [[ "${1:-}" == "--in-container" ]]; then in_container; else on_host; fi
