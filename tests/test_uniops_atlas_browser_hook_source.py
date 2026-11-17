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
        for inner in ['runner_contract','governor_signin','outsider_signin','chromium_launch','governor_page','governor_done','outsider_page','outsider_denial','governor_navigation','governor_banner','governor_headings','governor_organization','governor_ledger','governor_work','governor_submit']:
            self.assertIn("ATLAS_CI_BROWSER_INNER_STAGE="+inner,shell)
            self.assertIn("stage="+inner,shell)
            self.assertIn(inner,workflow)
        self.assertIn("case \"$(grep '^ATLAS_CI_BROWSER_INNER_STAGE=' \"$log\" || true)\" in",shell)
        self.assertIn("stage=governor_readback_or_browser_start",shell)
        self.assertIn("hash-object tests/held-uniops-p3-browser-page-interaction.mjs",shell)
        self.assertIn("abf24f372b4bffeb5575f3ea0d52e4d27cf931a5",shell)
        self.assertIn("abf24f372b4bffeb5575f3ea0d52e4d27cf931a5",workflow)
        self.assertIn("d3aad1c9fef9034bf57dc6143041e52eaa9fb88f",workflow)
        self.assertIn("bf0c2227a4e628080515f98d4afbcd851f2d4f1d",workflow)
        self.assertIn("node --check atlas-browser-ci/tests/held-uniops-p3-browser-page-interaction.mjs",workflow)
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
