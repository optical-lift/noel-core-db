#!/usr/bin/env bash
# Only for the protected manual Noel production workflow, never Atlas.
set -euo pipefail

version=20261015230001
name=noel_song_translation_constraint_graph_v1
expected_project=zirqkouammpwxlqfbsvf
migration="supabase/migrations/$version"_"$name.sql"
template=candidates/noel_song_translation_constraint_graph_v1/backfill_after_release_template.sql

if [[ "$CONFIRM_NOEL_PROJECT_REF" != "$expected_project" ]]; then
  echo 'Incorrect Noel project confirmation; no writes performed.' >&2
  exit 2
fi
if [[ -z "$NOEL_CORE_DATABASE_URL" || ! -f "$migration" || ! -f "$template" ]]; then
  echo 'Missing protected database credential, migration, or template.' >&2
  exit 2
fi
if [[ "$(git branch --show-current)" != main ]]; then
  echo 'Backfill is authorized only from main.' >&2
  exit 2
fi
export PGAPPNAME=noel-song-lxx-evidence-backfill
read_sql() {
  psql "$NOEL_CORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -A -t -F '|' -c "$1"
}
receipt=$(read_sql "SELECT name,encode(extensions.digest(convert_to('blob '||
 octet_length(convert_to(array_to_string(statements,E'\n'),'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(array_to_string(statements,E'\n'),'UTF8'),'sha1'),'hex')
 FROM supabase_migrations.schema_migrations WHERE version='$version';")
blob=$(git hash-object "$migration")
if [[ "$receipt" != "$name|$blob" ]]; then
  echo 'Live migration receipt does not match reviewed canonical migration.' >&2
  exit 1
fi
baseline_sql="WITH lexical AS (
 SELECT node_id,node_kind,parent_node_id,display_name,original_definition,operative_definition,
 authority_state,authority_basis,notes,metadata,is_active,created_at,updated_at
 FROM draft.noel_reality_nodes WHERE node_kind='lexical_pool'
)
SELECT (SELECT count(*) FROM lexical),(SELECT count(*) FROM draft.noel_reality_decisions),
(SELECT count(*) FROM draft.noel_mark_occurrence_bindings),
(SELECT md5(string_agg(md5(row_to_json(lexical)::text),'' ORDER BY node_id)) FROM lexical);"
baseline=$(read_sql "$baseline_sql")
if [[ "$baseline" != '287|196|306785|110a9c696db65826bc3cf3b280d31f53' ]]; then
 echo "Unexpected Noel founder or source baseline: $baseline" >&2
 exit 1
fi

action="${NOEL_EVIDENCE_ACTION:-verify_only}"
if [[ "$action" == populate_and_verify ]]; then
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
for bucket in $(seq 0 31); do
  sed "s/__BUCKET_0_TO_31__/$bucket/g" "$template" > "$tmp"
  if grep -q '__BUCKET_0_TO_31__' "$tmp"; then
    echo 'Unresolved bucket placeholder.' >&2
    exit 1
  fi
  echo "Noel-only evidence bucket $bucket / 31"
  psql "$NOEL_CORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$tmp"
  n=$(read_sql "SELECT count(*) FROM draft.noel_mark_lxx_choice_occurrences_v1
    WHERE mod(abs(hashtext(identity_id)::bigint),32)=$bucket;")
  echo "Verified cumulative rows in this bucket: $n"
done

elif [[ "$action" == verify_only ]]; then
  echo 'Noel evidence: verification-only mode; no backfill SQL will execute.'
else
  echo "Invalid Noel evidence action: $action" >&2
  exit 2
fi

if [[ "$(read_sql "$baseline_sql")" != "$baseline" ]]; then
  echo 'Noel founder or Hebrew source baseline changed; investigate.' >&2
  exit 1
fi
invalid=0
for bucket in $(seq 0 31); do
  invalid_bucket=$(read_sql "SELECT count(*) FROM draft.noel_mark_lxx_choice_occurrences_v1 e
   WHERE mod(abs(hashtext(e.identity_id)::bigint),32)=$bucket
   AND NOT EXISTS (
 SELECT 1 FROM draft.noel_mark_occurrence_bindings b
 JOIN draft.noel_mark_identity_forms f ON f.form_id=b.form_id
 JOIN core.alignment_segment_members sm
 ON sm.alignment_segment_id=e.alignment_segment_id AND sm.side='source'
 AND sm.source_token_id=e.source_token_id AND sm.member_order=e.source_member_order
 JOIN core.alignment_segments a ON a.alignment_segment_id=e.alignment_segment_id
 JOIN core.alignment_segment_members tm
 ON tm.alignment_segment_id=a.alignment_segment_id AND tm.side='target'
 AND tm.source_token_id=e.greek_token_id AND tm.member_order=e.target_member_order
 JOIN draft.lxx_tf_words_resolved_stage g
 ON g.tf_word_node=substring(tm.source_token_id FROM '[0-9]+$')::bigint
 WHERE b.witness_key=e.witness_key AND b.source_token_id=e.source_token_id
 AND b.form_id=e.form_id AND f.identity_id=e.identity_id
 AND a.source_token_count=e.source_segment_count
 AND a.target_token_count=e.target_segment_count
 AND g.greek_lex=e.greek_lexeme_key
);")
  if [[ "$invalid_bucket" != 0 ]]; then
    echo "Integrity test failed in hash bucket $bucket: $invalid_bucket invalid records" >&2
    exit 1
  fi
  echo "Verified source↔Greek membership bucket $bucket / 31"
done
if [[ "$invalid" != 0 ]]; then
  echo "Invalid Greek↔Hebrew evidence membership links: $invalid" >&2
  exit 1
fi
invalid_song=$(read_sql "SELECT count(*) FROM draft.noel_mark_song_anchor_choices_v1 x
 JOIN draft.noel_mark_lxx_choice_occurrences_v1 e ON e.choice_id=x.choice_id
 LEFT JOIN intelligence.v_canon_source_text_spine s
 ON s.witness_key=e.witness_key AND s.source_token_id=e.source_token_id
 WHERE s.source_token_id IS NULL OR s.canonical_book_code<>'Sng'
 OR (s.canonical_book_code||' '||s.chapter||':'||s.verse)<>x.song_canonical_ref
 OR e.identity_id<>x.identity_id;")
if [[ "$invalid_song" != 0 ]]; then
  echo "Invalid Song anchor provenance: $invalid_song" >&2
  exit 1
fi
song=$(read_sql "SELECT count(*) FROM draft.noel_mark_song_anchor_choices_v1 a
 JOIN draft.noel_mark_lxx_choice_occurrences_v1 e ON e.choice_id=a.choice_id
 WHERE e.source_token_id='tok.MT.Song.4.8.3' AND e.greek_lexeme_key='NU/MFH';")
jer=$(read_sql "SELECT count(*) FROM draft.noel_mark_lxx_choice_occurrences_v1
 WHERE source_token_id='tok.MT.Jer.2.32.4'
 AND mapping_scope='one_to_many' AND target_segment_count=2;")
if (( song < 1 || jer < 2 )); then
  echo "Song/Jeremiah acceptance evidence missing: song=$song jer=$jer" >&2
  exit 1
fi
totals=$(read_sql "SELECT (SELECT count(*) FROM draft.noel_mark_lxx_choice_occurrences_v1),
 (SELECT count(*) FROM draft.noel_mark_song_anchor_choices_v1),
 (SELECT count(DISTINCT identity_id) FROM draft.noel_mark_song_anchor_choices_v1),
 (SELECT count(*) FROM draft.noel_mark_translation_constraints_v1
 WHERE assessment_state='canon_excluded');")
echo "Noel evidence $action passed: choices|Song anchors|Song mark identities|exclusions=$totals"
echo "Unchanged founder baseline=$baseline"
if [[ -n "$GITHUB_STEP_SUMMARY" ]]; then
  {
    echo '### Noel Song–LXX evidence verified'
    echo "Version $version; sealed production migration receipt matched."
    echo "Choices | Song anchors | Song mark identities | exclusions: $totals"
    echo "Founder and source baseline unchanged: $baseline"
    echo "Verification mode: $action; 32 source-integrity checks completed."
    echo 'Song 4:8 and Jeremiah 2:32 phrase tests passed; no Atlas schema or application changes.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
