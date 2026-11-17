#!/usr/bin/env python3
"""Offline source contract for NEW issue-2833 diagnostic controller (NO execution).

The consumed issue #2831 workflow stays immutable and separate; only this
separately owner-approved event could ever enable a protected diagnostic retry.
"""
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
NEW=ROOT/".github/workflows/held-uniops-native-preu2-diagnostic-one-shot.yml"
OLD=ROOT/".github/workflows/held-uniops-native-notebook-one-shot-signed-clone.yml"
REVIEW="HELD UNI-OPS native pre-U2 diagnostic retry: source review, not executable"
AUTHORIZED="HELD UNI-OPS native pre-U2 diagnostic retry: one-shot signed test v1"

class DiagnosticOneShotSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text=NEW.read_text(encoding="utf8")
        cls.hold=OLD.read_text(encoding="utf8")

    def test_new_issue_owner_guard_no_consumed_authorization(self):
        s=self.text
        header=s.split("\njobs:\n",1)[0]
        protected=s.split("\n  validate-protected:\n",1)[1]
        self.assertIn("types: [edited]",header)
        self.assertNotIn("workflow_dispatch:",header)
        self.assertIn("github.event.issue.number == 2833",protected)
        self.assertNotIn("github.event.issue.number == 2831",protected)
        self.assertIn("github.actor == github.repository_owner",protected)
        self.assertIn("github.event.issue.author_association == 'OWNER'",protected)
        self.assertIn("github.event.changes.title.from == '"+REVIEW+"'",protected)
        self.assertIn("github.event.issue.title == '"+AUTHORIZED+"'",protected)
        self.assertIn("issues/2833/events?per_page=100&page=",protected)
        self.assertIn("len(matches)!=1",protected)
        self.assertIn("environment: production",protected)
        self.assertIn("group: held-uniops-native-preu2-diagnostic-2833",s)
        self.assertIn("'owner_run_approval':'held_atlas_pre_u2_diag_2833_one_shot_v1'",protected)
        self.assertIn("'diagnostic_goal':'finite_restored_clone_governor_pre_u2_v1'",protected)
        self.assertNotIn("issues/2831/events",protected)
        self.assertNotIn("held_atlas_native_2831_one_shot_v1",protected)

    def test_pinned_local_only_stage_reporter_is_separate_and_privacy_bounded(self):
        protected=self.text.split("\n  validate-protected:\n",1)[1]
        for mark in (
            "a7764ba80725bfb60ff501f648b68b29ff785824",
            "e2580c0e87bc00aa8ab4261655ee349bc8e5b334",
            "6416bdc4035922fac5a2612ae404441ebcb4db42",
            "tests/classify_uniops_native_pre_u2_stage_held.py",
            "tests/install_uniops_native_notebook_validator_copy_held.py",
            "UNI_OPS_NATIVE_PRE_U2_GATE=",
            "UNI_OPS_NATIVE_GRANT_STAGE=",
            "UNI_OPS_NATIVE_PRE_U2_GATE=not_recorded",
            "UNI_OPS_NATIVE_GRANT_STAGE=not_applicable",
            "PASS U4_NATIVE_SIGNED_WORKER_BROWSER_ORIGIN=PASS",
            "PASS ATLAS_NATIVE_GOVERNOR_DONE=PASS",
            "PASS ATLAS_NATIVE_OUTSIDER_DENIAL=PASS",
        ):
            self.assertIn(mark,protected,mark)
        self.assertLess(protected.index("Reject duplicate issue-2833 title authorization"),
                        protected.index("READ-ONLY snapshot exact production schema"))
        self.assertLess(protected.index("READ-ONLY snapshot exact production schema"),
                        protected.index("Read only pinned native Noel candidate"))
        self.assertLess(protected.index("Reconcile P3 immutable snapshots"),
                        protected.index("Run canonical authentic-schema disposable clone"))
        self.assertLess(protected.index("Run canonical authentic-schema disposable clone"),
                        protected.index("Emit only allowlisted native pre-U2 gate classification"))
        self.assertLess(protected.index("Emit only allowlisted native pre-U2 gate classification"),
                        protected.index("Delete private test-only schema"))
        self.assertIn("if: always()",protected)
        self.assertNotIn("supabase db push",protected)
        self.assertNotIn("apply_migration",protected)
        self.assertNotIn("cat \"$RUNNER_TEMP/uniops-private-clone.log\"",protected)
        self.assertNotIn("tail \"$RUNNER_TEMP/uniops-private-clone.log\"",protected)

    def test_workflow_yaml_valid_and_old_trigger_is_not_changed_by_new_source(self):
        check=subprocess.run(["ruby","-r","yaml","-e","YAML.load_file(ARGV.fetch(0))",str(NEW)],
                              capture_output=True,text=True,timeout=15)
        self.assertEqual(check.returncode,0,check.stderr)
        self.assertIn("github.event.issue.number == 2831",self.hold)
        self.assertNotIn("github.event.issue.number == 2833",self.hold)

if __name__=="__main__":
    unittest.main()
