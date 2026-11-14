#!/usr/bin/env python3
"""No-network, no-actor tests for P3 + historical cancellation source integration."""
import argparse
import py_compile
from pathlib import Path
import sys
import tempfile
import unittest

import prepare_uniops_p3_history_signed_followon_held as composite
import uniops_p3_historical_preservation_check_held as conservation

ARGV=sys.argv[1:]
PARSER=argparse.ArgumentParser(add_help=False)
for item in ("driver","bridge","companion","p3-hook"):
    PARSER.add_argument("--"+item,required=True,type=Path)
PATHS=PARSER.parse_args(ARGV) if ARGV else None

def sample():
    return {
        "contract":"uni_ops_p3_signed_result_snapshot_v1",
        "phase":"replay","validExactOriginal":True,"validRhythmState":True,
        "campaignTableAbsent":True,"campaignOfferTableAbsent":True,
        "originalWorkState":"completed","rhythmState":"resting",
        "qualifyingSatisfactionId":"synthetic non-secret receipt",
        "nextEligibleAt":"fictional next window",
        "observedPhysicalCondition":"resting",
        "sourceWorkTotal":1,
        "workTotal":1,
        "workAllocationTotal":1,
        "legacyTaskTotal":2,"plannedOccurrenceTotal":2,
        "legacyReleasedTaskIds":["fictional legacy task"],
        "eligibleOrReleasedOccurrenceIds":["fictional occurrence"],
        "releasedOccurrenceIds":[],
        "governedOfferTotal":1,"workPlanTotal":1,
        "workResultTotal":1,"originalResultTotal":1,
        "originalAcceptanceTotal":1,"physicalCareResultTotal":1,
        "physicalCareObservationTotal":1,"satisfactionTotal":1,
        "principalObligationTotal":0
    }

class HistoryFirstMowingConservation(unittest.TestCase):
    def test_one_realistic_historical_work_retires_without_touching_mowing(self):
        before=sample()
        after=dict(before,workTotal=before["workTotal"]+1,
                   workAllocationTotal=before["workAllocationTotal"]+1)
        self.assertTrue(conservation.require_preserved(before,after))
        for field in conservation.NO_MUTATION:
            with self.subTest(field=field):
                corrupted=dict(after)
                corrupted[field]=(3 if not isinstance(after[field],list)
                                  else ["unexpected carrier"])
                if corrupted[field]==before[field]:
                    corrupted[field]="unexpected"
                with self.assertRaises(conservation.PreservationRefusal):
                    conservation.require_preserved(before,corrupted)

    def test_fail_closed_on_vacuous_mowing_or_illicit_successor(self):
        before=sample()
        after=dict(before,workTotal=2,workAllocationTotal=2)
        for modification in (
            {"originalWorkState":"cancelled"},
            {"rhythmState":"due"},
            {"sourceWorkTotal":2},
            {"qualifyingSatisfactionId":None},
            {"validExactOriginal":False},
            {"workTotal":3},
            {"workAllocationTotal":3},
            {"plannedOccurrenceTotal":3},
            {"legacyReleasedTaskIds":["fictional legacy task","newly released"]},
            {"eligibleOrReleasedOccurrenceIds":["new eligible occurrence"]},
            {"principalObligationTotal":1},
            {"phase":"after"},
            {"sourceWorkTotal":0},
            {"physicalCareObservationTotal":2},
            {"workResultTotal":2},
        ):
            with self.subTest(modification=tuple(modification)):
                corrupted=dict(after,**modification)
                with self.assertRaises(conservation.PreservationRefusal):
                    conservation.require_preserved(before,corrupted)
        with self.assertRaises(conservation.PreservationRefusal):
            conservation.require_preserved({},after)
        with self.assertRaises(conservation.PreservationRefusal):
            conservation.require_preserved(before,{"private":"unreviewed"})

    def test_composes_exact_reviewed_original_signed_driver(self):
        self.assertIsNotNone(PATHS,"CI must supply original immutable checkout paths")
        driver=PATHS.driver.read_bytes()
        bridge=PATHS.bridge.read_bytes()
        companion=PATHS.companion.read_bytes()
        hook=PATHS.p3_hook.read_bytes()
        guard=(Path(__file__).parent/
               "uniops_p3_historical_preservation_check_held.py").read_bytes()
        preparer=(Path(__file__).parent/
                  "prepare_uniops_historical_retirement_signed_followon_held.py").read_bytes()
        compat=(Path(__file__).parent/
                "uniops_p3_history_existing_membership_seed_held.py").read_bytes()
        output=composite.prepare(driver,bridge,companion,guard,hook,preparer,compat)
        code=output.decode("utf8")
        self.assertIn("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS",code)
        self.assertIn("_history_fixture_c1=_compat.adapter(base.c1,sql)",code)
        self.assertIn("sql=sql,rpc=rpc,c1=_history_fixture_c1)",code)
        self.assertNotIn("sql=sql,rpc=rpc,c1=base.c1)",code)
        self.assertEqual(code.count("history_receipt=hist.prove("),1)
        self.assertEqual(code.count("historical-retirement-followon"),1)
        self.assertEqual(code.count("_mowing_before_history=_p3.capture"),1)
        self.assertEqual(code.count("_mowing_after_history=_p3.capture"),1)
        self.assertLess(code.index("_mowing_before_history=_p3.capture"),
                        code.index("history_receipt=hist.prove("))
        self.assertLess(code.index("history_receipt=hist.prove("),
                        code.index("_mowing_after_history=_p3.capture"))
        self.assertIn('check(a.u4_actual_followon,',code)
        self.assertIn('signed["no-seat"][0]',code)
        self.assertIn('    owner_session=signed[',code)
        self.assertIn("U4_SIGNED_ACTUAL_RESULT_DONE=PASS",code)
        with tempfile.TemporaryDirectory() as root:
            p=Path(root)/composite.SAFE_OUTPUT
            p.write_bytes(output)
            py_compile.compile(str(p),doraise=True)

    def test_rejects_unreviewed_or_duplicate_source(self):
        self.assertIsNotNone(PATHS)
        driver=PATHS.driver.read_bytes()
        bridge=PATHS.bridge.read_bytes()
        companion=PATHS.companion.read_bytes()
        hook=PATHS.p3_hook.read_bytes()
        guard=(Path(__file__).parent/
               "uniops_p3_historical_preservation_check_held.py").read_bytes()
        preparer=(Path(__file__).parent/
                  "prepare_uniops_historical_retirement_signed_followon_held.py").read_bytes()
        compat=(Path(__file__).parent/
                "uniops_p3_history_existing_membership_seed_held.py").read_bytes()
        parts=[driver,bridge,companion,guard,hook,preparer,compat]
        for i in range(len(parts)):
            corrupted=parts[:]
            corrupted[i]+=b"\n# unreviewed amendment"
            with self.subTest(index=i):
                with self.assertRaises((composite.P3HistoricalRefusal,
                                       composite.original.HeldHookRefusal)):
                    composite.prepare(*corrupted)
        with self.assertRaises((composite.P3HistoricalRefusal,
                               composite.original.HeldHookRefusal)):
            composite.prepare(b"",bridge,companion,guard,hook,preparer,compat)

if __name__=="__main__":
    unittest.main(argv=[sys.argv[0]],verbosity=2)
