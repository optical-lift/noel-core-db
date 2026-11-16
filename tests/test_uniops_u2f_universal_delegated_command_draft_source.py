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

if __name__=="__main__":
    unittest.main(verbosity=2)
