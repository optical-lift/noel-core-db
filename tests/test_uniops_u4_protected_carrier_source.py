"""Source-only safety contract for the U2->U4 owner-gated disposable test carrier.

No secrets, network, production DB, API or signed session. Kept separate from
the trusted U2 workflow. This test never authorizes CI installation.
"""
import ast
import re
import textwrap
import subprocess
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
U4=ROOT/".github/workflows/held-uni-ops-u2-u4-signed-actual-clone.yml"
ORIGINAL=ROOT/".github/workflows/held-uni-ops-option-a-u2-accepted-first-signed-clone.yml"
SOURCE_SHA="3827b97cab0eee461fbc7327ae3a8eb46fe8bc6c"

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

    def test_owner_exact_eight_field_selector_accepts_u4_digit_without_widening_authority(self):
        # Regression for the owner-gated issue #2653 failure #42662248793.
        # The old name pattern [a-z_]+ could never parse u4_test_sha.
        protected=self.source.rsplit("  validate-protected:",1)[-1]
        lines=[line for line in protected.splitlines()
               if "match=re.fullmatch(r'" in line]
        self.assertEqual(len(lines),1)
        source_parts=lines[0].split("match=re.fullmatch(r'",1)
        self.assertEqual(len(source_parts),2)
        pattern=source_parts[1].split("'",1)[0]
        expected={
            "diagnostic_scope":"uni_ops_a_u2_signed_disposable_schema_v1",
            "source_choice":"a_full_current_completion_plus_history",
            "signed_contract":"u1b_u2_mowing_accepted_first_v1",
            "source_review":"u2c_context_guard_two_blobs_v1",
            "production_target":"zirqkouammpwxlqfbsvf",
            "harness_head":"5d28e2584736b8dd9cab928a34a6d5dc39ba38c1",
            "u4_test_sha":SOURCE_SHA,
            "test_goal":"signed_u2_result_done_v1"
        }
        issue_lines=[key+": "+value for key,value in expected.items()]
        parsed={}
        for line in issue_lines:
            match=re.fullmatch(pattern,line)
            self.assertIsNotNone(match, "exact frozen field omitted: "+line)
            if match[1] in expected:
                self.assertNotIn(match[1],parsed)
                parsed[match[1]]=match[2]
        self.assertEqual(parsed,expected)
        self.assertIsNone(re.fullmatch(pattern,"u4-test-sha: "+SOURCE_SHA))
        self.assertIsNone(re.fullmatch(pattern,"u4_test_sha: anything/else"))
        self.assertNotEqual(dict(parsed,u4_test_sha="0"*40),expected)
        self.assertEqual(len(expected),8)
        self.assertIn("if match[1] in pairs:raise SystemExit",protected)
        self.assertIn("if pairs!=expected:raise SystemExit",protected)

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
                     "db9921b63b8a0cc6256d802cbeeff8d54e594559",
                     "acb845c8285c4f75067eab1c871a0eb6d2d3ad3a"):
            self.assertIn(blob,body)
        self.assertEqual(body.rsplit("  validate-protected:",1)[-1].count("ref: "+SOURCE_SHA),1)
        self.assertEqual(body.count("Checkout immutable U4 test-only source AFTER snapshot"),1)
        self.assertEqual(body.count("Attach immutable U4 signed follow-on ONLY to disposable validator COPY"),1)
        self.assertEqual(body.count("Run canonical authentic-schema disposable clone, no release"),1)

    def test_no_live_writes_and_ephemeral_clone_only(self):
        body=self.source
        self.assertLess(body.index("READ-ONLY snapshot exact production schema and roles, no data"),
                        body.index("Checkout immutable U4 test-only source AFTER snapshot"))
        self.assertLess(body.index("Attach exact genuine signed U2 test to a disposable local validator COPY"),
                        body.index("Attach immutable U4 signed follow-on ONLY to disposable validator COPY"))
        self.assertEqual(body.rsplit("  validate-protected:",1)[-1].count("NOEL_CORE_DATABASE_URL:"),1)
        self.assertIn("python3 canonical/tests/install-uniops-u2-first-original-signed-hook.py canonical/scripts/validate-production-schema-clone.sh",body)
        self.assertIn("assert text.count(original)==1",body)
        self.assertIn("text=text.replace(original,original+' --u4-actual-followon',1)",body)
        self.assertEqual(body.count("test \"$(git -C u4-test rev-parse HEAD)\" = "+SOURCE_SHA),1)
        protected=body.rsplit("  validate-protected:",1)[-1]
        for forbidden in ("supabase db push","supabase migration up","apply_migration",
                          "gh pr merge","secrets.SUPABASE_SERVICE_ROLE_KEY"):
            self.assertNotIn(forbidden,protected)
        self.assertIn("rm -f -- \"$RUNNER_TEMP/uniops-snapshot-schema.sql\"",body)
        self.assertIn("rm -rf -- \"$RUNNER_TEMP/uniops-private-diagnostics\"",body)

    def test_public_signed_transport_exact_source_and_disposable_only(self):
        # The original U2 18-stage assembly has no public care-Actual RPC;
        # the R02 private writer is already frozen and must not be replaced.
        body=self.source
        self.assertIn('12_care_signed_http_rpc_candidate.sql',body)
        self.assertIn('3e09b66e54c15e100110c2b50f43dc9c7593e51a',body)
        self.assertIn('transport="$UNI_OPS_PIN_ROOT/r02/',body)
        self.assertIn("manifest['stage_count']==18",body)
        self.assertIn("before.count(b'-- BEGIN PINNED STAGE ')==18",body)
        self.assertIn("before.count(b'-- END PINNED STAGE ')==18",body)
        self.assertIn("manifest['scratch_file_sha256']",body)
        self.assertIn("blob=='3e09b66e54c15e100110c2b50f43dc9c7593e51a'",body)
        self.assertIn("not out.exists() and not out.is_symlink()",body)
        self.assertIn("out.parent==pathlib.Path(__import__('os').environ['RUNNER_TEMP'])",body)
        self.assertIn("IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL",body)
        self.assertIn("FROM PUBLIC,anon,authenticated,service_role;",body)
        self.assertIn("b'TO authenticated;'",body)
        self.assertIn("has_function_privilege('anon'",body)
        self.assertIn("has_function_privilege('authenticated'",body)
        self.assertIn("preexisting public care actual source requires",body.lower())
        self.assertIn("BEGIN U4 DISPOSABLE PUBLIC TRANSPORT SOURCE BLOB",body)
        self.assertIn("END U4 DISPOSABLE PUBLIC TRANSPORT",body)
        self.assertNotIn('cp "$reviewed" "$RUNNER_TEMP/20261107211000_atlas_uni_ops_a_history_DISPOSABLE_ONLY.sql"',body)
        opener='          python3 - "$reviewed" "$RUNNER_TEMP/uniops-u2c-review-manifest.json" "$transport" \\'
        self.assertEqual(body.count(opener),1)
        block=body.split(opener,1)[1].split("<<'PY'\n",1)[1].split("\n          PY\n",1)[0]
        ast.parse(textwrap.dedent(block),filename="u4-ephemeral-transport-source.py",mode="exec")

    def test_u4_bounded_failure_enum_reporter(self):
        protected=self.source.rsplit("  validate-protected:",1)[-1]
        self.assertIn("U4_SIGNED_PROBE_ENTERED=yes",protected)
        self.assertIn("U4_SIGNED_FAILURE_GATE=",protected)
        self.assertIn("UNI_OPS_U4_SIGNED_FAILURE_GATE=",protected)
        self.assertIn("UNI_OPS_U4_SIGNED_PROBE_ENTERED=",protected)
        self.assertIn("unclassified_probe_assertion",protected)
        self.assertIn("public_actual_signature_gate",protected)
        self.assertIn("one_terminal_transition_gate",protected)
        self.assertIn("zero_successor_gate",protected)
        self.assertIn("source_table_name_gate",protected)
        self.assertIn("not_reported",protected)
        self.assertIn("ambiguous",protected)
        self.assertNotIn("print('UNI_OPS_U4_SIGNED_FAILURE_GATE='+actor_text)",protected)
        self.assertIn("no schema dump, role dump or diagnostic artifact retained/uploaded",protected)

    def test_signed_u4_no_network_helper_verified_before_protected_schema(self):
        source=self.source
        self.assertIn("Checkout immutable U4 no-network source for CI contract",source)
        self.assertIn("Verify exact U4 helper blobs and no-network unit tests",source)
        self.assertIn("python3 -m unittest discover -s u4-source-contract/tests -p 'test_uniops_u2_qualified_actual_followon_held.py' -v",source)
        self.assertIn("acb845c8285c4f75067eab1c871a0eb6d2d3ad3a",source)
        self.assertLess(source.index("Verify exact U4 helper blobs and no-network unit tests"),
                        source.index("\n  validate-protected:\n"))
        self.assertIn("persist-credentials: false",source)
        self.assertIn("ref: "+SOURCE_SHA,source)

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
