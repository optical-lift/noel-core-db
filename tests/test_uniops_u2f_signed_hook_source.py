#!/usr/bin/env python3
"""Offline two-point U2F signed hook test; never starts a database."""
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO=Path(__file__).resolve().parents[1]
CANONICAL=REPO/"scripts/validate-production-schema-clone.sh"
RECIPROCAL=REPO/"scripts/validate-atlas-ledger-reciprocal-signed-http.py"
INSTALLER=REPO/"candidates/atlas/uni_ops_u2f_universal_delegated_command_v1/pg17/install_u2f_signed_clone_hook_held.py"

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

class ExactU2FHook(unittest.TestCase):
    def create_copies(self,tmp):
        scratch=Path(tmp)/"u2f-scratch"
        scripts=Path(tmp)/"canonical"/"scripts"
        scratch.mkdir(parents=True)
        scripts.mkdir(parents=True)
        h=scratch/CANONICAL.name
        r=scripts/RECIPROCAL.name
        h.write_bytes(CANONICAL.read_bytes())
        r.write_bytes(RECIPROCAL.read_bytes())
        return h,r

    def call(self,tmp,h,r):
        env={**os.environ,"RUNNER_TEMP":tmp}
        return subprocess.run(
            [sys.executable,str(INSTALLER),"--copy",str(h),"--reciprocal-copy",str(r)],
            capture_output=True,text=True,env=env,check=False
        )

    def test_one_source_pinned_scratch_hook_keeps_both_canonical_sources_unchanged(self):
        harness_before=CANONICAL.read_bytes()
        reciprocal_before=RECIPROCAL.read_bytes()
        self.assertEqual(git_blob(harness_before),"a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5")
        self.assertEqual(git_blob(reciprocal_before),"ba2be33fa479e7d24523c10eaee3bbcf12918b3b")
        with tempfile.TemporaryDirectory() as tmp:
            h,r=self.create_copies(tmp)
            result=self.call(tmp,h,r)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn("U2F_TEMPORARY_CLONE_HOOK_SOURCE=PASS",result.stdout)
            self.assertIn("U2F_AUTH_BOOTSTRAP_DUPLICATED=NO",result.stdout)
            self.assertEqual(CANONICAL.read_bytes(),harness_before)
            self.assertEqual(RECIPROCAL.read_bytes(),reciprocal_before)
            new_h=h.read_text()
            new_r=r.read_text()
            self.assertEqual(new_h.count("U2F separately authorized signed-review-only clone setup"),1)
            self.assertEqual(new_h.count('phase="signed reciprocal Ledger roots, private intake and Person identity"'),1)
            self.assertLess(new_h.index("U2F separately authorized signed-review-only clone setup"),
                            new_h.index('phase="signed reciprocal Ledger roots, private intake and Person identity"'))
            for needle in ('test "$database_url" = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"',
                           'PGOPTIONS="-c uniops.disposable_signed=u2f_owner_authorized_clone_only_v1"',
                           '06_signed_native_root_lifecycle_held.sql',
                           '08_signed_clone_only_rpc_bridge_held.sql',
                           'grep -qx \'U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS\'',
                           'signed-ledger-reciprocal-summary.txt'):
                self.assertIn(needle,new_h)
            self.assertEqual(new_r.count("    base.setup_auth(a.db_url)"),1)
            self.assertEqual(new_r.count("    tokens={}"),1)
            self.assertIn('"--reuse-existing-signed-auth"',new_r)
            self.assertIn("u2f-signed-only-verdict.txt",new_r)
            self.assertIn("with _u2f_private.open",new_r)
            self.assertLess(new_r.index("    base.setup_auth(a.db_url)"),
                            new_r.index('    tokens={}'))
            self.assertLess(new_r.index("_u2f_run=subprocess.run"),
                            new_r.index('    tokens={}'))
            compile(new_r,str(r),"exec")
            replay=self.call(tmp,h,r)
            self.assertNotEqual(replay.returncode,0)
            self.assertIn("source blob drift",replay.stderr)
            self.assertEqual(CANONICAL.read_bytes(),harness_before)
            self.assertEqual(RECIPROCAL.read_bytes(),reciprocal_before)

    def test_tampered_validator_or_reciprocal_script_denied_before_any_copy_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            h,r=self.create_copies(tmp)
            original_r=r.read_bytes()
            h.write_bytes(h.read_bytes()+b"\n# unreviewed drift\n")
            fail=self.call(tmp,h,r)
            self.assertNotEqual(fail.returncode,0)
            self.assertIn("harness source blob drift",fail.stderr)
            self.assertEqual(r.read_bytes(),original_r)
            h.write_bytes(CANONICAL.read_bytes())
            original_h=h.read_bytes()
            r.write_bytes(r.read_bytes()+b"\n# unreviewed reciprocal drift\n")
            fail=self.call(tmp,h,r)
            self.assertNotEqual(fail.returncode,0)
            self.assertIn("reciprocal source blob drift",fail.stderr)
            self.assertEqual(h.read_bytes(),original_h)

    def test_non_scratch_and_canonical_paths_denied(self):
        with tempfile.TemporaryDirectory() as tmp:
            h,r=self.create_copies(tmp)
            outside=Path(tmp)/"wrong"
            outside.mkdir()
            invalid=outside/CANONICAL.name
            invalid.write_bytes(CANONICAL.read_bytes())
            fail=self.call(tmp,invalid,r)
            self.assertNotEqual(fail.returncode,0)
            self.assertIn("dedicated U2F scratch",fail.stderr)
            fail=self.call(tmp,CANONICAL,r)
            self.assertNotEqual(fail.returncode,0)
            self.assertIn("COPY must be inside the runner temporary area",fail.stderr)

if __name__=="__main__":
    unittest.main(verbosity=2)
