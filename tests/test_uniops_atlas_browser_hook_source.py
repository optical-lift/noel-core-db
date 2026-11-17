#!/usr/bin/env python3
"""No-network refusal tests for the disposable Atlas browser hook installer."""
from pathlib import Path
import subprocess
import os
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).resolve().parent/"install-uniops-atlas-browser-readback-hook.py"
SHELL=Path(__file__).resolve().parent/"run-uniops-atlas-browser-readback-local.sh"
WORKFLOW=Path(__file__).resolve().parent.parent/".github/workflows/held-uni-ops-p3-6a-signed-clone.yml"
BASE='''signed_accepted_first_probe=true
phase="signed integrated U1B source and U2 accepted-first original"
python3 signer --u4-actual-followon
phase="candidate domain schema lint"
'''

class BrowserHookSourceTests(unittest.TestCase):
    def run_hook(self,body):
        with tempfile.TemporaryDirectory() as temp:
            target=Path(temp)/"validator-copy.sh"
            target.write_text(body)
            result=subprocess.run([sys.executable,str(SCRIPT),str(target)],
                                  capture_output=True,text=True,check=False)
            return result,target.read_text()
    def test_exact_late_browser_hook(self):
        p,out=self.run_hook(BASE)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(out.count("ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK"),1)
        self.assertEqual(out.count("ATLAS_CI_OUTSIDER_WORK_DENIAL"),1)
        self.assertLess(out.index("signed integrated"),out.index("Atlas fictional governor"))
        self.assertLess(out.index("Atlas fictional governor"),out.index("candidate domain schema lint"))
        self.assertIn('$repo_root/tests/run-uniops-atlas-browser-readback-local.sh',out)
        self.assertIn('$database_url',out)
        self.assertIn('ATLAS_BROWSER_FICTIONAL_ONLY',out)

    def test_double_install_rejected(self):
        first,with_hook=self.run_hook(BASE)
        self.assertEqual(first.returncode,0)
        second,unchanged=self.run_hook(with_hook)
        self.assertNotEqual(second.returncode,0)
        self.assertEqual(unchanged,with_hook)

    def test_missing_or_duplicate_signer_rejected(self):
        for text in (BASE.replace('--u4-actual-followon',''),
                     BASE.replace('signed_accepted_first_probe=true',''),
                     BASE+BASE):
            with self.subTest(text=text[:30]):
                result,out=self.run_hook(text)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(out,text)

    def test_missing_validation_marker_rejected(self):
        text=BASE.replace('phase="candidate domain schema lint"','phase="other"')
        result,out=self.run_hook(text)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(out,text)

    def test_bounded_failure_stage_without_leaking_input(self):
        secret="synthetic-secret-for-offline-test"
        for args in ([], [secret], ["postgresql://postgres:"+secret+"@elsewhere:5432/postgres"]):
            with self.subTest(args=args):
                result=subprocess.run(["bash",str(SHELL),*args],
                   capture_output=True,text=True,env={**os.environ,"ATLAS_BROWSER_FICTIONAL_ONLY":"true"})
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(result.stdout,
                    "BLOCKED ATLAS_CI_BROWSER_READBACK=not_verified\n"
                    "ATLAS_CI_BROWSER_FAILURE_STAGE=environment_contract\n")
                self.assertNotIn(secret,result.stdout+result.stderr)

    def test_diagnostic_stages_static_and_no_raw_output(self):
        shell=SHELL.read_text()
        workflow=WORKFLOW.read_text()
        permitted=['environment_contract','atlas_source_integrity','fictional_actor_fixture','accepted_work_selection','local_api_configuration','browser_source_contract','package_install','chromium_install','next_server_ready','governor_readback_or_browser_start','outsider_denial','browser_acceptance_marker']
        for inner in ['runner_contract','governor_signin','outsider_signin','chromium_launch','governor_page','governor_done','outsider_page','outsider_denial','governor_navigation','governor_banner','governor_headings','governor_organization','governor_ledger','governor_work','governor_submit','governor_hydration_readiness','governor_form_reset','governor_button_disabled','governor_submit_click','governor_no_terminal_ui','governor_source_error','governor_work_unavailable','governor_work_without_verified_done','governor_work_without_done_indicator','governor_snapshot_without_work_state']:
            self.assertIn("ATLAS_CI_BROWSER_INNER_STAGE="+inner,shell)
            self.assertIn("stage="+inner,shell)
            self.assertIn(inner,workflow)
        self.assertIn("case \"$(grep '^ATLAS_CI_BROWSER_INNER_STAGE=' \"$log\" || true)\" in",shell)
        self.assertIn("stage=governor_readback_or_browser_start",shell)
        self.assertIn("hash-object tests/held-uniops-p3-browser-page-interaction.mjs",shell)
        self.assertIn("3c5e07bf8028ca9d8327eda89344c6f63a85bd97",shell)
        self.assertIn("3c5e07bf8028ca9d8327eda89344c6f63a85bd97",workflow)
        self.assertIn("ATLAS_CI_BROWSER_FAILURE_STAGE=",workflow)
        self.assertIn("governor_hydration_readiness",workflow)
        self.assertIn("governor_form_reset",workflow)
        self.assertIn("governor_button_disabled",workflow)
        self.assertIn("governor_submit_click",workflow)
        self.assertIn("d8cdfabe6701fbba57f2fd2234b5314dd42c6a16",workflow)
        self.assertIn("a410ce04096e8d734678613c1659786ac744e825",workflow)
        self.assertIn("node --check atlas-browser-ci/tests/held-uniops-p3-browser-page-interaction.mjs",workflow)
        self.assertIn("hash-object tests/held-uniops-p3-browser-result-classification.mjs",shell)
        self.assertIn("node --check atlas-browser-ci/tests/held-uniops-p3-browser-result-classification.mjs",workflow)
        self.assertIn("8cdd941e2cb2d5f881a7da877d04b15ede070aa3",shell)
        self.assertIn("8cdd941e2cb2d5f881a7da877d04b15ede070aa3",workflow)
        for blob in ("f4827af35b884fe614e8abb8fa5c492ed4ae7016","684d17962ae6b9bf2d3b4fb620dddecd981950ff","bf803abf7bd79dc9c41f3aedeffc4f90449fe4b0"):
            self.assertIn(blob,shell)
            self.assertIn(blob,workflow)
        self.assertIn("node --check lib/unified-operating/held-auth-session-gate.mjs",shell)
        self.assertIn("node --check atlas-browser-ci/lib/unified-operating/held-auth-session-gate.mjs",workflow)
        self.assertIn("lib/unified-operating/held-auth-session-gate.d.mts",shell)
        self.assertIn("app/uni-ops-lab/OperatingContinuityClient.tsx",workflow)
        self.assertIn("governor_no_terminal_ui",workflow)
        self.assertIn("governor_source_error",workflow)
        self.assertIn("governor_work_unavailable",workflow)
        self.assertIn("governor_work_without_verified_done",workflow)
        self.assertIn("governor_work_without_done_indicator",workflow)
        self.assertIn("governor_snapshot_without_work_state",workflow)
        for stage in permitted:
            self.assertIn(stage,shell)
            self.assertIn(stage,workflow)
        self.assertIn("ATLAS_CI_BROWSER_FAILURE_STAGE=",workflow)
        self.assertIn("ATLAS_CI_BROWSER_FAILURE_STAGE=%s",shell)
        self.assertNotIn('cat "$log"',shell)
        self.assertNotIn('tail "$log"',shell)
        self.assertNotIn('cat "$next_log"',shell)
        self.assertIn("if ! node tests/held-uniops-p3-signed-browser-readback.mjs",shell)
        self.assertIn("stage=outsider_denial",shell)
        self.assertIn("elif len(browser_stages)==1",workflow)

    def test_invalid_arguments_rejected(self):
        result=subprocess.run([sys.executable,str(SCRIPT)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)

if __name__=="__main__":
    unittest.main()
