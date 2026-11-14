#!/usr/bin/env python3
"""No-network fail-closed tests of immutable #2368 historical seed compatibility."""
import argparse
import io
from contextlib import redirect_stdout
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "historic_seed",HERE/"uniops_p3_history_existing_membership_seed_held.py")
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
C_BLOB="79151f723e60b33410c760acef715155a53771f3"
parser=argparse.ArgumentParser(add_help=False)
parser.add_argument("--companion",type=Path,required=True)
args=parser.parse_args(sys.argv[1:]) if len(sys.argv)>1 else None
PG="postgresql://postgres:fictional@127.0.0.1:54322/postgres"

class StopAfterSeed(Exception):
    pass

class FixtureCompatibility(unittest.TestCase):
    def test_frozen_original_companion_produces_exact_seed(self):
        self.assertIsNotNone(args)
        raw=args.companion.read_bytes()
        sha=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
        self.assertEqual(sha,C_BLOB,"Pinned historical companion drift")
        holder={}
        def check(condition,label):
            self.assertTrue(condition,label)
        def sql(_db,statement):
            if "to_regprocedure" in statement:return "t"
            if "current_database()" in statement:return "postgres"
            if "auth.users" in statement:return "1"
            self.fail("Unexpected SQL before source-defined seed")
        def seize(_db,q):
            holder["seed"]=q
            raise StopAfterSeed
        obj=SimpleNamespace(check=check,sql=sql,literal=lambda x:"'"+x+"'",
                            allow=None,deny=None,c1=SimpleNamespace(sql=seize))
        src=importlib.util.spec_from_file_location("reviewed_immutable_companion",
                                                   args.companion)
        mod=importlib.util.module_from_spec(src)
        src.loader.exec_module(mod)
        with self.assertRaises(StopAfterSeed):
            mod.proof(PG,None,None,{"owner":"owner","worker":"worker",
                 "outsider":"outsider","no-seat":"no-seat"},obj)
        self.assertEqual(holder["seed"].strip(),m.ORIGINAL_SEED.strip())
        self.assertEqual(m.adapt_known_seed(holder["seed"]).count(
            "INSERT INTO atlas."),3)

    def test_exact_two_source_adaptations_with_all_other_rows_unchanged(self):
        raw=m.ORIGINAL_SEED
        revised=m.adapt_known_seed(raw)
        self.assertEqual(revised,raw.replace(m.MEMBER_INSERT,
            "-- existing canonical Person membership reused",1).replace(
            m.ORIGINAL_ALLOCATION,m.BOUND_ALLOCATION,1))
        self.assertIn(m.WORK_INSERT,revised)
        self.assertIn(m.RELEVANCE_INSERT,revised)
        self.assertNotIn(m.LEGACY+"'",revised)
        self.assertIn("m.person_id='"+m.PERSON+"'",revised)

    def test_canonical_membership_preflight_and_exact_single_seed(self):
        writer_calls=[];selects=[]
        def reader(db,q):
            selects.append(q)
            return "1"
        original=SimpleNamespace(sql=lambda db,q:writer_calls.append(q))
        adapter=m.adapter(original,reader)
        self.assertIsNone(adapter.sql(PG,m.ORIGINAL_SEED))
        self.assertEqual(writer_calls,[m.adapt_known_seed(m.ORIGINAL_SEED)])
        self.assertEqual(selects,[m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL,m.ALLOCATION_SQL])
        with self.assertRaises(m.HistoricFixtureRefusal):
            adapter.sql(PG,m.ORIGINAL_SEED)
        # The source's historical membership INSERT was NOT performed.
        self.assertNotIn("INSERT INTO atlas.organization_memberships",writer_calls[0])

    def test_missing_existing_member_refuses_without_write(self):
        calls=[]
        a=m.adapter(SimpleNamespace(sql=lambda db,q:calls.append(q)),
                    lambda db,q:"0")
        with self.assertRaises(m.HistoricFixtureRefusal):
            a.sql(PG,m.ORIGINAL_SEED)
        self.assertEqual(calls,[])

    def test_wrong_target_drift_and_unreviewed_sql_fail_closed(self):
        for q in (
            m.ORIGINAL_SEED.replace("legacy_task_slice","forged_physical_done"),
            m.ORIGINAL_SEED.replace(m.USER,"e5200000-0000-4000-8000-999999999999"),
            m.ORIGINAL_SEED+"\nDELETE FROM atlas.work_items;",
            m.ORIGINAL_SEED.replace(m.MEMBER_INSERT,""),
            m.ORIGINAL_SEED.replace(m.ORIGINAL_ALLOCATION,m.BOUND_ALLOCATION),
            m.ORIGINAL_SEED+m.ORIGINAL_SEED,
            "",None):
            with self.subTest(case=str(q)[:30]):
                with self.assertRaises(m.HistoricFixtureRefusal):
                    m.adapt_known_seed(q)
        calls=[]
        for db in ("postgresql://postgres:any@untrusted.test:5432/postgres",
                   "postgresql://postgres:fictional@127.0.0.1:54322/production"):
            with self.assertRaises(m.HistoricFixtureRefusal):
                m.adapter(SimpleNamespace(sql=lambda db,q:calls.append(q)),
                    lambda db,q:"1").sql(db,m.ORIGINAL_SEED)
        self.assertEqual(calls,[])

    def test_local_subprocess_failure_is_not_silently_swallowed(self):
        def fails(db,q):
            raise subprocess.CalledProcessError(1,["psql","PRIVATE"])
        a=m.adapter(SimpleNamespace(sql=fails),lambda db,q:"1")
        with self.assertRaises(subprocess.CalledProcessError):
            a.sql(PG,m.ORIGINAL_SEED)


    def test_bounded_membership_absence_vs_nonunique_and_sql_failure(self):
        for count,expected in (("0","membership_absent"),
                               ("2","membership_not_exactly_one")):
            output=io.StringIO()
            fixture=m.adapter(SimpleNamespace(sql=lambda db,q:None),
                              lambda db,q:count)
            with self.subTest(count=count),redirect_stdout(output):
                with self.assertRaises(m.HistoricFixtureRefusal):
                    fixture.sql(PG,m.ORIGINAL_SEED)
            self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE="+expected,
                          output.getvalue())
            self.assertNotIn(m.ORG,output.getvalue())
            self.assertNotIn("postgresql://",output.getvalue())
        output=io.StringIO()
        def failed_reader(db,query):
            raise subprocess.CalledProcessError(1,["psql","PRIVATE"])
        with redirect_stdout(output):
            with self.assertRaises(subprocess.CalledProcessError):
                m.adapter(SimpleNamespace(sql=lambda db,q:None),
                          failed_reader).sql(PG,m.ORIGINAL_SEED)
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=membership_query_failed",
                      output.getvalue())

    def test_bounded_seed_failure_and_verified_allocation(self):
        output=io.StringIO()
        def fails(db,query):
            raise subprocess.CalledProcessError(1,["psql","PRIVATE"])
        with redirect_stdout(output):
            with self.assertRaises(subprocess.CalledProcessError):
                m.adapter(SimpleNamespace(sql=fails),
                          lambda db,q:"1").sql(PG,m.ORIGINAL_SEED)
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=seed_apply_failed",
                      output.getvalue())
        output=io.StringIO()
        with redirect_stdout(output):
            m.adapter(SimpleNamespace(sql=lambda db,q:None),
                      lambda db,q:"1").sql(PG,m.ORIGINAL_SEED)
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=fixture_verified",
                      output.getvalue())
        self.assertNotIn("PRIVATE",output.getvalue())

    def test_postseed_allocation_failure_is_not_mislabeled_as_seed_failure(self):
        output=io.StringIO()
        def reader(db,query):
            return "1" if query in (m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL) else "0"
        with redirect_stdout(output):
            with self.assertRaises(m.HistoricFixtureRefusal):
                m.adapter(SimpleNamespace(sql=lambda db,q:None),
                          reader).sql(PG,m.ORIGINAL_SEED)
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=allocation_not_exactly_one",
                      output.getvalue())
        self.assertNotIn("UNI_OPS_HISTORY_FIXTURE_STAGE=seed_apply_failed",
                         output.getvalue())


    def test_absent_person_membership_uses_exact_frozen_original_seed(self):
        state={"member":False,"statements":[],"queries":[]}
        def reader(db,q):
            state["queries"].append(q)
            if q==m.IDENTITY_SQL:return "aligned"
            if q in (m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL):
                return "1" if state["member"] else "0"
            if q==m.ALLOCATION_SQL:return "1" if state["member"] else "0"
            self.fail("Unreviewed read in absent-member fixture")
        def writer(db,q):
            self.assertEqual(q,m.ORIGINAL_SEED)
            state["statements"].append(q)
            state["member"]=True
        sink=io.StringIO()
        with redirect_stdout(sink):
            self.assertIsNone(m.adapter(SimpleNamespace(sql=writer),reader).
                              sql(PG,m.ORIGINAL_SEED))
        self.assertEqual(state["statements"],[m.ORIGINAL_SEED])
        self.assertEqual(state["queries"],[
            m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL,m.IDENTITY_SQL,
            m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL,m.ALLOCATION_SQL])
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=membership_created",
                      sink.getvalue())
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=fixture_verified",
                      sink.getvalue())
        self.assertNotIn("postgresql://",sink.getvalue())

    def test_no_auth_person_principal_identity_no_membership_insert(self):
        statements=[]
        reads=[]
        def reader(db,q):
            reads.append(q)
            return "misaligned" if q==m.IDENTITY_SQL else "0"
        sink=io.StringIO()
        with redirect_stdout(sink):
            with self.assertRaises(m.HistoricFixtureRefusal):
                m.adapter(SimpleNamespace(sql=lambda db,q:statements.append(q)),
                          reader).sql(PG,m.ORIGINAL_SEED)
        self.assertEqual(statements,[])
        self.assertEqual(reads,[
            m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL,m.IDENTITY_SQL])
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=person_identity_misaligned",
                      sink.getvalue())

    def test_conflicting_or_inactive_person_membership_never_overwritten(self):
        for active,total in (("0","1"),("1","2"),("2","2")):
            statements=[];sink=io.StringIO()
            def reader(db,q):
                if q==m.MEMBERSHIP_SQL:return active
                if q==m.PERSON_MEMBERSHIP_SQL:return total
                self.fail("Conflicting Person must not enter identity or SQL writes")
            with self.subTest(active=active,total=total),redirect_stdout(sink):
                with self.assertRaises(m.HistoricFixtureRefusal):
                    m.adapter(SimpleNamespace(sql=lambda db,q:statements.append(q)),
                              reader).sql(PG,m.ORIGINAL_SEED)
            self.assertEqual(statements,[])
            self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=membership_not_exactly_one",
                          sink.getvalue())

    def test_absent_member_cannot_claim_pass_without_insert_readback(self):
        statements=[];sink=io.StringIO()
        def reader(db,q):
            if q==m.IDENTITY_SQL:return "aligned"
            if q in (m.MEMBERSHIP_SQL,m.PERSON_MEMBERSHIP_SQL):return "0"
            self.fail("Allocation must not be reached")
        with redirect_stdout(sink):
            with self.assertRaises(m.HistoricFixtureRefusal):
                m.adapter(SimpleNamespace(sql=lambda db,q:statements.append(q)),
                          reader).sql(PG,m.ORIGINAL_SEED)
        self.assertEqual(statements,[m.ORIGINAL_SEED])
        self.assertIn("UNI_OPS_HISTORY_FIXTURE_STAGE=membership_postseed_not_one",
                      sink.getvalue())
        self.assertNotIn("UNI_OPS_HISTORY_FIXTURE_STAGE=fixture_verified",
                         sink.getvalue())

if __name__=="__main__":
    unittest.main(argv=[sys.argv[0]],verbosity=2)
