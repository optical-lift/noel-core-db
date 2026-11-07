#!/usr/bin/env python3
"""Patch only a throwaway checkout of the canonical local clone controller.

TEST-ONLY. Does not change repo main, a release migration, production DB,
permissions, caller identity, or any trusted global runner settings.
The reviewed exact controller anchors must match once or fail closed.
"""
import argparse
from pathlib import Path

def one(text, original, replacement, label):
    if text.count(original) != 1:
        raise SystemExit("STOP: canonical clone source changed: " + label)
    return text.replace(original, replacement, 1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--controller", required=True)
    opts = p.parse_args()
    target = Path(opts.controller)
    text = target.read_text(encoding="utf-8")
    if "signed_company_probe" in text or "UNI-OPS SIGNED HOOK" in text:
        raise SystemExit("STOP: signed source hook already installed")

    text = one(text, "signed_http_probe=false\n",
               "signed_http_probe=false\nsigned_company_probe=true\n",
               "one locally controlled signed test flag")
    text = one(
        text,
        '       [ "$signed_person_mail_probe" = true ]; then\n',
        '       [ "$signed_person_mail_probe" = true ] ||\n'
        '       [ "$signed_company_probe" = true ]; then\n',
        "require local GoTrue and REST")
    text = one(
        text,
        '    if [ "$signed_care_single_done_probe" = true ] ||\n',
        '     if [ "$signed_company_probe" = true ] ||\n'
        '        [ "$signed_care_single_done_probe" = true ] ||\n',
        "use existing minimum GoTrue/REST local services")
    hook = r'''
# UNI-OPS SIGNED HOOK: exact-source disposable local clone only.
# The protected workflow pins all input blobs, runs ordinary schema
# postconditions FIRST, and keeps this entire patch in ephemeral checkout.
if [ "$signed_company_probe" = true ]; then
  test -n "${SIGNED_COMPANY_C1_FIXTURE:-}"
  test -n "${SIGNED_COMPANY_HARVEST_FIXTURE:-}"
  test -n "${SIGNED_COMPANY_PROBE_SCRIPT:-}"
  test -n "${SIGNED_COMPANY_TRANSPORT_SQL:-}"
  test -n "${SIGNED_COMPANY_WORK_BED_FIXTURE:-}"
  phase="signed Farm-to-Company original C1 fixture"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$SIGNED_COMPANY_C1_FIXTURE" \
    >"$artifacts_dir/uniops-signed-c1-fixture.log" 2>&1
  phase="native nonweekly Harvest generated source witness"
  PGOPTIONS='-c uni_ops.disposable_clone=true' \
    psql "$database_url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose \
    -f "$SIGNED_COMPANY_HARVEST_FIXTURE" \
    >"$artifacts_dir/uniops-signed-harvest-fixture.log" 2>&1
  phase="source-guarded fictional Work-to-Bed prerequisites"
  PGOPTIONS='-c uni_ops.disposable_clone=true' \
    psql "$database_url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose \
    -f "$SIGNED_COMPANY_WORK_BED_FIXTURE" \
    >"$artifacts_dir/uniops-physical-work-source-private.log" 2>&1
  phase="exact original Harvest Journal manifest"
  psql "$database_url" -X -A -t -v ON_ERROR_STOP=1 \
    -c "SELECT jsonb_build_object(
      'kind','uni_ops_farm_company_source_test_only_v1',
      'organizationId','e5200000-0000-4000-8000-000000000801',
      'governingLedgerId','e5200000-0000-4000-8000-000000000401',
      'farmId','e5200000-0000-4000-8000-000000000b01',
      'attentionJournalId',j.id,
      'nativeSubjectId',j.source_id,
      'governorPersonId','e5200000-0000-4000-8000-000000000101')::text
    FROM atlas.journal_event_index j
    WHERE j.event_key='harvest-preparation-needs-owner-direction:fa510000-0000-4000-8000-000000000003'
      AND j.provenance->>'sourceObservationId'='fa510000-0000-4000-8000-000000000004'" \
    >"$RUNNER_TEMP/uniops-farm-company-source-manifest.json" \
    2>"$artifacts_dir/uniops-signed-manifest-stderr.log"
  python3 - "$RUNNER_TEMP/uniops-farm-company-source-manifest.json" <<'PY_MANIFEST'
import json,sys,uuid
from pathlib import Path
lines=Path(sys.argv[1]).read_text(encoding='utf-8').strip().splitlines()
if len(lines)!=1:
    raise SystemExit('STOP: no unique source-generated Farm Journal')
obj=json.loads(lines[0])
for k in ('organizationId','governingLedgerId','farmId',
          'attentionJournalId','nativeSubjectId','governorPersonId'):
    uuid.UUID(str(obj[k]))
if obj['kind']!='uni_ops_farm_company_source_test_only_v1':
    raise SystemExit('STOP: wrong fictional Farm source manifest')
PY_MANIFEST
  # Only the disposable clone has this exact C1 and native source evidence.
  # Validate before installing the separately source-pinned DEFAULT-CLOSED
  # wrapper, with no authenticated EXECUTE grant or production migration.
  phase="default-closed known-case transport installed in disposable clone"
  test "$(psql "$database_url" -X -A -t -v ON_ERROR_STOP=1 \
    -c "SELECT (current_database()='postgres' AND
      current_setting('server_version_num')::integer/10000=17 AND
      (SELECT count(*) FROM auth.users
       WHERE id IN (
        'e5200000-0000-4000-8000-000000000001'::uuid,
        'e5200000-0000-4000-8000-000000000002'::uuid,
        'e5200000-0000-4000-8000-000000000003'::uuid,
        'e5200000-0000-4000-8000-000000000004'::uuid))=4 AND
      EXISTS(SELECT 1 FROM atlas.journal_event_index
        WHERE event_key='harvest-preparation-needs-owner-direction:fa510000-0000-4000-8000-000000000003') AND
      to_regprocedure('public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)') IS NULL)" \
    2>"$artifacts_dir/uniops-local-transport-guard-private.log")" = 't'
  psql "$database_url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose \
    -f "$SIGNED_COMPANY_TRANSPORT_SQL" \
    >"$artifacts_dir/uniops-default-closed-transport-private.log" 2>&1
  phase="genuine signed Farm-to-Company private source matrix"
  python3 "$SIGNED_COMPANY_PROBE_SCRIPT" \
    --db-url "$database_url" \
    --fixture-manifest "$RUNNER_TEMP/uniops-farm-company-source-manifest.json" \
    --output "$artifacts_dir/uniops-farm-company-signed-summary.txt" \
    >"$artifacts_dir/uniops-farm-company-signed-private.log" 2>&1
  grep -q '^PASS local real GoTrue sessions' \
    "$artifacts_dir/uniops-farm-company-signed-summary.txt"
fi
'''
    anchor = ('if [ "$signed_http_probe" = true ]; then\n'
              '  phase="signed local HTTP API authorization matrix"\n')
    text = one(text, anchor, hook + "\n" + anchor,
               "post-DDL and pre-existing signed runner injection")
    target.write_text(text, encoding="utf-8")
    print("PASS only the disposable Company signed hook and local GoTrue startup were installed")


if __name__ == "__main__":
    main()
