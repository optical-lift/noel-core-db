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
                         'read_owner(api, key, owner) == [W_L1]',
                         'read_owner(api, key, owner) == []',
                         'fingerprint(args.db_url)'):
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
        for suffix in ("c21", "c22", "c23", "c24"):
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

if __name__ == "__main__":
    unittest.main()
