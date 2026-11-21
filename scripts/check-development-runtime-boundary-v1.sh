#!/usr/bin/env bash
# A fictional process-boundary experiment on the existing hosted custody runner.
# Never run this on Moonwell, RiverSong, or in the protected production job.
set -euo pipefail
umask 077
[[ "$GITHUB_ACTIONS" == true && "$RUNNER_ENVIRONMENT" == github-hosted && "$RUNNER_OS" == Linux && "$RUNNER_ARCH" == X64 ]]
[[ "$(uname -sm)" == "Linux x86_64" && -S /var/run/docker.sock ]]
[[ -z "${DOCKER_HOST:-}${DOCKER_CONTEXT:-}${DOCKER_TLS_VERIFY:-}${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]]
[[ "$(docker context show)" == default && "$(docker info --format '{{.OSType}}')" == linux ]]
root="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d "$RUNNER_TEMP/noel-boundary.XXXXXXXX")"
prefix="noel-boundary-$(basename "$work" | cut -d. -f2 | tr '[:upper:]' '[:lower:]')"
net="$prefix-local"
other="$prefix-other"
image="$prefix:fictional"
local_peer="$prefix-local-peer"
other_peer="$prefix-other-peer"
client="$prefix-client"
control="$prefix-control"
failed="$prefix-failed"
cleanup() {
    local result=$? bad=0 name
    trap - EXIT
    for name in "$client" "$control" "$failed" "$local_peer" "$other_peer"; do
        if docker container inspect "$name" >/dev/null 2>&1; then
            docker rm -f "$name" >/dev/null || bad=1
        fi
        if docker container inspect "$name" >/dev/null 2>&1; then bad=1; fi
    done
    for name in "$net" "$other"; do
        if docker network inspect "$name" >/dev/null 2>&1; then docker network rm "$name" >/dev/null || bad=1; fi
        if docker network inspect "$name" >/dev/null 2>&1; then bad=1; fi
    done
    if docker image inspect "$image" >/dev/null 2>&1; then docker image rm "$image" >/dev/null || bad=1; fi
    if docker image inspect "$image" >/dev/null 2>&1; then bad=1; fi
    rm -rf -- "$work" || bad=1
    [[ ! -e "$work" ]] || bad=1
    # A failed Docker daemon is not proof of successful cleanup.
    docker info --format '{{.OSType}}' >/dev/null || bad=1
    if (( bad )); then echo 'REFUSE: fictional resource cleanup failed' >&2; exit 1; fi
    echo 'PASS fictional resource cleanup'
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -m 755 "$work/root" "$work/admitted"
cc -std=c11 -Wall -Wextra -Werror -O2 -static "$root/tests/development-runtime-boundary-v1.c" -o "$work/root/boundary-probe"
chmod 755 "$work/root/boundary-probe"
printf 'fiction\n' > "$work/admitted/fixture.txt"
chmod 444 "$work/admitted/fixture.txt"
printf 'synthetic host-only marker\n' > "$work/host-marker"
export SYNTHETIC_HOST_SECRET=fictional_not_a_credential
# Build a scratch image from the fixed compiled fixture: no external image pulls.
tar -C "$work/root" -cf "$work/root.tar" boundary-probe
docker import "$work/root.tar" "$image" >/dev/null
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
[[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
for name in "$net" "$other"; do
    # Internal alone retains a host bridge address. Require isolated gateway mode.
    docker network create --internal --ipv6=false \
        --opt com.docker.network.bridge.gateway_mode_ipv4=isolated "$name" >/dev/null
    [[ "$(docker network inspect --format '{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}' "$name")" == 'true|false|isolated' ]]
done
flags=(--pull=never --user 65534:65534 --read-only --cap-drop ALL
    --security-opt no-new-privileges --ipc none --cgroupns private
    --pids-limit 32 --memory 64m --cpus 0.5
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=1m,mode=1777 --dns 127.0.0.1
    --entrypoint /boundary-probe)
docker run -d --name "$local_peer" --network "$net" "${flags[@]}" "$image_id" serve >/dev/null
docker run -d --name "$other_peer" --network "$other" "${flags[@]}" "$image_id" serve >/dev/null
local_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$local_peer")"
other_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$other_peer")"
[[ -n "$local_ip" && -n "$other_ip" && "$local_ip" != "$other_ip" ]]
# Positive control: the disallowed service really answers from its own network.
timeout 25 docker run --name "$control" --network "$other" "${flags[@]}" "$image_id" allow "$other_ip"
docker create --name "$client" --network "$net" "${flags[@]}" \
    --mount "type=bind,src=$work/admitted,dst=/admitted,readonly" \
    "$image_id" probe "$local_ip" "$other_ip" "$work/host-marker" >/dev/null
[[ "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}|{{.HostConfig.Privileged}}|{{.HostConfig.NetworkMode}}|{{len .Mounts}}' "$client")" == "true|false|$net|1" ]]
[[ "$(docker inspect --format '{{range .Mounts}}{{.Destination}}|{{.RW}}{{end}}' "$client")" == '/admitted|false' ]]
timeout 25 docker start -a "$client"
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$client")" == 0 ]]
# Exercise failing process exit and ensure it is not reported as proof success.
set +e
timeout 10 docker run --name "$failed" --network "$net" "${flags[@]}" "$image_id" fail
rc=$?
set -e
[[ "$rc" == 42 ]]
echo 'PASS bounded fictional failure propagation'
# The EXIT trap removes all experiment-owned resources and verifies absence.
