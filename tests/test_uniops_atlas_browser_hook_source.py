#!/usr/bin/env python3
"""No-network refusal tests for the disposable Atlas browser hook installer."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).resolve().parent/"install-uniops-atlas-browser-readback-hook.py"
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

    def test_invalid_arguments_rejected(self):
        result=subprocess.run([sys.executable,str(SCRIPT)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)

if __name__=="__main__":
    unittest.main()
