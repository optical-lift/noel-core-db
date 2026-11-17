#!/usr/bin/env python3
"""NO-DB audit of the independent native Notebook one-shot protected controller."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
WORKFLOW=ROOT/".github/workflows/held-uniops-native-notebook-one-shot-signed-clone.yml"
OLD_WORKFLOW=ROOT/".github/workflows/held-uni-ops-p3-6a-signed-clone.yml"
ISSUE_TITLE="HELD UNI-OPS native Notebook one-shot signed acceptance v1"
PRIOR_TITLE="HELD UNI-OPS native Notebook true-signed acceptance: source/runner review, not executable"

class NativeOneShotSourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=WORKFLOW.read_text(encoding="utf-8")
        cls.original=OLD_WORKFLOW.read_text(encoding="utf-8")
    def test_independent_one_time_owner_and_environment_membrane(self):
        s=self.source
        self.assertIn("types: [edited]",s)
        self.assertNotIn("types: [edited, reopened]",s)
        self.assertIn("github.event.issue.number == 2831",s)
        self.assertIn("github.event.issue.state == 'open'",s)
        self.assertIn("github.actor == github.repository_owner",s)
        self.assertIn("github.event.issue.author_association == 'OWNER'",s)
        self.assertIn("github.event.changes.title.from == '"+PRIOR_TITLE+"'",s)
        self.assertIn("github.event.issue.title == '"+ISSUE_TITLE+"'",s)
        self.assertIn("'owner_run_approval':'held_atlas_native_2831_one_shot_v1'",s)
        self.assertIn("environment: production",s)
        self.assertIn("group: held-uniops-native-notebook-one-shot-2831",s)
        self.assertEqual(s.count("NOEL_CORE_DATABASE_URL: "),1)
        self.assertNotIn("if: github.event.issue.number == 2822",s)
        # Old workflow remains untouched. Current candidate is never a direct
        # on: workflow_dispatch action, nor a push, nor a PR protected run.
        self.assertNotIn("workflow_dispatch:",s)
        self.assertNotIn("  push:",s)
        self.assertIn("if: github.event_name == 'pull_request'",s)
        self.assertIn("if: >-\n      github.event_name == 'issues'",s)
    def test_pinned_current_held_sources_and_exact_sequence(self):
        s=self.source
        for k in (
          "6bc616db84854ea2d906dd51a017d8616ef0762d",
          "e22ee0172bd808105d90a3cebeff33bcc2057053",
          "075919564dc340ad86be8e969a2ad2d02ec19a15",
          "7f4fc633c0d36daa005f0f7e2a85f0743f23ef1e",
          "12568439f527ee083981a8903249f0b79b89bc6b",
          "09d3be2ec9c7ae390387d74f7c9cde5fe591a035",
          "5964dd9a8729aa70609d52ab02cecc7e299fd89d",
          "cf61f7671ce47829a2989b80edc6d886c377ed71",
          "c93ab9d53f8d75917b8ab36aae87c8e2c47420e7",
          "uniops-native-governor-held-candidate.sql",
          "uniops_u2_qualified_actual_browser_p3_local_only.py",
          "install_uniops_native_notebook_validator_copy_held.py",
          "ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY=true",
          "ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED=true",
          "ATLAS_NATIVE_SIGNED_READBACK_ENABLED=true",
          "PASS U4_NATIVE_SIGNED_WORKER_BROWSER_ORIGIN=PASS",
          "PASS ATLAS_NATIVE_GOVERNOR_DONE=PASS",
          "PASS ATLAS_NATIVE_OUTSIDER_DENIAL=PASS",
        ):
            self.assertIn(k,s,k)
        self.assertLess(s.index("READ-ONLY snapshot exact production schema and roles, no data"),
                        s.index("Read only pinned native Noel candidate"))
        self.assertLess(s.index("Checkout immutable P4") if "Checkout immutable P4" in s
                        else s.index("Checkout immutable P3 6A held source AFTER snapshot"),
                        s.index("Reconcile P3 immutable snapshots"))
        protected=s.split("\n  validate-protected:\n",1)[1]
        self.assertLess(protected.index("Reconcile P3 immutable snapshots"),
                        protected.index("Run canonical authentic-schema disposable clone, no release"))
        self.assertIn("--role-only --file",s)
        self.assertIn('--file "$RUNNER_TEMP/uniops-snapshot-schema.sql"',s)
        self.assertNotIn("supabase db push",s.split("\n  validate-protected:\n",1)[1])
        self.assertNotIn("apply_migration",s.split("\n  validate-protected:\n",1)[1])
    def test_yaml_is_syntactically_valid_and_no_unreviewed_legacy_runner(self):
        check=subprocess.run(["ruby","-r","yaml","-e","YAML.load_file(ARGV.fetch(0))",
            str(WORKFLOW)],capture_output=True,text=True,timeout=15)
        self.assertEqual(check.returncode,0,check.stderr)
        self.assertNotIn("held-uniops-p3-signed-browser-readback.mjs",self.source.split(
            "\n  validate-protected:\n",1)[1])
        self.assertEqual(self.source.count("uniops-native-governor-private.log"),3)

if __name__=="__main__":
    unittest.main()
