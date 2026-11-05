#!/usr/bin/env python3
"""Self-contained, no-network tests for protected private-pilot issue approval."""
import copy
import importlib.util
import sys
import unittest
from pathlib import Path

CODE = Path(__file__).resolve().parents[1] / "scripts/verify-titus-pilot-approval.py"
spec = importlib.util.spec_from_file_location("titus_pilot", CODE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
EMAIL = "lexprjct@gmail.com"
ISSUE = "2489"
BODY = (
    f"**Authorized target:** `{EMAIL}`.\n"
    "**Grant kind:** `private_pilot`, not `purchase`. "
    "No payment may be inferred or invented.\n"
)
BASE = {
    "user": {"login": "optical-lift"},
    "author_association": "OWNER",
    "number": 2489,
    "state": "open",
    "title": f"Titus private-pilot issuance request: {EMAIL} (source-authorized only)",
    "html_url": "https://github.com/optical-lift/noel-core-db/issues/2489",
    "body": BODY,
}


class OwnerIssueTests(unittest.TestCase):
    def test_valid_owner_issue(self):
        module.verify(BASE, EMAIL, ISSUE)

    def test_other_target_email_denied(self):
        with self.assertRaises(ValueError):
            module.verify(BASE, "outsider@example.test", ISSUE)

    def test_issue_mismatch_denied(self):
        with self.assertRaises(ValueError):
            module.verify(BASE, EMAIL, "2490")

    def test_non_owner_denied(self):
        for change in ({"user": {"login": "different"}},
                       {"author_association": "CONTRIBUTOR"},
                       {"author_association": ""}):
            with self.subTest(change=change):
                issue = dict(BASE, **change)
                with self.assertRaises(ValueError):
                    module.verify(issue, EMAIL, ISSUE)

    def test_closed_or_forged_issue_denied(self):
        for field, value in (("state", "closed"),
                             ("number", 2500),
                             ("title", "Titus general-purpose superadmin"),
                             ("html_url", "https://evil.example/issues/2489")):
            with self.subTest(field=field):
                issue = dict(BASE, **{field: value})
                with self.assertRaises(ValueError):
                    module.verify(issue, EMAIL, ISSUE)

    def test_issue_body_must_name_actual_target_and_private_pilot(self):
        for value in ("", "**Authorized target:** `outsider@example.test`",
                      f"**Authorized target:** `{EMAIL}`",
                      "**Grant kind:** `purchase`"):
            with self.subTest(value=value):
                issue = dict(BASE, body=value)
                with self.assertRaises(ValueError):
                    module.verify(issue, EMAIL, ISSUE)

    def test_workflow_is_manual_and_protected(self):
        workflow = (CODE.parents[1] / ".github/workflows/titus-protected-private-pilot-issuance.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("\n  push:", workflow)
        self.assertNotIn("\n  issues:", workflow.split("\npermissions:", 1)[0])
        self.assertIn("environment: production", workflow)
        self.assertIn("refs/heads/main", workflow)
        self.assertIn("scripts/check-custody.sh", workflow)
        self.assertIn("scripts/check-titus-formation-custody.sh", workflow)
        self.assertIn("verify-titus-pilot-approval.py", workflow)

    def test_issuer_sql_single_complete_transaction_and_guard(self):
        source = (CODE.parents[1] / "scripts/titus-private-pilot-issue.sql").read_text()
        self.assertEqual(source.count("\nCOMMIT;"), 1)
        self.assertEqual(source.count("BEGIN;\nSET LOCAL"), 1)
        self.assertEqual(source.count("DO $issue$"), 1)
        self.assertEqual(source.count("$issue$;"), 1)
        self.assertEqual(source.count("LOCK TABLE titus.customer_workspace_entitlements_v1"), 1)
        self.assertTrue(source.strip().endswith("COMMIT;"))
        self.assertIn(
            "OR v_email !~* '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'",
            source,
        )
        self.assertIn("min(id::text)::uuid", source)
        self.assertEqual(source.count("AS ignored \\gset"), 3)
        self.assertNotIn("min(id) INTO", source)
        self.assertNotIn("INSERT INTO auth.users", source)

    def test_protected_issue_formation_custody_inputs_match_release(self):
        # The live formation custody check is not a purely local assertion.
        # Both read-only packet inputs must be present before protected DML.
        root = CODE.parents[1]
        issuer = (root / ".github/workflows/titus-protected-private-pilot-issuance.yml").read_text()
        release = (root / ".github/workflows/production-db-release.yml").read_text()
        for variable in ("NOEL_CORE_SUPABASE_URL", "NOEL_CORE_SUPABASE_PUBLISHABLE_KEY"):
            release_line = next(
                line.strip() for line in release.splitlines()
                if line.strip().startswith(variable + ":")
            )
            issuer_line = next(
                line.strip() for line in issuer.splitlines()
                if line.strip().startswith(variable + ":")
            )
            self.assertEqual(issuer_line, release_line)
        self.assertLess(
            issuer.index("bash scripts/check-titus-formation-custody.sh"),
            issuer.index("Apply one reviewed private-pilot source transaction"),
        )
        self.assertIn("environment: production", issuer)

    def test_issuer_is_a_narrow_existing_table_transaction(self):
        source = (CODE.parents[1] / "scripts/titus-private-pilot-issue.sql").read_text()
        self.assertIn("BEGIN;", source)
        self.assertIn("COMMIT;", source)
        self.assertIn("current_user <> 'postgres'", source)
        self.assertIn("grant_source_receipt", source)
        self.assertIn("v_prior.grant_kind<>'private_pilot'", source)
        self.assertIn("v_prior.grant_source_receipt<>v_receipt", source)
        self.assertIn("owner_auth_user_id", source)
        self.assertNotIn("CREATE USER", source)
        self.assertNotIn("INSERT INTO auth.users", source)
        self.assertNotIn("INSERT INTO titus.customer_workspaces_v1", source)
        self.assertNotIn("INSERT INTO titus.customer_course_drafts_v1", source)
        self.assertNotIn("UPDATE titus.customer_workspace_entitlements_v1", source)
        self.assertNotIn("service_role", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
