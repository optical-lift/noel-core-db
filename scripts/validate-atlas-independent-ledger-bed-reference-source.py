#!/usr/bin/env python3
"""Static safety contract for held multi-Ledger reference-only source.

Run from repository root: python3 scripts/validate-atlas-independent-ledger-bed-reference-source.py
STATIC ONLY: deliberately not a substitute for Postgres parsing or real signed
GoTrue/PostgREST execution on a protected PG17 full-schema disposable clone.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/"candidates/atlas/ledger_work_existing_object_reference_v1"
sql=(DIR/"HELD_source_candidate.sql").read_text(encoding="utf-8")
clone=(DIR/"clone_test_api_DISPOSABLE_ONLY.sql").read_text(encoding="utf-8")
signed=(ROOT/"scripts/validate-atlas-independent-ledger-bed-reference-signed-http.py").read_text(encoding="utf-8")

required_source=(
    "CREATE TABLE atlas.ledger_work_existing_bed_references_v1",
    "ALTER TABLE atlas.ledger_work_existing_bed_references_v1 ENABLE ROW LEVEL SECURITY",
    "REVOKE ALL ON TABLE",
    "FROM PUBLIC, anon, authenticated",
    "CREATE FUNCTION atlas.establish_ledger_work_existing_bed_reference_self_v1",
    "LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''",
    "auth.uid() IS NULL",
    "reality_access_self_api_v1",
    "current_person_id_v1",
    "current_principal_id_v1",
    "person_has_native_ledger_connection_v1",
    "current_active_ledger_seat_v1",
    "company_work_native_ledger_relevance",
    "principal_has_ledger_authority_v1",
    "ledger_occurrence_shared_work_actor_self_v1",
    "FROM atlas.growing_objects bed",
    "farm.organization_id=p_organization_id",
    "farm.status='active'",
    "work_state<>'open'",
    "ERRCODE='23505'",
    "'newWorkCreated',false",
    "'newObjectCreated',false",
    "'physicalCustodyChanged',false",
    "'otherLedgerReadGranted',false",
    "REVOKE ALL ON FUNCTION",
)
required_test=(
    '"owner"', '"worker"', '"outsider"', '"no-seat"',
    "DELETE FROM auth.sessions",
    "Flower custody must remain unchanged",
    "No Work duplicated",
    "No real-world Bed duplicated",
    "original Flower Bed",
    "127[.]0[.]0[.]1",
)
for name,check_text in (("held source",sql),("signed test",signed)):
    needed=required_source if name=="held source" else required_test
    missing=[x for x in needed if x not in check_text]
    if missing:
        raise SystemExit(f"FAIL {name}: missing source guarantees: {missing}")
if re.search(r"\bINSERT\s+INTO\s+atlas\.(?:work_items|growing_objects)\b",sql,re.I):
    raise SystemExit("FAIL: cross-Ledger reference source may not duplicate original Work/Bed")
if re.search(r"\b(?:CREATE\s+OR\s+REPLACE|ALTER)\s+FUNCTION\s+atlas\.guard_work_growing_object_context_v1",sql,re.I):
    raise SystemExit("FAIL: original Flower source guard must remain unchanged")
if "offer_venue_bed_shared_use" in sql or "accept_venue_bed_shared_use" in sql:
    raise SystemExit("FAIL: mere Ledger Work reference must not require another Ledger's governor")
if "GRANT EXECUTE" in sql or "GRANT SELECT" in sql:
    raise SystemExit("FAIL: held source must not release new runtime authority")
if not all(x in clone for x in (
    "current_database() <> 'postgres'",
    "current_setting('server_version_num')",
    "clone-upick-bed-3",
    "SECURITY DEFINER",
    "REVOKE ALL ON FUNCTION",
    "GRANT EXECUTE ON FUNCTION public.clone_test_",
)):
    raise SystemExit("FAIL: signed transport must be guarded as clone-only")
if re.search(r"GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+atlas\.",clone,re.I):
    raise SystemExit("FAIL: direct source-function access must remain private")
print("PASS STATIC independent target-Ledger original Work references one Bed")
print("PASS STATIC no Flower grant ceremony, duplicate Bed/Work, source mutation or broad ACL")
print("HELD: PostgreSQL parse, protected signed runtime, owner release and browser UI unproven")
