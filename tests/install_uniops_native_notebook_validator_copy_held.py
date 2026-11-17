#!/usr/bin/env python3
"""HELD source-only: local U2/U4/P3 validator COPY (never source or production).

Insert the existing protected Noel owner projection and canonical fictional
Personal Atlas grant BEFORE first signed U2 original/worker browser Actual.
Insert the independent signed native governor/outsider browser readback AFTER
signed U2/U4/P3 and BEFORE local schema lint. Never creates a second Result.
"""
import argparse
from pathlib import Path

U2='phase="signed integrated U1B source and U2 accepted-first original"\n'
LINT='phase="candidate domain schema lint"\n'
U4=' --u4-actual-followon'
BEFORE=r'''# Reviewed owner-ONLY disposable clone, not a migration or purchase:
phase="held native governor source and fictional Personal Atlas entitlement"
test "${ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY:-}" = true
test "${ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED:-}" = true
test "${ATLAS_NATIVE_SIGNED_READBACK_ENABLED:-}" = true
test -s "$repo_root/tests/uniops-native-governor-held-candidate.sql"
test -s "$repo_root/tests/uniops_native_governor_test_access_local_held.py"
test -s "$repo_root/tests/reconcile_uniops_native_governor_acl_local_held.py"
test -s "$repo_root/supabase/migrations/20260912203347_personal_atlas_access_grants_v1.sql"
# A private *fixed vocabulary* marker records the first failed local source
# gate without leaking PG error text, JWTs, SQL, fixture data or credentials.
# The separately reviewed controller may classify only this one file.
native_pre_u2_marker="$artifacts_dir/uniops-native-pre-u2-stage.safe"
native_pre_u2_stage() {
 case "$1" in
  projection_fingerprint_check|projection_source_mismatch|projection_source_probe_refused|projection_install_refused|grant_source_refused|grant_receipt_refused|signed_u2_ready) ;;
  *) return 1 ;;
 esac
 printf 'UNI_OPS_NATIVE_PRE_U2_STAGE=%s\n' "$1" > "$native_pre_u2_marker"
}
native_pre_u2_stage projection_fingerprint_check
# The immutable owner projection already checks this exact source fingerprint.
# This read-only precheck disambiguates source drift from PL/SQL compilation.
if ! native_projection_md5="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "
 SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND
 p.proname='company_work_accountability_native_ledger_self_api_v1'
" 2> "$artifacts_dir/uniops-native-source-preflight-private.log")"; then
 native_pre_u2_stage projection_source_probe_refused
 exit 1
fi
if [ "$native_projection_md5" != '302be9714957f5bf76d665092c9609b1' ]; then
 native_pre_u2_stage projection_source_mismatch
 exit 1
fi
unset native_projection_md5
if ! psql "$database_url" -X -v ON_ERROR_STOP=1 \
 -f "$repo_root/tests/uniops-native-governor-held-candidate.sql" \
 > "$artifacts_dir/uniops-native-owner-source-private.log" 2>&1; then
 native_pre_u2_stage projection_install_refused
 exit 1
fi
# This optional function-specific ACL replay is safe only when the restored
# function matches its pinned migration and has exact default PUBLIC EXECUTE.
# Any other condition refuses; it never changes production or broad defaults.
if ! ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED=true \
python3 "$repo_root/tests/reconcile_uniops_native_governor_acl_local_held.py" \
 --db-url "$database_url" \
 --canonical-migration "$repo_root/supabase/migrations/20260912203347_personal_atlas_access_grants_v1.sql" \
 > "$artifacts_dir/uniops-native-test-access-private.log" 2>&1; then
 native_pre_u2_stage grant_source_refused
 exit 1
fi
if ! ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED=true \
python3 "$repo_root/tests/uniops_native_governor_test_access_local_held.py" \
 --db-url "$database_url" \
 > "$artifacts_dir/uniops-native-test-access-private.log" 2>&1; then
 native_pre_u2_stage grant_source_refused
 exit 1
fi
if ! grep -qx 'PASS ATLAS_NATIVE_GOVERNOR_AUTHORIZED_TEST_GRANT=PASS' \
 "$artifacts_dir/uniops-native-test-access-private.log"; then
 native_pre_u2_stage grant_receipt_refused
 exit 1
fi
native_pre_u2_stage signed_u2_ready

'''
AFTER=r'''# Worker browser Actual/accepted Result/P3 snapshots must already be true.
phase="held native governor Done and outsider signed browser readback"
test "${ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY:-}" = true
test "${ATLAS_NATIVE_SIGNED_READBACK_ENABLED:-}" = true
test -s "$repo_root/tests/run-uniops-native-governor-readback-local.sh"
native_work="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "
SELECT w.id FROM atlas.work_items w
 JOIN atlas.work_result_acceptances a ON a.work_item_id=w.id
 JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
 WHERE w.organization_id='e5200000-0000-4000-8000-000000000801'::uuid
 AND w.source_object_type='rhythm_state'
 AND w.source_object_id='e5200000-0000-4000-8000-000000000d05'::uuid
 AND w.work_state='completed'
 AND w.result_contract_key='continuing_care_actual_v1'
 AND a.decision='accepted'
 AND r.result_contract_key='continuing_care_actual_v1'
 AND r.responsible_allocation_id IS NOT NULL
")"
[[ "$native_work" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]]
bash "$repo_root/tests/run-uniops-native-governor-readback-local.sh" \
 "$database_url" "$native_work" \
 > "$artifacts_dir/uniops-native-governor-private.log" 2>&1
grep -qx 'PASS ATLAS_NATIVE_GOVERNOR_DONE=PASS' \
 "$artifacts_dir/uniops-native-governor-private.log"
grep -qx 'PASS ATLAS_NATIVE_WORKER_BOUNDARY=PASS' \
 "$artifacts_dir/uniops-native-governor-private.log"
grep -qx 'PASS ATLAS_NATIVE_OUTSIDER_DENIAL=PASS' \
 "$artifacts_dir/uniops-native-governor-private.log"

'''
BEFORE=BEFORE.replace("\\${","${")
AFTER=AFTER.replace("\\${","${")

def install(text):
    if (not isinstance(text,str) or text.count(U2)!=1 or
        text.count(LINT)!=1 or text.count(U4)!=1 or
        text.count("signed_accepted_first_probe=true")!=1 or
        text.index(U2)>=text.index(LINT) or
        "ATLAS_NATIVE_GOVERNOR_DONE=PASS" in text or
        "uniops-native-governor-held-candidate.sql" in text or
        "ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK" in text):
        raise ValueError("Expected U2/U4 disposable validator not exact or already hooked")
    out=text.replace(U2,BEFORE+U2,1).replace(LINT,AFTER+LINT,1)
    for marker in (
      'phase="held native governor source and fictional Personal Atlas entitlement"',
      'phase="held native governor Done and outsider signed browser readback"',
      "ATLAS_NATIVE_GOVERNOR_DONE=PASS",
      "ATLAS_NATIVE_OUTSIDER_DENIAL=PASS",
      "signed_accepted_first_probe=true",U2,LINT,U4):
        if out.count(marker)!=1:
            raise ValueError("Native Notebook validator hook duplicated or missing")
    return out

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--validator-copy",required=True)
    a=p.parse_args()
    path=Path(a.validator_copy)
    if not path.is_file() or path.is_symlink() or (
      path.name!="validate-production-schema-clone.sh"):
        raise SystemExit("Refuse noncanonical disposable validator path")
    prepared=install(path.read_text(encoding="utf8"))
    path.write_text(prepared,encoding="utf8")
    print("PASS native governed source and browser readback attached to LOCAL validator COPY only")

if __name__=="__main__":
    main()
