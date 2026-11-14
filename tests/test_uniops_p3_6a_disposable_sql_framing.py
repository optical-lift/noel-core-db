#!/usr/bin/env python3
"""No-network first-mowing P3 statement-framing safety regression.

Loads the exact P3 held SQL at a separate pinned git checkout supplied by CI.
No production, PostgreSQL, release migration or actor context is accessed.
"""
from pathlib import Path
import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location(
    "p3_frame", HERE/"frame-uniops-p3-6a-disposable-sql.py")
frame=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(frame)
SOURCE_PATH=Path(sys.argv[1]) if len(sys.argv)>1 else None

def synthetic(bodies):
    """Shape of the immutable assembler; contents of unrelated stages omitted."""
    orig="\n".join(
      "-- BEGIN PINNED STAGE s%02d blob:%040x\nSELECT 1;\n-- END PINNED STAGE s%02d"%(i,i+1,i)
      for i in range(18))
    blocks=[]
    for i in range(8):
        if i==0:
            name="01_result_only_rhythm_evaluator_held.sql"
            pin=frame.REVIEWED[name]
            body=bodies[name]
        elif i==5:
            name="11_governed_rhythm_clock_signal_specific_hold_held.sql"
            pin=frame.REVIEWED[name]
            body=bodies[name]
        elif i==6:
            name="12_direct_rhythm_base_writers_governed_hold_held.sql"
            pin=frame.REVIEWED[name]
            body=bodies[name]
        else:
            name=f"other-reviewed-{i:02d}.sql"
            pin="f"*40
            body="SELECT 1;\n"
        blocks.append("\n-- BEGIN PINNED P3 6A HELD STAGE "+
                      name+" "+pin+"\n"+body+"\n-- END PINNED P3 6A HELD STAGE "+name+"\n")
    return orig+"\n"+ "\n".join(blocks)

class P3StrictFraming(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if SOURCE_PATH is None:
            raise AssertionError("Immutable P3 source checkout argument required")
        cls.bodies=frame.source_bytes(SOURCE_PATH)

    def test_exact_four_punctuation_insertions_only(self):
        raw=synthetic(self.bodies)
        revised=frame.frame(raw,self.bodies)
        self.assertEqual(len(revised),len(raw)+4)
        self.assertEqual(revised.count("-- BEGIN PINNED STAGE "),18)
        self.assertEqual(revised.count("-- BEGIN PINNED P3 6A HELD STAGE "),8)
        self.assertEqual(revised.count("-- END PINNED P3 6A HELD STAGE "),8)
        self.assertEqual(revised.count("end;$function$;\n\nCOMMIT;"),1)
        self.assertNotEqual(revised,raw)
        one=self.bodies["01_result_only_rhythm_evaluator_held.sql"]
        eleven=self.bodies["11_governed_rhythm_clock_signal_specific_hold_held.sql"]
        twelve=self.bodies["12_direct_rhythm_base_writers_governed_hold_held.sql"]
        self.assertEqual(raw.count(one),1)
        self.assertEqual(raw.count(eleven),1)
        self.assertEqual(raw.count(twelve),1)
        self.assertEqual(twelve.count("\n$function$\n"),2)
        expected=raw.replace(one,one.rstrip()+";\n\n",1).replace(
            eleven,eleven.replace("end;$function$\n\nCOMMIT;",
                         "end;$function$;\n\nCOMMIT;",1),1).replace(
            twelve,twelve.replace("\n$function$\n","\n$function$;\n"),1)
        self.assertEqual(revised,expected,
            "An assembler punctuation repair MUST NOT rewrite source logic")
        with self.assertRaises(AssertionError):
            frame.frame(revised,self.bodies)

    def test_fail_closed_if_composer_or_hold_source_drifts(self):
        raw=synthetic(self.bodies)
        for changed in (
           raw.replace("01_result_only_rhythm_evaluator_held.sql","01_forced.sql",1),
           raw.replace(self.bodies["01_result_only_rhythm_evaluator_held.sql"],
                       self.bodies["01_result_only_rhythm_evaluator_held.sql"].replace(
                           "SECURITY DEFINER","SECURITY INVOKER",1),1),
           raw.replace("11_governed_rhythm_clock_signal_specific_hold_held.sql",
                       "11_synthetic.sql",1),
           raw.replace("12_direct_rhythm_base_writers_governed_hold_held.sql",
                       "12_synthetic.sql",1),
           raw.replace(self.bodies["12_direct_rhythm_base_writers_governed_hold_held.sql"],
                       self.bodies["12_direct_rhythm_base_writers_governed_hold_held.sql"].replace(
                           "SECURITY DEFINER","SECURITY INVOKER",1),1),
           raw+"\n-- BEGIN PINNED P3 6A HELD STAGE not-authorized",
           raw.replace("-- BEGIN PINNED STAGE s00",
                       "-- BEGIN PINNED STAGE invalid",1).replace(
                           "-- BEGIN PINNED STAGE s01","-- NO STAGE s01",1),
        ):
            with self.subTest(source_change=changed[:100]):
                with self.assertRaises(AssertionError):
                    frame.frame(changed,self.bodies)
        with self.assertRaises(AssertionError):
            frame.source_bytes(SOURCE_PATH.parent)

    def test_refuse_non_disposable_path_or_wrong_hash_without_writes(self):
        raw=synthetic(self.bodies)
        with tempfile.TemporaryDirectory(prefix="held-p3-framing-") as d:
            root=Path(d)
            for filename in ("anything.sql",frame.NAME):
                path=root/filename
                path.write_text(raw,encoding="utf8")
                before=path.read_bytes()
                cmd=subprocess.run(["python3",str(HERE/"frame-uniops-p3-6a-disposable-sql.py"),
                    str(path),str(SOURCE_PATH)],
                    capture_output=True,text=True,check=False,timeout=10)
                self.assertNotEqual(cmd.returncode,0)
                self.assertEqual(path.read_bytes(),before)
            # Source already framed cannot be accepted for a second write.
            self.assertNotEqual(hashlib.sha256(raw.encode()).hexdigest(),
                                frame.SOURCE_SHA256)

if __name__=="__main__":
    unittest.main(argv=[sys.argv[0]],verbosity=2)
