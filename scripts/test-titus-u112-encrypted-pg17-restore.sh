#!/usr/bin/env bash
# U1.12: genuine encrypted PG17 restore using FICTIONAL data only.
# Docker network=none, no secret DB URL, no real customer rows or migration.
set -Eeuo pipefail
command -v docker >/dev/null
command -v openssl >/dev/null
command -v python3 >/dev/null
root="$(cd "$(dirname "$0")/.." && pwd -P)"
name="titus-u112-fixture-$RANDOM-$RANDOM"
work="$(mktemp -d)"
vault="$work/vault"
mkdir -m 700 "$vault"
umask 077
started=0
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [ "$started" -eq 1 ]; then
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT INT TERM

openssl req -x509 -newkey rsa:3072 -nodes \
  -keyout "$work/fictional-private.pem" -out "$work/fictional-public.pem" \
  -days 1 -subj '/CN=titus-u112-fictional-only' >/dev/null 2>&1

docker run -d --rm --name "$name" --network none \
  --mount "type=bind,src=$root,dst=/source,readonly" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=postgres \
  postgres:17 -c listen_addresses='' >/dev/null
started=1

ready=0
for i in $(seq 1 60); do
  if [ "$(docker exec "$name" psql -U postgres -d postgres -Atqc \
    "select current_setting('server_version_num')::int/10000, inet_server_addr() is null" \
    2>/dev/null || true)" = '17|t' ]; then
    ready=1
    break
  fi
  sleep 1
done
test "$ready" = 1
docker exec "$name" createdb -U postgres historical_source
docker exec "$name" createdb -U postgres historical_clone

# The fixture contains only a fictional Course, two Units and three revisions.
docker exec "$name" psql -X -v ON_ERROR_STOP=1 -U postgres \
  -d historical_source \
  -f /source/candidates/shared-teaching-course-clean-cutover-v1/U1_12_FICTIONAL_PG17_ORIGINALS.sql \
  >/dev/null
docker exec "$name" pg_dump -U postgres -d historical_source \
  --schema-only --schema=titus \
  | docker exec -i "$name" psql -X -v ON_ERROR_STOP=1 -U postgres \
    -d historical_clone >/dev/null

# PostgreSQL custom-format DATA archive; plaintext is piped directly
# into CMS encryption, never saved to a filesystem.
docker exec "$name" pg_dump -U postgres -d historical_source \
  --format=custom --data-only \
  --table=titus.course --table=titus.unit --table=titus.unit_revision \
  | python3 "$root/scripts/titus-u112-sealed-custody-transport.py" seal \
    --vault-dir "$vault" --name fictional-pg17 \
    --certificate "$work/fictional-public.pem" >/dev/null

python3 "$root/scripts/titus-u112-sealed-custody-transport.py" verify \
  --vault-dir "$vault" --name fictional-pg17 \
  --certificate "$work/fictional-public.pem" \
  --private-key "$work/fictional-private.pem" >/dev/null

# A separate PostgreSQL database restores the sealed archive via pipe.
# No decrypted archive files are ever written.
openssl cms -decrypt -binary -inform DER \
  -in "$vault/fictional-pg17.capsule.cms" \
  -recip "$work/fictional-public.pem" \
  -inkey "$work/fictional-private.pem" 2>/dev/null \
  | docker exec -i "$name" pg_restore \
    -U postgres -d historical_clone \
    --data-only --no-owner --exit-on-error --single-transaction >/dev/null 2>&1

fingerprint="select md5(
  (select coalesce(string_agg(row_to_json(c)::text,'|' order by c.id),'') from titus.course c)
  ||'#'||
  (select coalesce(string_agg(row_to_json(u)::text,'|' order by u.id),'') from titus.unit u)
  ||'#'||
  (select coalesce(string_agg(row_to_json(r)::text,'|' order by r.id),'') from titus.unit_revision r)
)"
original="$(docker exec "$name" psql -U postgres -d historical_source -Atqc "$fingerprint")"
restored="$(docker exec "$name" psql -U postgres -d historical_clone -Atqc "$fingerprint")"
test -n "$original"
test "$original" = "$restored"
test "$(docker exec "$name" psql -U postgres -d historical_clone -Atqc \
  'select count(*) from titus.course')" = 1
test "$(docker exec "$name" psql -U postgres -d historical_clone -Atqc \
  'select count(*) from titus.unit')" = 2
test "$(docker exec "$name" psql -U postgres -d historical_clone -Atqc \
  'select count(*) from titus.unit_revision')" = 3

# Mutation negative: one altered historical body must be detected.
docker exec "$name" psql -U postgres -d historical_clone -X -v ON_ERROR_STOP=1 \
  -c "update titus.unit_revision set body_text=body_text||E'\r' where revision_number=2" >/dev/null
changed="$(docker exec "$name" psql -U postgres -d historical_clone -Atqc "$fingerprint")"
test "$original" != "$changed"

echo 'PASS fictional PG17 encrypted custom-format backup, independent verification, isolated restore, Course/Unit/revision preservation, and mutation detection; no real data'
