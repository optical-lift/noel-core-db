#!/usr/bin/env bash
# Disposable PG16 only. Two independent psql connections simulate parallel
# authenticated claims, NOT independently signed GoTrue/PostgREST sessions.
set -euo pipefail

program='61000000-0000-4000-8000-000000000201'
version='61000000-0000-4000-8000-000000000301'
user='61000000-0000-4000-8000-000000000001'

create_one() {
  local out="$1"
  psql -XAtq -v ON_ERROR_STOP=1 >"$out" <<SQL
SET ROLE authenticated;
SET request.jwt.claim.sub='$user';
SELECT public.personal_program_author_note_create_self_api_v1(
 '$program','$version','W1-A',NULL,
 'Identical concurrent author annotation.',
 'isolate-concurrent-create-001')->>'noteId';
SQL
}

create_one "$RUNNER_TEMP/note-create-a.out" &
pid_a=$!
create_one "$RUNNER_TEMP/note-create-b.out" &
pid_b=$!
wait "$pid_a"
wait "$pid_b"
note_a="$(tail -n1 "$RUNNER_TEMP/note-create-a.out" | tr -d '[:space:]')"
note_b="$(tail -n1 "$RUNNER_TEMP/note-create-b.out" | tr -d '[:space:]')"
if [[ ! "$note_a" =~ ^[0-9a-f-]{36}$ || "$note_a" != "$note_b" ]]; then
  echo 'Concurrent create failed exact idempotent note identity' >&2
  exit 1
fi

count="$(psql -XAtq -v ON_ERROR_STOP=1 -c \
  "SELECT count(*) FROM atlas.personal_program_author_note_events
   WHERE program_id='$program' AND request_key='isolate-concurrent-create-001';" \
  | tr -d '[:space:]')"
if [[ "$count" != "1" ]]; then
  echo "Concurrent create admitted $count events instead of one" >&2
  exit 1
fi

# Competing revisions have different request keys. Only one may advance the
# note from rev 1 to 2, even if both sessions begin at the same expected rev.
revise_one() {
  local out="$1" id="$2"
  psql -XAtq -v ON_ERROR_STOP=1 >"$out" 2>&1 <<SQL
SET ROLE authenticated;
SET request.jwt.claim.sub='$user';
SELECT public.personal_program_author_note_revise_self_api_v1(
 '$program','$note_a',1,
 'Competing change $id.','resolved',
 'isolate-concurrent-revision-$id')->>'revision';
SQL
}

revise_one "$RUNNER_TEMP/note-revise-a.out" a &
pid_a=$!
revise_one "$RUNNER_TEMP/note-revise-b.out" b &
pid_b=$!
set +e
wait "$pid_a"
rc_a=$?
wait "$pid_b"
rc_b=$?
set -e
if ! { [[ "$rc_a" == 0 && "$rc_b" != 0 ]] ||
       [[ "$rc_a" != 0 && "$rc_b" == 0 ]]; }; then
  echo "Competing revisions were not exactly one success/one conflict ($rc_a/$rc_b)" >&2
  exit 1
fi
if [[ "$rc_a" != 0 ]] && ! grep -q 'Stale annotation revision' "$RUNNER_TEMP/note-revise-a.out"; then
  echo 'First revision failed for a reason other than stale expected revision' >&2
  exit 1
fi
if [[ "$rc_b" != 0 ]] && ! grep -q 'Stale annotation revision' "$RUNNER_TEMP/note-revise-b.out"; then
  echo 'Second revision failed for a reason other than stale expected revision' >&2
  exit 1
fi
count="$(psql -XAtq -v ON_ERROR_STOP=1 -c \
  "SELECT count(*) FROM atlas.personal_program_author_note_events
   WHERE program_id='$program' AND note_id='$note_a' AND revision=2;" \
  | tr -d '[:space:]')"
if [[ "$count" != "1" ]]; then
  echo "Competing revisions produced $count revision-two events" >&2
  exit 1
fi
echo 'Parallel create serialized; competing updates produced one source-verified revision and one stale conflict.'
