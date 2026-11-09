"""Source-only U2->U4 probe controls. NOT a PostgreSQL or signed actor test."""
import importlib.util
import contextlib
import io
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "u4_held",HERE/"uniops_u2_qualified_actual_followon_held.py")
u4=importlib.util.module_from_spec(spec)
spec.loader.exec_module(u4)

class U4Boundaries(unittest.TestCase):
    def test_loopback_only(self):
        self.assertTrue(u4.local_only(
            "postgresql://postgres:synthetic@127.0.0.1:54322/postgres"))
        for unsafe in (
            "postgresql://postgres:secret@db.example.com:5432/postgres",
            "postgresql://postgres:secret@localhost:5432/postgres",
            "postgresql://postgres:secret@10.0.0.1:5432/postgres",
            "postgresql://postgres:secret@127.0.0.1:5432/production",
            "",
            None,
        ):
            self.assertFalse(u4.local_only(unsafe))

    def test_exact_receipt_never_infers_done(self):
        work="e5200000-0000-4000-8000-000000000d07"
        positive={
            "ok":True,"workItemId":work,
            "physicalActualContractVersion":"continuing_care_actual_v1",
            "workState":"completed","noNewWorkCreated":True,
            "noClockAdmission":True,
            "workResultId":"e5200000-0000-4000-8000-000000000d08",
        }
        self.assertTrue(u4.accepted_receipt(positive,work))
        for field,wrong in (
            ("ok",False),("workItemId","wrong"),
            ("physicalActualContractVersion","generic_done"),
            ("workState","open"),("noNewWorkCreated",False),
            ("noClockAdmission",False),("workResultId",None),
        ):
            altered=dict(positive,**{field:wrong})
            self.assertFalse(u4.accepted_receipt(altered,work))
        self.assertFalse(u4.accepted_receipt(None,work))

    def test_nonlocal_never_contacts_sql_or_rest(self):
        def forbidden(*_args,**_kwargs):
            raise AssertionError("Network/source operation attempted")
        with self.assertRaisesRegex(AssertionError,"loopback"):
            u4.prove("postgresql://postgres:secret@db.example.com:5432/postgres",
                     "https://example.com","key",
                     {"owner":"x","worker":"y","outsider":"z"},
                     "e5200000-0000-4000-8000-000000000d07",
                     sql=forbidden,rpc=forbidden)

    def test_only_existing_exact_source_tables_admitted(self):
        expected={
            "atlas.work_items",
            "atlas.work_allocations",
            "atlas.company_work_native_ledger_relevance",
            "atlas.work_item_context_links",
            "atlas.work_execution_results",
            "atlas.work_result_acceptances",
            "atlas.tasks",
            "atlas.governed_prework_candidate_offers_v1",
            "atlas.work_execution_plans",
            "atlas.work_lifecycle_events_v1",
        }
        self.assertEqual(u4.U4_COUNT_TABLES,expected)
        for table in expected:
            self.assertTrue(u4.count_table_allowed(table))
        for forbidden in (
            "",None,0,"atlas.tasks;drop table atlas.tasks",
            "atlas.tasks where true","atlas.governed_prework_candidate_offers_v2",
            "atlas.some_unreviewed_table","auth.users","public.other",
            "atlas.work_items ","atlas.work_items\n", "atlas..tasks",
        ):
            self.assertFalse(u4.count_table_allowed(forbidden))

    def test_allowlisted_failure_gate_never_prints_untrusted_message(self):
        self.assertEqual(len(u4.U4_DENIAL_CLASSES),20)
        self.assertEqual(len(set(u4.U4_DENIAL_CLASSES.values())),20)
        out=io.StringIO()
        with contextlib.redirect_stdout(out):
            with self.assertRaisesRegex(AssertionError,"RPC is NOT in clone"):
                u4.require(False,
                    "U4 source-authenticated physical Actual RPC is NOT in clone")
        self.assertEqual(out.getvalue(),
            "U4_SIGNED_FAILURE_GATE=public_actual_signature_gate\n")
        out=io.StringIO()
        unexpected="private JWT and response data must not print"
        with contextlib.redirect_stdout(out):
            with self.assertRaisesRegex(AssertionError,"private JWT"):
                u4.require(False,unexpected)
        self.assertEqual(out.getvalue(),
            "U4_SIGNED_FAILURE_GATE=unclassified_probe_assertion\n")
        self.assertNotIn(unexpected,out.getvalue())
        out=io.StringIO()
        with contextlib.redirect_stdout(out):
            u4.require(True,unexpected)
        self.assertEqual(out.getvalue(),"")

    def test_actual_result_diagnostics_are_finite_and_never_expose_response(self):
        work="e5200000-0000-4000-8000-000000000d07"
        good={
            "ok":True,"workItemId":work,
            "physicalActualContractVersion":"continuing_care_actual_v1",
            "workState":"completed","noNewWorkCreated":True,
            "noClockAdmission":True,
            "workResultId":"e5200000-0000-4000-8000-000000000d08",
        }
        self.assertEqual(
            u4.actual_response_classes(200,good,work),
            ("ok","none_or_other","accepted"))
        variants=(
            (None,"non_object"),({"ok":False},"not_ok"),
            (dict(good,workItemId="unknown"),"work_item_mismatch"),
            (dict(good,physicalActualContractVersion="other"),"actual_contract_mismatch"),
            (dict(good,workState="open"),"not_completed"),
            (dict(good,noNewWorkCreated=False),"new_work_not_absent"),
            (dict(good,noClockAdmission=False),"clock_not_absent"),
            (dict(good,workResultId=None),"result_id_not_uuid"),
        )
        for response,expected in variants:
            with self.subTest(expected=expected):
                self.assertEqual(
                    u4.actual_response_classes(200,response,work),
                    ("ok","none_or_other",expected))
        for status,expected in ((400,"bad_request"),(401,"unauthorized"),
                                (403,"forbidden"),(404,"not_found"),
                                (409,"conflict"),(500,"server_failure"),
                                (503,"server_failure"),(429,"other_status")):
            response={"code":"42501","message":"private bearer token SECRET"}
            labels=u4.actual_response_classes(status,response,work)
            self.assertEqual(labels,(expected,"source_permission","not_checked"))
            self.assertNotIn("private",repr(labels))
            self.assertNotIn("SECRET",repr(labels))
        self.assertEqual(
            u4.actual_response_classes(400,{"code":"22023"},work),
            ("bad_request","source_argument","not_checked"))
        self.assertEqual(
            u4.actual_response_classes(400,{"code":["dynamic","untrusted"]},work),
            ("bad_request","none_or_other","not_checked"))
        self.assertEqual(
            u4.actual_response_classes(200,dict(good,code="private"),work),
            ("ok","none_or_other","accepted"))
        self.assertEqual(len(set(u4.U4_RECEIPT_FIELD_CLASSES)),10)
        self.assertEqual(len(set(u4.U4_SQL_ERROR_CLASSES.values())),7)

    def test_driver_is_explicit_opt_in(self):
        driver=(HERE/"validate-uniops-option-a-u2-accepted-first-signed.py").read_text()
        self.assertIn('action="store_true"',driver)
        self.assertIn('if a.u4_actual_followon:',driver)
        self.assertIn('follow.prove(a.db_url,api,key,',driver)
        self.assertIn('new_work,sql=sql,rpc=rpc)',driver)
        self.assertLess(driver.index('No physical Result can be synthesized by consent'),
                        driver.index('if a.u4_actual_followon:'))
        self.assertLess(driver.index('if a.u4_actual_followon:'),
                        driver.index('delete from auth.sessions where id='))

if __name__=="__main__":
    unittest.main()
