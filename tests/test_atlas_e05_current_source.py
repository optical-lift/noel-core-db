"""E05 source-only preflight tests: all SQL stays synthetic/mock."""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

SRC=Path(__file__).resolve().parents[1]/"scripts/check-atlas-e05-current-source.py"
spec=importlib.util.spec_from_file_location("e05_source",SRC)
e05=importlib.util.module_from_spec(spec)
spec.loader.exec_module(e05)

class E05CurrentSourceTests(unittest.TestCase):
    def fixture(self,temp):
        pg=temp/"pg";pg.mkdir()
        found={key:True for key in e05.RELATIONS}
        found.update({key:True for key in e05.FUNCTIONS})
        found.update({"role.anon":True,"role.authenticated":True,
            "role.authenticator":True,
            "role.authenticator.authenticated":True,
            "role.authenticator.anon":True,
            "empty.auth.users":True,"empty.atlas.work_items":True,
            "empty.atlas.organizations":True,"empty.ledger.seats":True,
            "empty.reality.person":True})
        for name in e05.PUBLIC_CALLS:
            found["acl.authenticated."+name]=True
            found["acl.anon.denied."+name]=True
        return {"database":"atlas_e05_12345678","server":"127.0.0.1",
                "pgdata":str(pg),"surfaces":found}

    def test_eligible_means_no_full_parity_or_signed_claim(self):
        with tempfile.TemporaryDirectory() as root:
            temp=Path(root)
            result=e05.check(self.fixture(temp),"atlas_e05_12345678",temp)
            self.assertEqual(result["state"],"E05_SOURCE_ELIGIBLE_NOT_FULL_PARITY")
            self.assertEqual(result["signedSourceAcceptance"],"NOT_RUN")
            self.assertFalse(result["permissionsChanged"])

    def test_stale_clone_missing_three_deps_refused(self):
        with tempfile.TemporaryDirectory() as root:
            temp=Path(root)
            x=self.fixture(temp)
            for key in ("ledger.booking_requests","ledger.booking_offerings",
                        "atlas.company_work_native_ledger_exact_source_v1"):
                x["surfaces"][key]=False
            with self.assertRaisesRegex(e05.Refused,"ledger.booking_requests"):
                e05.check(x,"atlas_e05_12345678",temp)

    def test_wrong_rpc_grants_refused(self):
        with tempfile.TemporaryDirectory() as root:
            temp=Path(root);x=self.fixture(temp)
            key="acl.anon.denied.public.connected_person_my_work_self_api_v1"
            x["surfaces"][key]=False
            with self.assertRaisesRegex(e05.Refused,"acl.anon.denied"):
                e05.check(x,"atlas_e05_12345678",temp)
            x["surfaces"][key]=True
            x["surfaces"]["role.authenticator.authenticated"]=False
            with self.assertRaisesRegex(e05.Refused,"role.authenticator"):
                e05.check(x,"atlas_e05_12345678",temp)

    def test_existing_user_or_organization_refused(self):
        with tempfile.TemporaryDirectory() as root:
            temp=Path(root);x=self.fixture(temp)
            x["surfaces"]["empty.atlas.organizations"]=False
            with self.assertRaisesRegex(e05.Refused,"empty.atlas.organizations"):
                e05.check(x,"atlas_e05_12345678",temp)

    def test_production_original_clone_and_password_urls_denied(self):
        with tempfile.TemporaryDirectory() as root:
            temp=Path(root)
            for url in ("postgresql://postgres@127.0.0.1:55432/noel_schema_clone",
                        "postgresql://postgres:secret@127.0.0.1:55666/atlas_e05_12345678",
                        "postgresql://postgres@remote.example:55666/atlas_e05_12345678",
                        "postgresql://postgres@127.0.0.1:55666/postgres",
                        "postgresql://postgres@127.0.0.1:55666/atlas_e05_12345678#frag"):
                with self.assertRaises(e05.Refused):
                    e05.guard_url(url,temp)
            self.assertEqual(e05.guard_url(
                "postgresql://postgres@127.0.0.1:55666/atlas_e05_12345678",temp),
                "atlas_e05_12345678")

    def test_no_mutating_sql_or_row_extraction(self):
        sql=e05.surface_sql()
        self.assertIn("to_regclass('ledger.booking_offerings')",sql)
        self.assertIn("to_regprocedure('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)')",sql)
        self.assertIn("has_function_privilege('authenticated'",sql)
        self.assertIn("SELECT count(*)=0 FROM auth.users",sql)
        self.assertNotRegex(sql,re.compile(r"\b(?:insert|update|delete|grant|revoke|alter|drop|copy|create)\b",re.I))

    def test_foreign_pgdata_denied(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as other:
            temp=Path(root);x=self.fixture(temp);x["pgdata"]=other
            with self.assertRaises(e05.Refused):
                e05.check(x,"atlas_e05_12345678",temp)

if __name__=="__main__":
    unittest.main()
