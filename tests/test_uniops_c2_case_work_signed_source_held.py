#!/usr/bin/env python3
"""No-network review checks for the HELD C2 disposable signed Case/Work test."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests/uniops_c2_case_work_disposable_fixture_held.sql"
DRIVER = ROOT / "scripts/validate-atlas-c2-case-work-signed-http.py"
C1 = ROOT / "scripts/validate-atlas-c1-signed-http.py"

class C2SignedTestSourceReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = FIXTURE.read_text(encoding="utf-8")
        cls.driver = DRIVER.read_text(encoding="utf-8")
        cls.c1 = C1.read_text(encoding="utf-8")

    def test_driver_python_compiles_without_running_signed_requests(self):
        compile(self.driver, str(DRIVER), "exec")
        self.assertIn('runpy.run_path(', self.driver)
        self.assertIn('validate-atlas-c1-signed-http.py', self.driver)
        for expected in ('local_status()', 'sign_in(api, key, name)',
                         'auth.sessions', 'RPC, params, None',
                         'revoked native root', 'ended native seat',
                         'ended GoTrue session',
                         'set(read_owner(api, key, owner)) == {W_L1, W_VERIFIED, W_STALE}',
                         'W_VERIFIED, "C2 SOURCE VERIFIED L1 VALID")) == []',
                         'fingerprint(args.db_url)',
                         'parser.add_argument("--expected-function-sql", required=True',
                         'pg_get_functiondef(',
                         'hashlib.sha256(actual_function.encode()).digest()',
                         'C2 disposable installed owner SQL differs from reviewed, pinned candidate'):
            self.assertIn(expected, self.driver)
        self.assertIn('parsed.hostname in ("127.0.0.1", "localhost")', self.c1)
        self.assertNotIn('service_role', self.driver)
        self.assertNotIn('supabase db push', self.driver)
        self.assertNotIn('apply_migration', self.driver)
        self.assertNotIn('http://', self.driver)
        self.assertNotIn('https://', self.driver)

    def test_disposable_fixture_has_hard_local_and_auth_identity_gate(self):
        for expected in (
            "current_database() IS DISTINCT FROM 'postgres'",
            "current_setting('server_version_num')::integer/10000 <> 17",
            "current_setting('uni_ops.disposable_clone',true)",
            "FROM auth.users WHERE id IN",
            "stable_key='signed_http_c1'",
            "position('rel.ledger_id=p_ledger_id'",
            "position('company_work_native_ledger_exact_source_v1'",
            "RAISE EXCEPTION 'Refuse C2:",
            "INSERT INTO atlas.ledgers",
            "INSERT INTO atlas.ledger_organization_participations",
            "'operating',false",
            "INSERT INTO atlas.work_items",
            "INSERT INTO atlas.work_requirement_links",
            "INSERT INTO atlas.company_work_native_ledger_relevance",
        ):
            self.assertIn(expected, self.fixture, expected)
        for forbidden in (r"(?im)^\\s*GRANT\\b", r"(?im)^\\s*REVOKE\\b",
                          r"(?im)^\\s*(CREATE|DROP|ALTER)\\s+(TABLE|FUNCTION|ROLE)\\b",
                          r"(?im)^\\s*INSERT\\s+INTO\\s+atlas[.]work_allocations\\b",
                          r"(?im)^\\s*INSERT\\s+INTO\\s+atlas[.]work_result",
                          r"(?im)^\\s*INSERT\\s+INTO\\s+atlas[.].*clock"):
            self.assertIsNone(re.search(forbidden, self.fixture), forbidden)

    def test_exact_current_foreign_withdrawn_and_inactive_history_controls(self):
        for suffix in ("c21", "c22", "c23", "c24", "c25", "c26"):
            self.assertIn("e5200000-0000-4000-8000-000000000" + suffix,
                          self.fixture)
            self.assertIn("e5200000-0000-4000-8000-000000000" + suffix,
                          self.driver)
        self.assertIn("C2 FOREIGN L2 ONLY NOT DISCLOSABLE", self.fixture)
        self.assertIn("C2 WITHDRAWN L1 NOT DISCLOSABLE", self.fixture)
        self.assertIn("'withdrawn',now()", self.fixture)
        self.assertIn("'advances',fixture.is_active", self.fixture)
        self.assertIn("'active',null,null,null", self.fixture)
        self.assertIn("'operating',false", self.fixture)
        self.assertIn("and tablename <> 'company_work_native_ledger_relevance'",
                      self.driver)
        self.assertIn("withdrawal_reason='C2 disposable signed withdrawal proof'",
                      self.driver)
        self.assertIn("C2 foreign, withdrawn or inactive historical original disclosed",
                      self.driver)

    def test_current_stale_and_withdrawn_source_verified_proof_is_distinct(self):
        # Only the existing source's allowlisted exact native booking source
        # is used. No fake proof helper, grant, result or Work state mutation.
        for value in (
            "INSERT INTO ledger.booking_requests(",
            "INSERT INTO atlas.company_work_native_ledger_relevance(",
            "source_object_type,source_object_id",
            "'ledger_booking_request'",
            "'source_verified','ledger','booking_requests'",
            "atlas.company_work_native_ledger_exact_source_v1(",
            "C2 SOURCE VERIFIED L1 VALID",
            "C2 SOURCE PROOF WILL GO STALE",
            "e5200000-0000-4000-8000-000000000b25",
            "e5200000-0000-4000-8000-000000000b26",
        ):
            self.assertIn(value, self.fixture, value)
        for value in (
            "UPDATE ledger.booking_requests",
            "SET ledger_id='{LEDGER_B}'::uuid",
            "EXCEPTION WHEN SQLSTATE '23514' THEN NULL;",
            "C2 immutable booking source lost original L1 proof",
            "C2 immutable booking was wrongly reassigned to L2",
            "with removed as (",
            "delete from ledger.booking_requests",
            "where id='{B_STALE}'::uuid and ledger_id='{LEDGER_A}'::uuid",
            "returning id",
            "select count(*) from removed",
            "C2 disposable synthetic booking source removal failed",
            "where work_item_id='{W_STALE}'::uuid",
            "and evidence_kind='source_verified' and attribution_state='active'",
            "C2 removed synthetic source still independently proves L1",
            "C2 removed source spuriously proves L2",
            "C2 signed raw L1 reader disclosed stale source_verified original",
            "extra_forbidden=(W_STALE, \"C2 SOURCE PROOF WILL GO STALE\")",
            "where id='{RELEVANCE_VERIFIED}'::uuid and attribution_state='active'",
            "C2 source_verified evidence withdrawal remained visible",
            "start == fingerprint(args.db_url)",
        ):
            self.assertIn(value, self.driver, value)
        self.assertIn("DO $c2_immutable$", self.driver)
        self.assertIn("raise exception 'C2 fixture unexpectedly permitted booking Ledger reassignment'".lower(), self.driver.lower())
        # psql -t -A may include UPDATE command tags after RETURNING rows.
        # Both local-only withdrawals must validate scalar affected-row counts.
        self.assertEqual(self.driver.count("with changed as ("), 2)
        self.assertEqual(self.driver.count("select count(*) from changed"), 2)
        self.assertNotIn("returning 1", self.driver.lower())
        self.assertNotIn("update atlas.work_items", self.driver.lower())
        self.assertNotIn("insert into atlas.work_items", self.driver.lower())
        self.assertNotIn("update atlas.work_requirement_links", self.driver.lower())
        self.assertNotIn("source_verified' and no source", self.fixture)


if __name__ == "__main__":
    unittest.main()
