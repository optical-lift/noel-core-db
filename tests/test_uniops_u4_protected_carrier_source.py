"""Source-only safety contract for the U2->U4 owner-gated disposable test carrier.

No secrets, network, production DB, API or signed session. Kept separate from
the trusted U2 workflow. This test never authorizes CI installation.
"""
import re
import subprocess
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
U4=ROOT/".github/workflows/held-uni-ops-u2-u4-signed-actual-clone.yml"
ORIGINAL=ROOT/".github/workflows/held-uni-ops-option-a-u2-accepted-first-signed-clone.yml"
SOURCE_SHA="1f8bacb42c3e25d24fe123c1982857e1e79884fc"

class U4CarrierSourceSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=U4.read_text(encoding="utf-8")
        cls.original=ORIGINAL.read_text(encoding="utf-8")

    def test_yaml_parses_with_trusted_runner_ruby(self):
        subprocess.run(["ruby","-ryaml","-e",
                        "YAML.load_file(ARGV.fetch(0))",str(U4)],
                       capture_output=True,text=True,check=True)

    def test_protected_owner_issue_gate_is_new_and_exact(self):
        body=self.source
        protected=body.split("\n  validate-protected:\n",1)[1]
        self.assertIn("github.event_name == 'issues'",protected)
        self.assertIn("github.event.issue.author_association == 'OWNER'",protected)
        self.assertIn("github.actor == github.repository_owner",protected)
        self.assertIn("github.event.issue.title == 'UNI-OPS U2 to U4 protected signed Actual gate'",protected)
        self.assertNotIn("github.event.issue.number == 2626",body)
        self.assertIn("environment: production",protected)
        for exact in ("u4_test_sha","test_goal","signed_u2_result_done_v1",
                      "a_full_current_completion_plus_history",SOURCE_SHA):
            self.assertIn(exact,body)
        self.assertIn("if pairs!=expected:raise SystemExit",protected)
        self.assertIn("Duplicate owner source selector",protected)
        self.assertIn("github.event_name == 'pull_request'",body)

    def test_only_custodied_new_source_in_existing_18_stage_composition(self):
        body=self.source
        orig=self.original
        for exact in ("lifecycle ddfb0bf5374798301fe076a61d2b944dfb52ff63",
                      "u2c_review aa117383d693d33dbfe12bdc46fd6c7ae64a7911",
                      "c1fixture 9af4ab9b203877f048af09e23bac58bf86cd58fe",
                      "16 frozen source stages and exactly two independently pinned"):
            self.assertIn(exact,body)
            self.assertIn(exact,orig)
        for blob in ("09eeee925ebfa2cb64b1dea336688ba8076ef44d",
                     "3629cf05641619d0b3b10b572d83dd7f589b64b9",
                     "01bc92e0b70143bb161bb1e47855c55129ae9656"):
            self.assertIn(blob,body)
        self.assertEqual(body.count("ref: "+SOURCE_SHA),1)
        self.assertEqual(body.count("Checkout immutable U4 test-only source AFTER snapshot"),1)
        self.assertEqual(body.count("Attach immutable U4 signed follow-on ONLY to disposable validator COPY"),1)
        self.assertEqual(body.count("Run canonical authentic-schema disposable clone, no release"),1)

    def test_no_live_writes_and_ephemeral_clone_only(self):
        body=self.source
        self.assertLess(body.index("READ-ONLY snapshot exact production schema and roles, no data"),
                        body.index("Checkout immutable U4 test-only source AFTER snapshot"))
        self.assertLess(body.index("Attach exact genuine signed U2 test to a disposable local validator COPY"),
                        body.index("Attach immutable U4 signed follow-on ONLY to disposable validator COPY"))
        self.assertEqual(body.count("NOEL_CORE_DATABASE_URL:"),1)
        self.assertIn("python3 canonical/tests/install-uniops-u2-first-original-signed-hook.py canonical/scripts/validate-production-schema-clone.sh",body)
        self.assertIn("assert text.count(original)==1",body)
        self.assertIn("text=text.replace(original,original+' --u4-actual-followon',1)",body)
        self.assertEqual(body.count("test \"$(git -C u4-test rev-parse HEAD)\" = "+SOURCE_SHA),1)
        for forbidden in ("supabase db push","supabase migration up","apply_migration",
                          "gh pr merge","secrets.SUPABASE_SERVICE_ROLE_KEY"):
            self.assertNotIn(forbidden,body)
        self.assertIn("rm -f -- \"$RUNNER_TEMP/uniops-snapshot-schema.sql\"",body)
        self.assertIn("rm -rf -- \"$RUNNER_TEMP/uniops-private-diagnostics\"",body)

    def test_acceptance_requires_u4_not_generic_u2_pass(self):
        body=self.source
        self.assertIn("grep -q '^U4_SIGNED_ACTUAL_RESULT_DONE=PASS$'",body)
        self.assertIn("UNI_OPS_U4_SIGNED_ACTUAL_RESULT_DONE=",body)
        self.assertIn("'NOT_VERIFIED'",body)
        self.assertEqual(body.count("- name: Report only bounded failure class and source stage"),1)
        self.assertEqual(body.count("- name: Delete private test-only schema, role snapshot, source and logs"),1)
        self.assertNotIn("upload-artifact",body)
        self.assertIn("UNI_OPS_PRODUCTION_MUTATION=NONE",body)

if __name__=="__main__":
    unittest.main()
