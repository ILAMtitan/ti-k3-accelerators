#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 [--jobs N] /path/to/Armbian/build" >&2; exit 2; }
jobs=$(nproc)
while (($#)); do
  case "$1" in
    --jobs) jobs=${2:?}; shift 2;;
    -h|--help) usage;;
    *) break;;
  esac
done
[[ $# -eq 1 && $jobs =~ ^[1-9][0-9]*$ ]] || usage
armbian=$(readlink -f "$1")
[[ -x "$armbian/compile.sh" ]] || { echo "Missing Armbian compile.sh: $armbian" >&2; exit 1; }
[[ -f "$armbian/userpatches/config-ti-k3-beagley-ai.conf" ]] || { echo 'TI K3 userpatches are not prepared' >&2; exit 1; }
command -v docker >/dev/null || { echo 'Docker is required for the pinned Armbian build' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Docker daemon unavailable or current user lacks access' >&2; exit 1; }
locked_ref='ubuntu:noble@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'
local_ref='ti-k3.local/ubuntu:noble'
docker pull --platform linux/amd64 "$locked_ref"
locked_id=$(docker image inspect --format '{{.Id}}' "$locked_ref")
docker tag "$locked_id" "$local_ref"
[[ $(docker image inspect --format '{{.Id}}' "$local_ref") == "$locked_id" ]] || { echo 'Pinned Armbian base-image alias verification failed' >&2; exit 1; }
(
  cd "$armbian"
  export CPUTHREADS="$jobs"
  export TI_K3_IMAGE_BUILD_JOBS="$jobs"
  export PREFER_DOCKER=yes
  export DOCKERFILE_USE_ARMBIAN_IMAGE_AS_BASE=no
  export DOCKER_ARMBIAN_BASE_IMAGE="$local_ref"
  export DOCKER_FORCE_PULL=no
  ./compile.sh build ti-k3-beagley-ai
)
