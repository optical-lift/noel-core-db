#!/usr/bin/env python3
"""No-network source-cataloged P3 SQL diagnostic emission tests."""
from pathlib import Path
import importlib.util
import tempfile
import unittest
import sys

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "p3_reason",HERE/"uniops_p3_6a_postcondition_failure_category.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
SOURCE=Path(sys.argv[1]) if len(sys.argv)>1 else None
STAGE="p3-mowing-postconditions"
PREFIX="psql:/tmp/P3-TEST_ONLY.sql:1234: ERROR: "

class StructuralCheckDiagnostic(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if SOURCE is None:
            raise AssertionError("Pinned P3 20 source must be passed by CI")
        cls.source=SOURCE
        assert mod.source_catalog_valid(cls.source)

    def test_every_exact_source_exception_maps_to_one_finite_label(self):
        self.assertEqual(len(mod.PHRASES),7)
        for label,msg in mod.PHRASES:
            with self.subTest(label=label):
                self.assertEqual(mod.classify(PREFIX+msg,STAGE,self.source),label)
                self.assertNotIn(msg,label)
                self.assertNotIn("psql",label)
                self.assertLess(len(label),42)

    def test_no_user_sensitive_or_unknown_error_is_exposed(self):
        secret="private JWT token 12345, Person 7, address and source SQL"
        self.assertEqual(mod.classify(PREFIX+secret,STAGE,self.source),
                         "unclassified_or_ambiguous")
        self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1]+" and "+mod.PHRASES[1][1],
                             STAGE,self.source),"unclassified_or_ambiguous")
        self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1],
                             "history-retirement-postconditions",self.source),"not_applicable")
        self.assertEqual(mod.classify("",STAGE,self.source),"error_absent")
        self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1]+"\n"+secret,
                             STAGE,self.source),"unclassified_or_ambiguous")

    def test_source_drift_refuses_classification(self):
        with tempfile.TemporaryDirectory(prefix="p3-postcondition-classifier-") as d:
            p=Path(d)/"20_mowing_6a_core_postconditions_held.sql"
            p.write_bytes(self.source.read_bytes()+b"\n-- unapproved")
            self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1],STAGE,p),
                             "unverified_source")
            p.unlink()
            self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1],STAGE,p),
                             "unverified_source")
            p.symlink_to(self.source)
            self.assertEqual(mod.classify(PREFIX+mod.PHRASES[0][1],STAGE,p),
                             "unverified_source")

if __name__=="__main__":
    unittest.main(argv=[sys.argv[0]],verbosity=2)
