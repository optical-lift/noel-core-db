#!/usr/bin/env python3
"""No-network source-frozen regression for exact P3 held postcondition correction."""
from pathlib import Path
import hashlib
import importlib.util
import subprocess
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location(
    "held_real_dependency",HERE/"correct_uniops_p3_6a_postcondition_deppath_held.py")
fix=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fix)
SOURCE=Path(sys.argv[1]) if len(sys.argv)>1 else None

def mock_framed_sql(raw):
    """Build the frozen stage-envelope format without running a SQL engine."""
    u2="\n".join("-- BEGIN PINNED STAGE s%02d\nSELECT 1;\n-- END PINNED STAGE s%02d"%(n,n) for n in range(18))
    p3=[]
    for n in range(8):
        if n==7:
            name="20_mowing_6a_core_postconditions_held.sql"
            pin=fix.REVIEWED[name]
            body=raw[name]
        else:
            name="01_synthetic_%02d.sql"%n
            pin="f"*40
            body="SELECT 1;\n"
        p3.append("\n-- BEGIN PINNED P3 6A HELD STAGE "+name+" "+pin+
                 "\n"+body+"\n-- END PINNED P3 6A HELD STAGE "+name+"\n")
    return u2+"\n"+"\n".join(p3)

class StructuralDependencyCorrection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if SOURCE is None:
            raise AssertionError("Exact pinned P3 source checkout required")
        cls.raw=fix.check_sources(SOURCE)

    def test_exact_one_current_source_dependency_repaired(self):
        baseline=mock_framed_sql(self.raw)
        corrected=fix.correct_sql(baseline,self.raw)
        expected=baseline.replace(fix.OLD,fix.NEW,1)
        self.assertEqual(corrected,expected,
                         "No P3 source logic or another check may be modified")
        self.assertEqual(corrected.count(fix.NEW),1)
        self.assertEqual(corrected.count(fix.OLD),0)
        self.assertEqual(corrected.count("-- BEGIN PINNED STAGE "),18)
        self.assertEqual(corrected.count("-- BEGIN PINNED P3 6A HELD STAGE "),8)
        self.assertIn("position('uni_ops_accepted_first_original_source_receipt_held_v1'",corrected)
        self.assertIn("position('resolve_governed_canonical_farm_rule_authority_v1'",corrected)
        self.assertIn("Atomic first-original triggers not attached and enabled",corrected)
        self.assertIn("Private 6A authority became callable by API role",corrected)
        self.assertIn("accepted_first_original_source_receipt_held_v1",self.raw["04_canonical_original_acceptance_guard_held.sql"])
        self.assertIn("CREATE CONSTRAINT TRIGGER z_uni_ops_governed_original_finalization_v1",
                      self.raw["06_deferred_governed_original_finalization_held.sql"])

    def test_corrupt_stages_and_source_fail_closed(self):
        base=mock_framed_sql(self.raw)
        bad=(
            base.replace("20_mowing_6a_core_postconditions_held.sql","20_bad.sql",1),
            base.replace(fix.OLD,fix.NEW,1),
            base.replace(fix.OLD,fix.OLD+"\n"+fix.OLD,1),
            base.replace("-- BEGIN PINNED STAGE s00","-- REMOVED ORIGINAL STAGE",1),
            base.replace(self.raw["20_mowing_6a_core_postconditions_held.sql"],
                         self.raw["20_mowing_6a_core_postconditions_held.sql"].replace(
                             "has_function_privilege","permission_granted",1),1),
        )
        for drift in bad:
            with self.subTest(drift=drift[:80]):
                with self.assertRaises(AssertionError):
                    fix.correct_sql(drift,self.raw)
        with tempfile.TemporaryDirectory(prefix="p3-dependency-drift-") as d:
            root=Path(d)
            for name,blob in self.raw.items():
                (root/name).write_text(blob)
            self.assertEqual(fix.check_sources(root),self.raw)
            path=root/"20_mowing_6a_core_postconditions_held.sql"
            path.write_text(path.read_text()+"\n-- unauthorized change")
            with self.assertRaises(AssertionError):
                fix.check_sources(root)
            path.unlink()
            path.symlink_to(SOURCE/"20_mowing_6a_core_postconditions_held.sql")
            with self.assertRaises(AssertionError):
                fix.check_sources(root)

    def test_no_real_file_write_without_exact_signed_scratch(self):
        base=mock_framed_sql(self.raw)
        with tempfile.TemporaryDirectory(prefix="held-uniops-p3-real-dependency-") as d:
            root=Path(d)
            for name in ("bad.sql",fix.NAME):
                p=root/name
                p.write_text(base)
                original=p.read_bytes()
                r=subprocess.run(["python3",str(HERE/"correct_uniops_p3_6a_postcondition_deppath_held.py"),
                                  str(p),str(SOURCE)],capture_output=True,text=True,timeout=8)
                self.assertNotEqual(r.returncode,0)
                self.assertEqual(p.read_bytes(),original)
            self.assertNotEqual(hashlib.sha256(base.encode()).hexdigest(),fix.FRAMED_SQL_SHA)

if __name__=="__main__":
    unittest.main(argv=[sys.argv[0]],verbosity=2)
