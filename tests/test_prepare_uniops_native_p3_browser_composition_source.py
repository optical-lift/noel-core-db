#!/usr/bin/env python3
"""Offline exact P3 frozen-snapshot + native browser-positive splice test."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent
COMPOSER=ROOT/"prepare_uniops_native_p3_browser_composition_held.py"
PATCHER=ROOT/"prepare_uniops_native_worker_actual_hook_held.py"

def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

composer=load(COMPOSER,"p3_browser_composer")
patcher=load(PATCHER,"pinned_browser_positive")

class ComposedNativeP3Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.u4=Path(os.environ.get("FROZEN_U4_SOURCE",""))
        cls.p3=Path(os.environ.get("PINNED_P3_SCRIPT",""))
        if not cls.u4.is_file() or not cls.p3.is_file():
            raise AssertionError("Exact frozen U4 and P3 checks must be checked out")
        cls.raw=cls.u4.read_bytes()
        cls.instrumented=composer.p3_expected(cls.raw,cls.p3)
        assert composer.git_blob(cls.raw)==composer.FROZEN_U4_BLOB
        assert composer.git_blob(cls.p3.read_bytes())==composer.PINNED_P3_BLOB

    def test_p3_snapshot_immutably_precedes_browser_actual(self):
        out=composer.splice(self.raw,self.p3,self.instrumented,patcher)
        s=out.decode()
        for marker in composer.P3_MARKERS:
            self.assertEqual(s.count(marker),1,marker)
        for marker in composer.SOURCE_NEGATIVES:
            self.assertEqual(s.count(marker),1,marker)
        self.assertEqual(s.count(patcher.REPLACEMENT),1)
        self.assertNotIn(patcher.NEEDLE,s)
        self.assertIn('payload["p_action_id"]=receipt["actionId"]',s)
        self.assertIn('private.unlink(missing_ok=True)',s)
        self.assertIn("same original Result",s if "same original Result" in s else "same original Result")
        compile(s,composer.OUTPUT_NAME,"exec")

    def test_exact_p3_parent_bytes_required(self):
        tampered=self.instrumented.replace(
            b'_p3_before=_p3.capture',b'_p3_before= _p3.capture',1)
        self.assertNotEqual(tampered,self.instrumented)
        with self.assertRaises(ValueError):
            composer.splice(self.raw,self.p3,tampered,patcher)
        with self.assertRaises(ValueError):
            composer.splice(self.raw+b"bad",self.p3,self.instrumented,patcher)

    def test_positive_first_runs_after_before_snapshot_and_before_after_snapshot(self):
        s=composer.splice(self.raw,self.p3,self.instrumented,patcher).decode()
        pre=s.index("_p3_before=_p3.capture")
        positive=s.index(patcher.REPLACEMENT)
        post=s.index("_p3_after=_p3.capture")
        replay=s.index('status, replay = call("worker")')
        p3_replay=s.index("_p3_replay=_p3.capture")
        self.assertLess(pre,positive)
        self.assertLess(positive,post)
        self.assertLess(post,replay)
        self.assertLess(replay,p3_replay)
        self.assertLess(p3_replay,s.index("_p3.compare("))

    def test_in_place_or_unpinned_source_is_denied(self):
        with tempfile.TemporaryDirectory(prefix="p3-browser-negative-") as td:
            wrong=Path(td)/"frozen.py"
            wrong.write_bytes(self.raw+b"changed")
            instrumented=Path(td)/"p3.py"
            instrumented.write_bytes(self.instrumented)
            with self.assertRaises(ValueError):
                composer.compose(wrong,self.p3,instrumented,PATCHER)
            original=Path(td)/"frozen_u4.py"
            original.write_bytes(self.raw)
            with self.assertRaises(ValueError):
                composer.compose(original,self.p3,instrumented,Path(td)/"missing.py")
            self.assertEqual(
                composer.compose(original,self.p3,instrumented,PATCHER),
                composer.splice(self.raw,self.p3,self.instrumented,patcher))

if __name__=="__main__":
    unittest.main()
