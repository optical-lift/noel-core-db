#!/usr/bin/env python3
"""No-network source guard for held universal U2F command catalog declaration."""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/"candidates/atlas/uni_ops_u2f_universal_delegated_command_v1"
SQL=(FOLDER/"candidate.sql").read_text(encoding="utf8")
README=(FOLDER/"README.md").read_text(encoding="utf8")
KERNEL=(ROOT/"supabase/migrations/20260928002435_atlas_delegated_agent_command_kernel_v1.sql").read_text(encoding="utf8")
ALLOWLIST=(ROOT/"supabase/migrations/20260928003036_atlas_delegated_agent_explicit_allowlist_v1.sql").read_text(encoding="utf8")
TARGET=(ROOT/"supabase/migrations/20260928003952_atlas_delegated_agent_target_contract_v1.sql").read_text(encoding="utf8")
SOURCE=re.sub(r"(?m)^\s*--[^\n]*","",SQL)
NATIVE_IDENTITY=(FOLDER/"02_native_ledger_carrier_identity_held.sql").read_text(encoding="utf8")
NATIVE_SOURCE=re.sub(r"(?m)^\s*--[^\n]*","",NATIVE_IDENTITY)

class UniversalDelegatedDraftOnly(unittest.TestCase):
    def test_existing_canonical_registry_not_new_table_or_second_work(self):
        self.assertIn("create table if not exists atlas.delegated_agent_authorizations",KERNEL.lower())
        self.assertIn("references ledger.ledgers(id)",KERNEL.lower())
        self.assertIn("create table if not exists atlas.agent_command_definitions",KERNEL.lower())
        self.assertIn("create table if not exists atlas.agent_command_invocations",KERNEL.lower())
        self.assertIn("to_regclass('atlas.work_items')",SOURCE)
        self.assertEqual(len(re.findall(r"\bINSERT\s+INTO\s+atlas\.agent_command_definitions\s*\(",SOURCE,re.I)),1)
        self.assertNotRegex(SOURCE,r"(?i)\b(?:CREATE|DROP|ALTER|TRUNCATE)\s+(?:TABLE|FUNCTION|VIEW|SCHEMA|TRIGGER)\b")
        self.assertNotRegex(SOURCE,r"(?i)\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+atlas\.(?:work_items|tasks|task_release_queue_items|delegated_agent_carriers|delegated_agent_credentials|delegated_agent_authorizations|agent_command_invocations)\b")

    def test_intentionally_unexecutable_without_registered_actor(self):
        for s in (
            "'work.original.establish_one'", "'ledger','commit','principal_explicit'",
            "'u2f_held_no_executable_handler_v1','draft'",
            "status='draft'", "status='active'",
            "'executable',false","'autoNextWork',false",
            "'noLegacyTaskOrQueueFallback',true",
            "'maxOriginalsPerCampaign',1",
        ):
            with self.subTest(required=s):
                self.assertIn(s,SOURCE)
        self.assertIn("v_command.status<>'active'",ALLOWLIST)
        self.assertIn("command_not_active",ALLOWLIST)
        self.assertIn("target_kind_required",TARGET)
        self.assertIn("target_id_required",TARGET)

    def test_identity_guard_fails_on_source_drift_or_existing_command(self):
        self.assertIn("28bbb95ce3874a7dbf641387c22ac1fd",SOURCE)
        self.assertIn("md5(pg_catalog.pg_get_functiondef",SOURCE)
        self.assertIn("command_key='work.original.establish_one'",SOURCE)
        self.assertIn("command identity already exists",SOURCE)
        self.assertIn("RAISE EXCEPTION",SOURCE)
        self.assertEqual(SOURCE.count("BEGIN;"),1)
        self.assertEqual(SOURCE.count("COMMIT;"),1)

    def test_no_activation_backdoors_or_grants(self):
        self.assertNotRegex(SOURCE,r"(?i)\b(?:GRANT|REVOKE|CREATE\s+ROLE|SET\s+ROLE|SET\s+SESSION\s+AUTHORIZATION|SECURITY\s+DEFINER|CREATE\s+EXTENSION)\b")
        self.assertNotIn("auth.uid()",SOURCE)
        self.assertNotIn("service_role",SOURCE)
        self.assertNotRegex(SOURCE,r"(?i)\b(?:pg_cron|cron\.schedule|supabase|next\s+work\s+insert)\b")
        self.assertIn("'after_result_no_automatic_successor'",SOURCE)
        self.assertIn("'one_independent_worker_acceptance'",SOURCE)

    def test_source_governance_flags_missing_crosswalk_and_u2e_limits(self):
        # Presentation-only Markdown emphasis/case must not falsify a safety guard.
        plain=README.replace("**","").lower()
        for term in (
            "ledger.ledgers","atlas.ledgers",
            "zero registered carriers","zero active authorizations",
            "farm_id","carrier_state='unbound'",
            "status='draft'","U2F","NOT a production migration",
            "one atomic writer","No automatic successor",
        ):
            with self.subTest(term=term):
                self.assertIn(term.lower(),plain)
        self.assertNotIn("Already authorized",README)

    def test_private_native_identity_alignment_uses_only_existing_canonical_carriers(self):
        expected=(
            "CREATE FUNCTION atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(",
            "STABLE", "SECURITY INVOKER", "SET search_path TO ''",
            "atlas.delegated_agent_authorizations",
            "atlas.delegated_agent_carriers",
            "atlas.principals",
            "ledger.ledgers",
            "ledger.seats",
            "a.ledger_id=p_native_ledger_id",
            "a.delegating_seat_id IS NOT NULL",
            "s.person_entity_id=p.person_id",
            "s.ledger_id=l.id",
            "s.seat_state='active'",
            "l.ledger_state='active'",
            "p.person_id IS NOT NULL",
            "a.authorization_state='active'",
            "c.status='active'",
            "a.revoked_at IS NULL",
            "s.began_at<=pg_catalog.now()",
            "s.ended_at IS NULL OR s.ended_at>pg_catalog.now()",
            "a.begins_at<=pg_catalog.now()",
            "a.ends_at IS NULL OR a.ends_at>pg_catalog.now()",
            "REVOKE ALL ON FUNCTION",
            "FROM PUBLIC,anon,authenticated,service_role;",
        )
        for token in expected:
            with self.subTest(required=token):
                self.assertIn(token,NATIVE_SOURCE)
        self.assertEqual(len(re.findall(r"\bCREATE\s+FUNCTION\b",NATIVE_SOURCE,re.I)),1)

    def test_private_identity_does_not_become_original_work_authority(self):
        for flag in (
            "'workIssuerAuthorized',false",
            "'governingRootVerified',false",
            "'workCandidateAccepted',false",
            "'rulebookAndNeedVerified',false",
            "'originalWorkCreated',false",
            "'sourceOnly',true",
        ):
            with self.subTest(flag=flag):
                self.assertIn(flag,NATIVE_SOURCE)
        self.assertNotRegex(NATIVE_SOURCE,
            r"(?i)\b(?:INSERT\s+INTO|UPDATE\s+atlas\.|DELETE\s+FROM|DROP\s+|ALTER\s+|GRANT\s+|SECURITY\s+DEFINER|SET\s+ROLE|SET\s+SESSION\s+AUTHORIZATION)\b")
        for obsolete in (
            "atlas.ledgers","atlas.principal_ledger_authorities",
            "atlas.tasks","atlas.task_release_queue_items",
            "atlas.governed_prework_candidate_offers_v1",
            "atlas.governed_seasonal_scheduler_campaigns_v1",
            "auth.uid()",
        ):
            self.assertNotIn(obsolete,NATIVE_SOURCE)
        self.assertNotIn("work.original.establish_one",NATIVE_SOURCE)

    def test_readonly_legacy_to_native_adjudication_no_new_operating_tables(self):
        preflight=(FOLDER/"03_legacy_ledger_retirement_readonly_preflight_held.psql").read_text(encoding="utf8")
        pure=re.sub(r"(?m)^\s*--[^\n]*","",preflight)
        pure="\n".join(line for line in pure.splitlines() if not line.lstrip().startswith("\\"))
        self.assertNotRegex(pure, r"(?i)\b(?:INSERT|UPDATE|DELETE|TRUNCATE|CREATE|DROP|ALTER|GRANT|REVOKE)\s+(?:INTO|FROM|ON|TABLE|VIEW|FUNCTION|SCHEMA|POLICY|ROLE|INDEX)\b")
        for token in (
            ":'legacy_ledger_id'::uuid",
            "atlas.ledger_organization_participations",
            "atlas.principal_ledger_authorities",
            "ledger.onboarding_cases",
            "ledger.ledgers",
            "ledger.seats",
            "reality.entities",
            "legacy_adjudicated_migration",
            "migrationAdjudicated",
            "legacyLedgerId",
            "'canActivateLedger',false",
            "'workIssuerAuthorized',false",
            "'originalWorkCreated',false",
            "'legacyTableDropAuthorized',false",
            "'productionMutation',false",
        ):
            with self.subTest(token=token):
                self.assertIn(token,preflight)
        self.assertNotIn("Feast Guild",preflight)
        self.assertNotIn("WHERE l.name=",preflight)
        self.assertNotIn("security definer",preflight.lower())


    def test_governing_root_preflight_is_readonly_and_never_authorizes_work(self):
        inspect=(FOLDER/"04_governing_root_source_noloss_preflight_held.psql").read_text(encoding="utf8")
        pure=re.sub(r"(?m)^\\s*--[^\\n]*","",inspect)
        pure="\\n".join(line for line in pure.splitlines() if not line.lstrip().startswith("\\\\"))
        for token in (
            ":'governing_root_receipt_id'::uuid",
            ":'native_ledger_id'::uuid",
            "atlas.principal_ledger_authorities",
            "atlas.principals",
            "atlas.ledgers",
            "ledger.ledgers",
            "ledger.seats",
            "reality.responsibility_relations",
            "s.seat_basis->>'legacyLedgerAuthorityEvidenceId'=r.id::text",
            "'nativeGoverningRootVerified',false",
            "'sourceAdjudicationComplete',false",
            "'workIssuerAuthorized',false",
            "'originalWorkCreated',false",
            "'legacyRootRetirementAuthorized',false",
            "'productionMutation',false",
            "'sourceOnly',true",
        ):
            with self.subTest(required=token):
                self.assertIn(token,inspect)
        self.assertNotRegex(pure,r"(?i)\\b(?:INSERT|UPDATE|DELETE|TRUNCATE|CREATE|DROP|ALTER|GRANT|REVOKE)\\b")
        self.assertNotIn("security definer",inspect.lower())
        self.assertNotIn("auth.uid()",inspect)
        self.assertNotIn("atlas.tasks",inspect)
        self.assertNotIn("atlas.work_items",inspect)
        test=(FOLDER/"pg17/test_governing_root_source_noloss.py").read_text(encoding="utf8")
        fixture=(FOLDER/"pg17/governing_root_fixture.sql").read_text(encoding="utf8")
        self.assertIn("after rolled-back negatives",test)
        self.assertIn("unknown original receipt",test)
        self.assertIn("no original receipt provenance",test)
        self.assertIn("entity responsibility absent",test)
        self.assertIn("retired native Ledger",test)
        self.assertIn("EXECUTABLE_WORK_ISSUER=NO",test)
        self.assertIn("CREATE TABLE reality.responsibility_relations",fixture)
        self.assertNotIn("from production",fixture.lower())

if __name__=="__main__":
    unittest.main(verbosity=2)
