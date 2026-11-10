#!/usr/bin/env python3
"""Offline C2 trusted-controller/hook contract tests, no external connection."""
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "scripts/prepare-uniops-c2-protected-clone-hook-held.py"
VALIDATOR = ROOT / "scripts/validate-production-schema-clone.sh"
WORKFLOW = ROOT / ".github/workflows/held-uniops-c2-protected-source-controller.yml"


class HeldC2ControllerSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("held_c2_installer", HOOK)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)
        cls.validator = VALIDATOR.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_one_exact_clone_only_hook_and_bash_syntax(self):
        compiled = self.module.build_copy(self.validator)
        self.assertEqual(compiled.count('phase="held C2 exact native Ledger source proof signed matrix"'), 1)
        self.assertLess(compiled.index('python3 "$repo_root/scripts/validate-atlas-c1-signed-http.py"'),
                        compiled.index('phase="held C2 exact native Ledger'))
        self.assertIn("--expected-function-sql", compiled)
        self.assertIn("PGOPTIONS='-c uni_ops.disposable_clone=true'", compiled)
        self.assertIn("ffcf0b1c8ab49b4d456037aa5f1147cf", compiled)
        self.assertIn("held-c2-six-original-fixture.log", compiled)
        self.assertIn("held-c2-signed-private-receipt.txt", compiled)
        self.assertEqual(compiled.count('phase="candidate domain schema lint"'), 1)
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "validator-copy.sh"
            p.write_text(compiled)
            subprocess.run(["bash", "-n", str(p)], check=True)
        with self.assertRaises(ValueError):
            self.module.build_copy(compiled)

    def test_drift_and_missing_anchor_refused(self):
        for variant in (self.validator.replace("signed_http_probe=true", "signed_http_probe=false"),
                        self.validator + "\n# unauthorized change\n",
                        self.validator.replace('phase="candidate domain schema lint"',
                                               'phase="different lint"')):
            with self.assertRaises(ValueError):
                self.module.build_copy(variant)

    def test_workflow_has_separate_owner_only_protected_gate(self):
        y = self.workflow
        self.assertIn("pull_request:", y)
        self.assertIn("issues:", y)
        self.assertIn("types: [opened, edited, reopened]", y)
        self.assertIn("github.event.issue.author_association == 'OWNER'", y)
        self.assertIn("github.actor == github.repository_owner", y)
        self.assertIn("environment: production", y)
        self.assertIn("NOEL_CORE_DATABASE_URL:", y)
        self.assertIn("supabase db dump", y)
        self.assertIn("production-custom-roles.sql", y)
        self.assertIn("production-user-schema.sql", y)
        self.assertIn("validate-production-schema-clone.sh", y)
        self.assertIn("20261019201528", y)
        self.assertIn("prepare-uniops-c2-protected-clone-hook-held.py", y)
        self.assertIn("diagnostic_scope", y)
        self.assertIn("release_intent", y)
        self.assertIn("checkout@v4", y)
        self.assertIn("pulls/2668", y)
        self.assertIn("pulls/2669", y)
        self.assertNotIn("workflow_dispatch:", y)
        self.assertNotIn("supabase db push", y)
        self.assertNotIn("supabase migration up", y)
        self.assertNotIn("secrets.SUPABASE_SERVICE_ROLE_KEY", y)
        # PR-only job has no secrets, no environment, no DB, no privileged
        # action. Protected job can never run from PR event.
        before, protected = y.split("\n  protected-disposable-signed-c2:\n", 1)
        self.assertNotIn("secrets.", before)
        self.assertNotIn("environment:", before)
        self.assertIn("github.event_name == 'issues'", protected)
        self.assertIn("github.event.issue.title == 'UNI-OPS C2 exact Ledger Case Work signed disposable test request'", protected)
        self.assertIn("ref: 32d67670259e37fc1bd1485ede2a4db7fc4e5401", protected)
        self.assertIn("ref: 2545ed3cdafc811ce6ccb466b6aaa99ab9d5ec17", protected)
        self.assertIn("ref: 7e9b712c38d6a9ff2ef3922f735431bc5dfd5f04", protected)
        self.assertTrue(y.index("Validate exact owner diagnostic scope") <
                        y.index("Read-only protected schema and roles snapshot") <
                        y.index("Validate C2 only on disposable clone"))


if __name__ == "__main__":
    unittest.main()
