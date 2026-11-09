"""Source-only U2->U4 probe controls. NOT a PostgreSQL or signed actor test."""
import importlib.util
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
