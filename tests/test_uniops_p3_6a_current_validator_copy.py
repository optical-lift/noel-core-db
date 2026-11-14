#!/usr/bin/env python3
"""HELD P3 6A no-network regression for exact current-schema U2 test hook.

Refuses old/unknown host validators. Replays the previously reviewed source-
anchored transformations in a temp COPY and proves no other source text changed.
Does not run PostgreSQL or alter any committed validator.
"""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
INSTALLER=ROOT/"tests/install-uniops-p3-6a-current-validator-copy.py"
CURRENT=ROOT/"scripts/validate-production-schema-clone.sh"
EXPECTED="a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5"
HISTORIC="39f526cd8671f0aadbaab61c66dfc4971ef52131"

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

def run(source,root):
    target=root/"local-validator-copy.sh"
    target.write_bytes(source)
    proc=subprocess.run(["python3",str(INSTALLER),str(target)],
        capture_output=True,text=True,timeout=10,check=False)
    return proc,target

class P3CurrentValidatorCopy(unittest.TestCase):
    def test_current_source_and_old_guard_are_independently_pinned(self):
        self.assertEqual(git_blob(CURRENT.read_bytes()),EXPECTED)
        installer=INSTALLER.read_text()
        original=(ROOT/"tests/install-uniops-u2-first-original-signed-hook.py").read_text()
        self.assertIn('if git_blob!="'+EXPECTED+'"',installer)
        self.assertIn('if git_blob!="'+HISTORIC+'"',original)
        self.assertNotIn('if git_blob!="'+EXPECTED+'"',original)
        self.assertIn('signed_accepted_first_probe=true',installer)
        self.assertIn('signed_accepted_first_probe=true',original)
        # No different anchor or test mechanism: only reviewed pin, comment,
        # and PASS receipt differ from the original immutable patch recipe.
        for tok in ('anchors=(', 'if data.count(old)!=1:',
                    'data=data.replace(old,new,1)',
                    'data.replace(marker,hook+marker,1)',
                    'if data.count("signed_accepted_first_probe")!=3:'):
            self.assertIn(tok,installer)
            self.assertIn(tok,original)
        self.assertIn("fail(\"canonical validator source drift\")",installer)

    def test_exact_source_safe_copy_and_no_extra_changes(self):
        raw=CURRENT.read_bytes()
        with tempfile.TemporaryDirectory(prefix="p3-6a-validated-copy-") as t:
            root=Path(t)
            proc,target=run(raw,root)
            self.assertEqual(proc.returncode,0,"installer rejected exact current validator")
            transformed=target.read_text()
            original=raw.decode("utf8")
            expected=original
            edits=(
                ("signed_http_probe=false\n",
                 "signed_http_probe=false\nsigned_accepted_first_probe=true\n"),
                ('if [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||',
                 'if [ "$signed_accepted_first_probe" = true ] || [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||'),
                ('if [ "$signed_care_single_done_probe" = true ] ||',
                 'if [ "$signed_accepted_first_probe" = true ] || [ "$signed_care_single_done_probe" = true ] ||'),
            )
            for old,new in edits:
                self.assertEqual(expected.count(old),1)
                expected=expected.replace(old,new,1)
            marker='phase="candidate domain schema lint"\n'
            self.assertEqual(expected.count(marker),1)
            original_installer=(ROOT/"tests/install-uniops-u2-first-original-signed-hook.py").read_text()
            start=original_installer.index("hook='''")+len("hook='''")
            end=original_installer.index("'''",start)
            expected=expected.replace(marker,original_installer[start:end]+marker,1)
            self.assertEqual(transformed,expected,
                "P3 instrumenter changed more than exact safe local U2 start/hook")
            self.assertEqual(CURRENT.read_bytes(),raw,
                "tracked canonical validator must remain untouched")
            self.assertEqual(transformed.count("signed_accepted_first_probe"),3)
            self.assertIn("phase=\"signed integrated U1B source and U2 accepted-first original\"",transformed)
            self.assertIn('psql "$database_url" -X -v ON_ERROR_STOP=1',transformed)
            # New source keeps post-November ACCESS03/02/01 scoped controls.
            for label in ("signed_access01_event_choices_probe",
                          "signed_access02_my_work_probe",
                          "signed_access03_zone_retirement_probe",
                          "pre1_rest_proof"):
                self.assertIn(label,transformed)
            # No second installation / unauthorized retry on rewritten copy.
            proc2=subprocess.run(["python3",str(INSTALLER),str(target)],
                 capture_output=True,text=True,timeout=10)
            self.assertNotEqual(proc2.returncode,0)
            self.assertIn("canonical validator source drift",proc2.stderr+proc2.stdout)

    def test_fail_closed_on_unknown_source_and_symlink(self):
        raw=CURRENT.read_bytes()
        with tempfile.TemporaryDirectory(prefix="p3-6a-negative-copy-") as t:
            root=Path(t)
            for label,data in (("unknown",raw+b"\n# drift\n"),("empty",b""),
                               ("old-pin-masquerade",raw.replace(
                                  b"signed_http_probe=false",b"signed_http_probe=true"))):
                with self.subTest(label=label):
                    proc,target=run(data,root)
                    self.assertNotEqual(proc.returncode,0)
                    self.assertIn("canonical validator source drift",proc.stderr+proc.stdout)
                    self.assertEqual(target.read_bytes(),data)
            target=root/"local-validator-copy.sh"
            target.unlink()
            target.symlink_to(CURRENT)
            proc=subprocess.run(["python3",str(INSTALLER),str(target)],
                capture_output=True,text=True,timeout=10)
            self.assertNotEqual(proc.returncode,0)
            self.assertIn("regular ephemeral validator required",proc.stderr+proc.stdout)
            self.assertEqual(git_blob(CURRENT.read_bytes()),EXPECTED)

if __name__=="__main__":
    unittest.main(verbosity=2)
