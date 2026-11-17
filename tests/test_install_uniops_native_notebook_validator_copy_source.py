#!/usr/bin/env python3
"""No-network validator COPY contract for native signed U4/P3/owner readback."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent
SRC=ROOT.parent/"scripts"/"validate-production-schema-clone.sh"
U2=ROOT/"install-uniops-p3-6a-current-validator-copy.py"
HOOK=ROOT/"install_uniops_native_notebook_validator_copy_held.py"

def load():
    spec=importlib.util.spec_from_file_location("native_u2_validator",HOOK)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

class NativeValidatorCopySource(unittest.TestCase):
    def make_original(self,folder):
        file=folder/"validate-production-schema-clone.sh"
        file.write_bytes(SRC.read_bytes())
        test=subprocess.run(["python3",str(U2),str(file)],capture_output=True,text=True)
        self.assertEqual(test.returncode,0,test.stderr)
        text=file.read_text()
        pivot='--output "$artifacts_dir/uniops-u2-signed-summary.txt"'
        self.assertEqual(text.count(pivot),1)
        text=text.replace(pivot,pivot+" --u4-actual-followon",1)
        file.write_text(text)
        return file

    def test_all_native_hooks_in_singular_disposable_validator_copy(self):
        module=load()
        with tempfile.TemporaryDirectory(prefix="uniops-native-validator-") as t:
            copy=self.make_original(Path(t))
            original=copy.read_text()
            amended=module.install(original)
            self.assertLess(amended.index("uniops-native-governor-held-candidate.sql"),
                            amended.index(module.U2))
            self.assertLess(amended.index(module.U2),
                            amended.index("run-uniops-native-governor-readback-local.sh"))
            self.assertLess(amended.index("run-uniops-native-governor-readback-local.sh"),
                            amended.index(module.LINT))
            self.assertEqual(amended.count("--u4-actual-followon"),1)
            self.assertEqual(amended.count('phase="signed integrated U1B source and U2 accepted-first original"'),1)
            self.assertEqual(amended.count('ATLAS_NATIVE_GOVERNOR_DONE=PASS'),1)
            self.assertEqual(amended.count('ATLAS_NATIVE_OUTSIDER_DENIAL=PASS'),1)
            self.assertIn('ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED=true',amended)
            self.assertIn('ATLAS_NATIVE_SIGNED_READBACK_ENABLED',amended)
            self.assertIn('native_work="$(psql "$database_url" -XAt',amended)
            self.assertIn('r.responsible_allocation_id IS NOT NULL',amended)
            self.assertNotIn('ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK',amended)
            self.assertNotIn('supabase db push',amended)
            self.assertNotIn('apply_migration',amended)
            copy.write_text(amended)
            syntax=subprocess.run(["bash","-n",str(copy)],capture_output=True,text=True)
            self.assertEqual(syntax.returncode,0,syntax.stderr)
            with self.assertRaises(ValueError):
                module.install(amended)

    def test_cannot_hook_p3_validator_without_true_u2_u4(self):
        module=load()
        source=SRC.read_text()
        with self.assertRaises(ValueError):
            module.install(source)
        with tempfile.TemporaryDirectory(prefix="uniops-native-validator-") as t:
            copy=self.make_original(Path(t))
            no_u4=copy.read_text().replace(" --u4-actual-followon","")
            with self.assertRaises(ValueError):
                module.install(no_u4)
            with self.assertRaises(ValueError):
                module.install(copy.read_text().replace(
                  'phase="signed integrated U1B source and U2 accepted-first original"',
                  'phase="not_the_signed_original"'))

if __name__=="__main__":
    unittest.main()
