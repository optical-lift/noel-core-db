#!/usr/bin/env bash
# Fixed synthetic test only; no schema snapshot, production credentials or candidate execution.
set -euo pipefail
umask 077
[[ "$GITHUB_ACTIONS" == true && "$RUNNER_ENVIRONMENT" == github-hosted && "$RUNNER_OS" == Linux && "$RUNNER_ARCH" == X64 ]]
[[ "$(uname -sm)" == "Linux x86_64" && -S /var/run/docker.sock ]]
[[ -z "${DOCKER_HOST:-}${DOCKER_CONTEXT:-}${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]]
[[ "$(docker context show)" == default && "$(docker info --format '{{.OSType}}')" == linux ]]
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cli="$RUNNER_TEMP/supabase"
[[ "$("$cli" --version | tail -n1)" == 2.116.0 ]]
"$cli" start --help >"$RUNNER_TEMP/development-stack-help.txt"
grep -q -- '--network-id' "$RUNNER_TEMP/development-stack-help.txt"
work="$(mktemp -d "$RUNNER_TEMP/noel-signed-stack.XXXXXXXX")"
project="devproof_$(basename "$work" | cut -d. -f2 | tr '[:upper:]' '[:lower:]')"
net="$project-isolated"; other="$project-excluded"; image="$project:fictional"
db="supabase_db_$project"; auth="supabase_auth_$project"; rest="supabase_rest_$project"; gateway="supabase_kong_$project"
peer="$project-peer"; client="$project-client"; sqlclient="$project-sql"; control="$project-control"; dbprobe="$project-dbprobe"
started=false
cleanup() {
 local rc=$? bad=0 name
 trap - EXIT
 for name in "$peer" "$client" "$sqlclient" "$control" "$dbprobe"; do
   if docker container inspect "$name" >/dev/null 2>&1; then docker rm -f "$name" >/dev/null || bad=1; fi
 done
 if [[ "$started" == true ]]; then
   (cd "$work"; "$cli" stop --no-backup --network-id "$net") >"$work/stop.log" 2>&1 || bad=1
 fi
 for name in "$db" "$auth" "$rest" "$gateway" "$peer" "$client" "$sqlclient" "$control" "$dbprobe"; do
   if docker container inspect "$name" >/dev/null 2>&1; then bad=1; fi
 done
 # Scope all inspection to the unique project; never use global prune or stop --all.
 if docker ps -a --format '{{.Names}}' | grep -F "$project" >/dev/null; then bad=1; fi
 if docker volume ls --format '{{.Name}}' | grep -F "$project" >/dev/null; then bad=1; fi
 for name in "$net" "$other"; do
   if docker network inspect "$name" >/dev/null 2>&1; then docker network rm "$name" >/dev/null || bad=1; fi
   if docker network inspect "$name" >/dev/null 2>&1; then bad=1; fi
 done
 if docker image inspect "$image" >/dev/null 2>&1; then docker image rm "$image" >/dev/null || bad=1; fi
 rm -rf -- "$work" || bad=1
 docker info --format '{{.OSType}}' >/dev/null || bad=1
 if ((bad)); then echo 'REFUSE: fictional stack cleanup failed' >&2; exit 1; fi
 echo 'PASS fictional signed stack resource cleanup'
 exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$work"
"$cli" init --force >/dev/null
python3 - "$project" <<'PY'
import re,sys
from pathlib import Path
p=Path("supabase/config.toml")
s=p.read_text()
s,n=re.subn(r'^project_id\s*=.*$',f'project_id = "{sys.argv[1]}"',s,count=1,flags=re.M)
assert n==1
sec=""
lines=[]
for line in s.splitlines():
    if line.strip().startswith("["): sec=line.strip()
    if sec=="[db]" and re.match(r'^major_version\s*=',line): line="major_version = 17"
    lines.append(line)
p.write_text("\n".join(lines)+"\n")
PY
for name in "$net" "$other"; do
 docker network create --internal --ipv6=false --opt com.docker.network.bridge.gateway_mode_ipv4=isolated "$name" >/dev/null
 [[ "$(docker network inspect --format '{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}' "$name")" == 'true|false|isolated' ]]
done
# The same minimal service set and exact Supabase CLI as the canonical clone.
started=true
if ! "$cli" start --network-id "$net" -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$work/start.log" 2>&1; then
 echo 'REFUSE: pinned fictional Supabase startup failed (no production access)' >&2
 # Only print fixed diagnostic categories, never CLI keys or arbitrary output.
 grep -Ei '(^Error|failed|health|rate.limit|denied|not found|network)' "$work/start.log" | cut -c1-200 | tail -n12 >&2 || true
 exit 1
fi
for name in "$db" "$auth" "$rest" "$gateway"; do
 [[ "$(docker inspect --format '{{.State.Running}}|{{.HostConfig.Privileged}}|{{len .NetworkSettings.Networks}}' "$name")" == 'true|false|1' ]]
 [[ "$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$name")" == "$net" ]]
 [[ "$(docker inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "$name")" != *docker.sock* ]]
done
[[ "$(docker network inspect --format '{{len .Containers}}' "$net")" == 4 ]]
db_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$db")"
api_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$gateway")"
[[ "$db_ip" =~ ^[0-9.]+$ && "$api_ip" =~ ^[0-9.]+$ ]]
# Only the trusted host gets CLI status; pass solely the local anon key over stdin.
"$cli" status --network-id "$net" -o env >"$work/status.env" 2>"$work/status.log"
python3 - "$work/status.env" "$work/anon" <<'PY'
import sys
from pathlib import Path
d=dict(line.split("=",1) for line in Path(sys.argv[1]).read_text().splitlines() if "=" in line)
key=(d.get("ANON_KEY") or d.get("SUPABASE_ANON_KEY") or "").strip().strip('"')
assert len(key)>20 and not any(c.isspace() for c in key)
assert (d.get("API_URL") or "").strip('"').startswith(("http://127.0.0.1:","http://localhost:"))
Path(sys.argv[2]).write_text(key+"\n")
PY
rm "$work/status.env"
# SQL client uses the local stack's exact database image, no mounted host checkout.
db_image="$(docker inspect --format '{{.Image}}' "$db")"
[[ "$db_image" =~ ^sha256:[0-9a-f]{64}$ ]]
mkdir -m 755 "$work/root" "$work/admitted"
cp "$root/tests/development-signed-stack-v1.sql" "$work/admitted/fixture.sql"
chmod 444 "$work/admitted/fixture.sql"
flags=(--pull=never --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges
 --ipc none --cgroupns private --pids-limit 64 --memory 128m --cpus 1 --tmpfs /tmp:rw,noexec,nosuid,nodev,size=4m,mode=1777)
test "$(timeout 25 docker run --rm --network "$net" "${flags[@]}" -e PGPASSWORD=postgres --entrypoint psql "$db_image" -h "$db_ip" -U postgres -d postgres -XAtqc "select current_setting('server_version_num')::int/10000")" = 17
timeout 45 docker run --name "$sqlclient" --network "$net" "${flags[@]}" -e PGPASSWORD=postgres \
 --mount "type=bind,src=$work/admitted,dst=/admitted,readonly" --entrypoint psql "$db_image" \
 -h "$db_ip" -U postgres -d postgres -X -v ON_ERROR_STOP=1 -f /admitted/fixture.sql >"$work/fixture.log" 2>&1 || { echo 'REFUSE: fictional SQL fixture failed'; tail -n10 "$work/fixture.log"; exit 1; }
echo 'PASS independent isolated PostgreSQL 17 SQL client'
# No third-party Go dependency or downloaded test image.
CGO_ENABLED=0 GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -trimpath -o "$work/root/probe" "$root/tests/development-signed-stack-v1.go"
tar -C "$work/root" -cf "$work/root.tar" probe
docker import "$work/root.tar" "$image" >/dev/null
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
[[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
docker run -d --name "$peer" --network "$other" "${flags[@]}" --entrypoint /probe "$image_id" serve >/dev/null
other_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$peer")"
timeout 15 docker run --name "$control" --network "$other" "${flags[@]}" --entrypoint /probe "$image_id" positive "$other_ip:18080"
# Share the real database service's network namespace only, not its filesystem or capabilities.
timeout 15 docker run --name "$dbprobe" --network "container:$db" "${flags[@]}" --entrypoint /probe "$image_id" network "$api_ip:8000" "$other_ip:18080"
sleep 2
timeout 100 docker run -i --name "$client" --network "$net" "${flags[@]}" --entrypoint /probe "$image_id" signed "$api_ip:8000" <"$work/anon"
rm "$work/anon"
