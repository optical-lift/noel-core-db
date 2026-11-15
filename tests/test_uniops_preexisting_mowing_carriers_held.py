#!/usr/bin/env python3
"""No-network source-only negative tests. This is not signed acceptance."""
import ast
import copy
import json
from pathlib import Path
import unittest

import uniops_preexisting_mowing_carriers_held as prior
import prepare_uniops_preexisting_mowing_signed_held as composer

FAKE_LOCAL="postgresql://postgres:synthetic@127.0.0.1:54322/postgres"

def physical():
    return {
        "contract":prior.CONTRACT,
        "legacyTask":{
            "id":prior.TASK,"organization_id":prior.ORG,"farm_id":prior.FARM,
            "status":"open","work_lane":"rhythm",
            "planned_occurrence_id":prior.RELEASED,
            "released_at":"2026-11-01T00:00:00+00:00",
            "generated_from_id":prior.STATE,
            "metadata":{"cloneFixture":True}},
        "releasedOccurrence":{
            "id":prior.RELEASED,"farm_id":prior.FARM,"state":"released",
            "source_id":prior.STATE,"released_task_id":prior.TASK,
            "released_at":"2026-11-01T00:00:00+00:00",
            "metadata":{"cloneFixture":True}},
        "plannedOccurrence":{
            "id":prior.PLANNED,"farm_id":prior.FARM,"state":"planned",
            "source_id":prior.STATE,"released_task_id":None,
            "released_at":None,"metadata":{"cloneFixture":True}}}

def p3():
    return {
        "contract":"uni_ops_p3_signed_result_snapshot_v1",
        "phase":"replay",
        "legacyTaskTotal":1,"plannedOccurrenceTotal":2,
        "legacyReleasedTaskIds":[prior.TASK],
        "eligibleOrReleasedOccurrenceIds":[prior.RELEASED],
        "releasedOccurrenceIds":[prior.RELEASED]}

class FrozenPriorMowingFixture(unittest.TestCase):
    def test_seed_is_local_transaction_with_exact_real_physical_tables(self):
        source=prior.INSTALL_SQL
        self.assertTrue(source.startswith("BEGIN;"))
        self.assertTrue(source.endswith("COMMIT;"))
        self.assertEqual(source.count("INSERT INTO atlas.work_definitions"),1)
        self.assertEqual(source.count("INSERT INTO atlas.work_release_policies"),1)
        self.assertEqual(source.count("INSERT INTO atlas.planned_work_occurrences"),1)
        self.assertEqual(source.count("INSERT INTO atlas.tasks"),1)
        self.assertEqual(source.count("UPDATE atlas.planned_work_occurrences"),1)
        self.assertIn("governed_farm_rulebook_scope_versions_v1",source)
        self.assertIn("governed_prework_candidate_offers_v1",source)
        self.assertIn("current_database()<>'postgres'",source)
        self.assertNotIn("DELETE FROM",source)
        self.assertNotIn("TRUNCATE",source)
        self.assertNotIn("ALTER TABLE",source)
        self.assertNotIn("GRANT ",source)
        for value in (prior.ORG,prior.FARM,prior.STATE,prior.TASK,
                      prior.RELEASED,prior.PLANNED,prior.DEFINITION,prior.POLICY):
            self.assertIn(value,source)
        self.assertIn("source_kind,source_id,title,state,released_at",source)

    def test_disallowed_db_never_invokes_write_or_reader(self):
        calls=[]
        runner=lambda db,statement:calls.append((db,statement))
        for db in ("",None,"postgres://postgres:pass@db.example.org:5432/postgres",
                   "postgres://postgres:pass@127.0.0.1:5432/noel",
                   "postgres://service:pass@127.0.0.1:5432/postgres",
                   "postgres://postgres:pass@localhost:5432/postgres"):
            with self.subTest(db=db):
                with self.assertRaises(prior.PriorMowingRefusal):
                    prior.install(db,runner)
                with self.assertRaises(prior.PriorMowingRefusal):
                    prior.capture(db,runner)
        self.assertEqual(calls,[])

    def test_local_reader_queries_only_known_three_fictional_rows(self):
        calls=[]
        def sql(db,statement):
            calls.append((db,statement))
            return json.dumps(physical())
        self.assertEqual(prior.capture(FAKE_LOCAL,sql),physical())
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][1],prior.SNAPSHOT_SQL)
        self.assertTrue(calls[0][1].startswith("SELECT jsonb_build_object("))
        self.assertNotIn("FROM atlas.work_items",calls[0][1])
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.capture(FAKE_LOCAL,lambda *_:"{}")
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.capture(FAKE_LOCAL,lambda *_:"bad response")
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.capture(FAKE_LOCAL,lambda *_:"{}\n{}")

    def test_install_executes_only_preapproved_disposable_seed(self):
        calls=[]
        prior.install(FAKE_LOCAL,lambda db,statement:calls.append((db,statement)))
        self.assertEqual(calls,[(FAKE_LOCAL,prior.INSTALL_SQL)])

    def test_requires_nonempty_linked_state_and_identical_row_data(self):
        before=physical()
        after=copy.deepcopy(before)
        snap=p3()
        self.assertTrue(prior.require_preserved(before,after,snap,copy.deepcopy(snap)))
        mutations=(
            ("legacyTask","status","done"),
            ("legacyTask","released_at",None),
            ("legacyTask","planned_occurrence_id",prior.PLANNED),
            ("legacyTask","generated_from_id","other"),
            ("releasedOccurrence","state","completed"),
            ("releasedOccurrence","released_task_id",None),
            ("releasedOccurrence","source_id","other"),
            ("plannedOccurrence","state","eligible"),
            ("plannedOccurrence","released_task_id",prior.TASK),
            ("plannedOccurrence","released_at","unexpected"),
        )
        for part,key,value in mutations:
            with self.subTest(part=part,key=key):
                corrupt=copy.deepcopy(after)
                corrupt[part][key]=value
                with self.assertRaises(prior.PriorMowingRefusal):
                    prior.require_preserved(before,corrupt,snap,snap)
        for part in ("legacyTask","releasedOccurrence","plannedOccurrence"):
            corrupt=copy.deepcopy(after)
            corrupt[part]=None
            with self.assertRaises(prior.PriorMowingRefusal):
                prior.require_preserved(before,corrupt,snap,snap)
        # A field outside the minimal expected fields may not be silently
        # revised either: compare the entire original physical rows.
        corrupt=copy.deepcopy(after)
        corrupt["legacyTask"]["metadata"]["unexpected"]="changed"
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.require_preserved(before,corrupt,snap,snap)

    def test_nonempty_p3_census_is_mandatory_not_vacuously_equal(self):
        before=physical()
        p=p3()
        changes=(
            {"legacyTaskTotal":0},
            {"plannedOccurrenceTotal":0},
            {"legacyReleasedTaskIds":[]},
            {"eligibleOrReleasedOccurrenceIds":[]},
            {"releasedOccurrenceIds":[]},
            {"phase":"after"},
            {"contract":"wrong"},
            {"legacyTaskTotal":True},
        )
        for delta in changes:
            with self.subTest(delta=delta):
                with self.assertRaises(prior.PriorMowingRefusal):
                    prior.require_preserved(before,before,dict(p,**delta),p)
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.require_preserved(before,before,p,dict(p,plannedOccurrenceTotal=3))
        with self.assertRaises(prior.PriorMowingRefusal):
            prior.require_preserved(before,before,{},{})

    def test_composer_pins_fixture_and_keeps_old_sources_untouched(self):
        fixture=Path(__file__).with_name(
            "uniops_preexisting_mowing_carriers_held.py").read_bytes()
        self.assertEqual(composer.git_blob(fixture),composer.FIXTURE_BLOB)
        self.assertEqual(composer.PARENT_BLOB,
                         "e0240feabf26a3c19b7f86aa7f4de22d70635523")
        # A small standalone source specimen tests the add-on's placement.
        # Full parent composer still requires the exact frozen independent
        # driver, companion, bridge, guard, hook and adapters in CI.
        specimen='''def main():
    count_before=int(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid"))
    if True:
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=governor_started",flush=True)
        history_receipt=hist.prove()
        _mowing_after_history=_p3.capture(a.db_url,sql,_p3.ORG,_p3.STATE,new_work,"replay")
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=conservation_started",flush=True)
        print("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS",flush=True)
        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"
'''
        code=composer.inject(specimen.encode(),fixture).decode()
        ast.parse(code)
        self.assertIn("_legacy.install(a.db_url,sql)",code)
        self.assertIn("_legacy.require_preserved(",code)
        self.assertLess(code.index("_legacy.install("),code.index("count_before=int("))
        self.assertLess(code.index("_legacy_before=_legacy.capture"),
                        code.index("history_receipt=hist.prove"))
        self.assertLess(code.index("history_receipt=hist.prove"),
                        code.index("_legacy_after=_legacy.capture"))
        self.assertLess(code.index("_legacy.require_preserved("),
                        code.index("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"))
        with self.assertRaises(composer.LegacyCarrierCompositionRefusal):
            composer.inject(specimen.encode(),fixture+b"\n# drift")
        with self.assertRaises(composer.LegacyCarrierCompositionRefusal):
            composer.inject((specimen+specimen).encode(),fixture)

if __name__=="__main__":
    unittest.main(verbosity=2)
