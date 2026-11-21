"""INC-17: no external database or Docker used by these refusal/contract tests."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"scripts/check-atlas-e05-docker-current-source.py"
spec=importlib.util.spec_from_file_location("e05_docker_source",SOURCE)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
native=module.source_module("check-atlas-e05-current-source.py","e05_native_test_contract")

class DockerCurrentSourceTests(unittest.TestCase):
    def test_catalog_presence_is_read_only_and_reuses_native_names(self):
        sql=module.catalog_presence_sql(native)
        self.assertTrue(sql.startswith("SELECT jsonb_build_object("))
        self.assertIn("to_regclass('atlas.work_items')",sql)
        self.assertIn("to_regprocedure('public.connected_person_my_work_self_api_v1(integer,uuid)')",sql)
        self.assertIn("to_regrole('authenticator')",sql)
        self.assertNotIn("count(*)",sql)
        self.assertNotRegex(sql,re.compile(
            r"\b(insert|update|delete|grant|revoke|alter|drop|copy|create)\b",re.I))
        expected=set(native.RELATIONS)|set(native.FUNCTIONS)|{
            "role.anon","role.authenticated","role.authenticator"}
        inventory={name:True for name in expected}
        self.assertTrue(module.exact_presence(inventory,native))
        inventory["atlas.work_items"]=False
        self.assertFalse(module.exact_presence(inventory,native))
        inventory["unknown"]=True
        with self.assertRaises(module.Refused):
            module.exact_presence(inventory,native)

    def test_native_custody_and_signed_runner_remain_unchanged(self):
        checker=(ROOT/"scripts/check-atlas-e05-current-source.py").read_text()
        runner=(ROOT/"scripts/prepare-atlas-e05-nonfarm-clone-fixture.py").read_text()
        atlas=(ROOT/"scripts/run-atlas-e05-isolated-riversong.py").read_text()
        self.assertIn('result["server"]=="127.0.0.1"',checker)
        self.assertIn('temp in pgdata.parents',checker)
        self.assertIn("DATABASE.fullmatch(parsed.path[1:])",runner)
        self.assertIn('preparer.guard(config.db_url, preparer.job_temp())',atlas)
        source=SOURCE.read_text()
        self.assertIn("current.require_source_surfaces(result",source)
        self.assertNotIn("service_role",source.lower())
        self.assertNotIn("NOEL_CORE_DATABASE_URL=",source)
        self.assertNotIn("supabase db dump",source)

    def test_refuses_remote_url_before_sql_or_docker_access(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/"e05-supported-stack.probe"
            root.mkdir()
            with patch.dict(os.environ,{"RUNNER_TEMP":td}), \
                 patch.object(module,"query",side_effect=AssertionError("no query")), \
                 patch.object(module,"docker_inspect",side_effect=AssertionError("no Docker")):
                with self.assertRaisesRegex(Exception,"loopback"):
                    module.check("postgresql://postgres@prod.example.com:5432/postgres",
                                 {"PGPASSWORD":"postgres"},root,
                                 "e05host_0123456789abcdef",
                                 "e05net_0123456789abcdef",
                                 "supabase_db_e05host_0123456789abcdef",5432)

    def test_mocked_exact_docker_success_and_missing_schema_hold(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/"e05-supported-stack.fixture"
            config=root/"project"/"supabase"
            config.mkdir(parents=True)
            project="e05host_0123456789abcdef"
            network="e05net_0123456789abcdef"
            port=58231
            (config/"config.toml").write_text(
                'project_id = "'+project+'"\n[db]\nport = '+str(port)+'\n')
            db="postgresql://postgres@127.0.0.1:"+str(port)+"/postgres"
            volume="supabase_db_"+project
            ip="172.18.0.9"
            pgdata="/var/lib/postgresql/data"
            info={"Name":"/supabase_db_"+project,"State":{"Running":True},
                  "Mounts":[{"Type":"volume","Name":volume,"Destination":pgdata}],
                  "NetworkSettings":{
                      "Networks":{network:{"IPAddress":ip}},
                      "Ports":{"5432/tcp":[{"HostIp":"127.0.0.1",
                                           "HostPort":str(port)}]}}}
            netinfo={"Name":network,"Driver":"bridge",
                     "Options":{"com.docker.network.bridge.host_binding_ipv4":
                                "127.0.0.1"}}
            flags=set(native.RELATIONS)|set(native.FUNCTIONS)|{
                "role.anon","role.authenticated","role.authenticator"}
            flags={name:True for name in flags}
            surfaces={key:True for key in native.RELATIONS}
            surfaces.update({key:True for key in native.FUNCTIONS})
            surfaces.update({"role.anon":True,"role.authenticated":True,
                "role.authenticator":True,
                "role.authenticator.authenticated":True,
                "role.authenticator.anon":True,
                "empty.auth.users":True,"empty.atlas.work_items":True,
                "empty.atlas.organizations":True,"empty.ledger.seats":True,
                "empty.reality.person":True})
            for name in native.PUBLIC_CALLS:
                surfaces["acl.authenticated."+name]=True
                surfaces["acl.anon.denied."+name]=True
            response={"database":"postgres","server":ip,"pgdata":pgdata,
                      "surfaces":surfaces}
            def fake_query(_url,_env,sql):
                if sql.startswith("SELECT current_database()"):
                    return "postgres|"+ip+"|"+pgdata+"|170000|0|0"
                if "'empty.auth.users'" in sql:
                    return json.dumps(response)
                return json.dumps(flags)
            def fake_run(args,**kw):
                if args[:3]==["docker","network","inspect"]:
                    return subprocess.CompletedProcess(args,0,json.dumps([netinfo]),"")
                raise AssertionError("Unexpected external call")
            with patch.dict(os.environ,{"RUNNER_TEMP":td}), \
                 patch.object(module,"query",side_effect=fake_query), \
                 patch.object(module,"docker_inspect",return_value=info), \
                 patch.object(subprocess,"run",side_effect=fake_run):
                ready=module.check(db,{"PGPASSWORD":"postgres"},root,
                                   project,network,volume,port)
                self.assertEqual(ready["state"],"DOCKER_SOURCE_ELIGIBLE_NOT_FULL_PARITY")
                self.assertEqual(ready["checkedSurfaces"],len(surfaces))
                self.assertEqual(ready["signedSourceAcceptance"],"NOT_RUN")
                self.assertFalse(ready["productionChanges"])
                flags["atlas.work_items"]=False
                held=module.check(db,{"PGPASSWORD":"postgres"},root,
                                  project,network,volume,port)
                self.assertEqual(held["state"],"HELD_MISSING_CURRENT_SOURCE")
                self.assertEqual(held["dockerCustody"],"PASS")
                wrong=json.loads(json.dumps(info))
                wrong["NetworkSettings"]["Ports"]["5432/tcp"][0]["HostIp"]="0.0.0.0"
                with patch.object(module,"docker_inspect",return_value=wrong):
                    with self.assertRaises(Exception):
                        module.check(db,{"PGPASSWORD":"postgres"},root,
                                     project,network,volume,port)

if __name__=="__main__":
    unittest.main()
