#!/usr/bin/env python3
"""Fail-closed offline source review for unexecuted owner-protected U2F controller."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/".github/workflows/held-uniops-u2f-genuine-signed-one-shot.yml"
SRC=PATH.read_text(encoding="utf-8")

class U2FSourceReview(unittest.TestCase):
    def test_owner_2881_one_shot_protection(self):
        for required in (
            "github.event_name == 'issues'",
            "github.event.issue.number == 2881",
            "github.actor == github.repository_owner",
            "github.event.issue.author_association == 'OWNER'",
            "github.event.changes.title.from",
            "environment: production",
            "issues/2881/events?per_page=100&page=",
            "len(renames)!=1 or len(wanted)!=1",
            "parsed!=expected",
        ):
            with self.subTest(required=required):
                self.assertIn(required,SRC)
        for prohibited in ("workflow_dispatch:","schedule:","gh issue edit","gh workflow run"):
            self.assertNotIn(prohibited,SRC)
        self.assertEqual(SRC.count("  validate-protected:"),1)

    def test_exact_current_source_pins_before_any_credentials(self):
        self.assertIn("098fd12727c8722120a73b3676d97b2777d5a310",SRC,
                      "STOP: stale U2F source was pinned in protected controller")
        self.assertIn("4a13cad8fba7c1ca1feab64dad2ede44bfa4c518",SRC)
        self.assertIn("1ffedf113ee6c801b00fc521084d3e160c373198",SRC)
        self.assertNotIn("check_me_before_execution",SRC)
        self.assertNotIn("8fea511c6b422acb8686f57228af23fb053e6fa3",SRC)
        self.assertNotIn("ff74c66c293a1d94cc77f39af0db19adfe724080",SRC)
        self.assertIn("a965fcca2cb5e1c44f255eba24cca2a4d21c5",SRC)
        self.assertIn("ba2be33fa479e7d24523c10eaee3bbcf12918b3b",SRC)

    def test_github_token_and_read_only_schema_scope(self):
        self.assertIn("          GH_TOKEN: ${{ github.token }}",SRC,
                      "STOP: token must have an actual environment variable name")
        self.assertIn("os.environ['GH_TOKEN']",SRC)
        self.assertNotIn("          ${{ github.token }}: ${{ github.token }}",SRC)
        self.assertEqual(SRC.count("NOEL_CORE_DATABASE_URL: ${{ secrets.NOEL_CORE_DATABASE_URL }}"),1)
        self.assertIn("supabase db dump --db-url",SRC)
        self.assertIn("--role-only",SRC)
        self.assertNotIn("supabase db push",SRC)
        self.assertNotIn("apply_migration",SRC)

    def test_original_signed_reciprocal_probe_is_preserved_and_u2f_hook_matches(self):
        self.assertIn('--reciprocal-copy "$scratch/canonical/scripts/validate-atlas-ledger-reciprocal-signed-http.py"',SRC,
                      "STOP: U2F installer now requires BOTH test-only source copies")
        self.assertIn("signed-ledger-reciprocal-summary.txt",SRC)
        self.assertIn("U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS",SRC)
        self.assertIn("CANONICAL_NATIVE_GOVERNING_ROOT_GRANTS=ZERO",SRC)
        self.assertIn("DELEGATED_AGENT_WORK_COMMAND=NOT_RUN",SRC)

    def test_private_cleanup_no_protected_run_from_pr(self):
        self.assertIn("Delete all private source copies, roles, schema and signed logs",SRC)
        self.assertIn("rm -rf",SRC)
        self.assertNotIn("actions/upload-artifact",SRC)
        self.assertNotIn("permissions:\n  contents: write",SRC)
        self.assertIn("PROTECTED_EXECUTION=NOT_TRIGGERED",SRC)
        self.assertIn("github.event_name == 'pull_request'",SRC)

if __name__=="__main__":
    unittest.main(verbosity=2)
