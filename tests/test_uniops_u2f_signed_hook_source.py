#!/usr/bin/env python3
"""No-network U2F guarded scratch hook checks. Never starts a database."""
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CANONICAL=ROOT/"scripts/validate-production-schema-clone.sh"
INSTALLER=ROOT/"candidates/atlas/uni_ops_u2f_universal_delegated_command_v1/pg17/install_u2f_signed_clone_hook_held.py"

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

class ExactU2FSignedCloneHookSource(unittest.TestCase):
    def test_one_temporary_copy_preserves_exact_canonical_source_and_existing_signed_probe(self):
        original=CANONICAL.read_bytes()
        self.assertEqual(git_blob(original),"a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5")
        with tempfile.TemporaryDirectory() as tmp:
            scratch=Path(tmp)/"u2f-scratch"
            scratch.mkdir()
            out=scratch/CANONICAL.name
            out.write_bytes(original)
            env={**os.environ,"RUNNER_TEMP":tmp}
            call=[sys.executable,str(INSTALLER),"--copy",str(out)]
            result=subprocess.run(call,capture_output=True,text=True,env=env,check=False)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn("U2F_TEMPORARY_CLONE_HOOK_SOURCE=PASS",result.stdout)
            self.assertEqual(CANONICAL.read_bytes(),original)
            new=out.read_text()
            self.assertEqual(new.count("U2F separately authorized signed-review-only clone check"),1)
            self.assertEqual(new.count('phase="signed reciprocal Ledger roots, private intake and Person identity"'),1)
            self.assertLess(new.index("U2F separately authorized signed-review-only clone check"),
                            new.index('phase="signed reciprocal Ledger roots, private intake and Person identity"'))
            for token in ('test "$database_url" = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"',
                          'PGOPTIONS="-c uniops.disposable_signed=u2f_owner_authorized_clone_only_v1"',
                          '06_signed_native_root_lifecycle_held.sql',
                          '08_signed_clone_only_rpc_bridge_held.sql',
                          'validate_u2f_genuine_signed_clone_held.py',
                          'grep -qx \'U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS\''):
                with self.subTest(token=token):
                    self.assertIn(token,new)
            replay=subprocess.run(call,capture_output=True,text=True,env=env,check=False)
            self.assertNotEqual(replay.returncode,0)
            self.assertIn("source blob drift",replay.stderr)
            self.assertEqual(CANONICAL.read_bytes(),original)

    def test_wrong_source_blob_and_non_scratch_location_denied(self):
        original=CANONICAL.read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            env={**os.environ,"RUNNER_TEMP":tmp}
            scratch=Path(tmp)/"u2f-scratch"
            scratch.mkdir()
            copy=scratch/CANONICAL.name
            copy.write_bytes(original+b"\n# unreviewed drift\n")
            cmd=[sys.executable,str(INSTALLER),"--copy",str(copy)]
            drift=subprocess.run(cmd,capture_output=True,text=True,env=env,check=False)
            self.assertNotEqual(drift.returncode,0)
            self.assertIn("source blob drift",drift.stderr)
            other=Path(tmp)/"other"
            other.mkdir()
            wrong=other/CANONICAL.name
            wrong.write_bytes(original)
            outside=subprocess.run([sys.executable,str(INSTALLER),"--copy",str(wrong)],
                                   capture_output=True,text=True,env=env,check=False)
            self.assertNotEqual(outside.returncode,0)
            self.assertIn("dedicated U2F scratch",outside.stderr)
            self.assertEqual(CANONICAL.read_bytes(),original)

    def test_canonical_never_touched_even_with_temporary_scope_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            env={**os.environ,"RUNNER_TEMP":tmp}
            result=subprocess.run(
                [sys.executable,str(INSTALLER),"--copy",str(CANONICAL)],
                capture_output=True,text=True,env=env,check=False
            )
            self.assertNotEqual(result.returncode,0)
            self.assertIn("may not modify canonical validator",result.stderr)
            self.assertEqual(git_blob(CANONICAL.read_bytes()),
                             "a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5")

if __name__=="__main__":
    unittest.main(verbosity=2)
