"""Unprivileged hosted E05 source/refusal tests; no database, Docker or secrets."""
import ast
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"scripts/run-atlas-e05-hosted-protected.py"

class HostedE05SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=SOURCE.read_text(encoding="utf-8")
        ast.parse(cls.s)
        spec=importlib.util.spec_from_file_location("hosted_e05_source_contract",SOURCE)
        cls.mod=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.mod)

    def test_exact_host_and_private_snapshot_files(self):
        s=self.s
        self.assertIn("platform.system()=='Linux'",s)
        self.assertIn("platform.machine()=='x86_64'",s)
        self.assertIn("owner.safe_file(roles_path,temp)",s)
        self.assertIn("owner.safe_file(schema_path,temp)",s)
        self.assertNotIn("NOEL_CORE_DATABASE_URL",s)
        self.assertNotIn("service_role",s)
        self.assertIn("'PGDATA='+data",s)
        self.assertIn("'POSTGRES_PASSWORD='+passwd",s)
        self.assertIn("f'127.0.0.1:{port}:5432'",s)
        self.assertIn("temp in Path(p[2]).resolve(strict=True).parents",s)

    def test_no_forged_identity_or_unreviewed_runner(self):
        s=self.s
        self.assertIn("owner.PINNED_BLOBS",s)
        self.assertIn("owner.git_blob(path)==expected",s)
        self.assertIn("run-atlas-e05-isolated-riversong.py",s)
        self.assertIn("E05_SIGNED_SOURCE_ACCEPTANCE=PASS;",s)
        self.assertIn("native.GO_URL,native.GO_SHA=GO_URL,GO_SHA",s)
        self.assertIn("native.REST_URL,native.REST_SHA=REST_URL,REST_SHA",s)
        self.assertIn("GOTRUE_DISABLE_SIGNUP='true'",s)
        self.assertIn("ThreadingHTTPServer",s)

    def test_order_of_bootstrap_roles_auth_schema_gate_rest_signed(self):
        s=self.s
        positions=[s.index("private_command(['psql',db,'-X','-v','ON_ERROR_STOP=1','-f',roles]"),
                   s.index("authport,secret=auth_start("),
                   s.index("private_command(['psql',db,'-X','-v','ON_ERROR_STOP=1','-f',schema]"),
                   s.index("gate=subprocess.run("),
                   s.index("restport=rest_start("),
                   s.index("bridge=subprocess.run(")]
        self.assertEqual(positions,sorted(positions))

    def test_owner_approved_platform_artifact_hashes(self):
        self.assertEqual(self.mod.GO_SHA,"1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730")
        self.assertEqual(self.mod.REST_SHA,"eb4471a7b8112a54e103539f2348c4d7f1c5b9b390649700ad62836e9211e279")
        self.assertEqual(self.mod.PG_IMAGE,
            "supabase/postgres:17.6.1.136@sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00")

    def test_real_docker_bridge_sql_identity(self):
        # A connection to host 127.0.0.1:port reaches PostgreSQL at the
        # Docker bridge IP; this must be checked against docker inspect.
        import copy
        name="atlas-e05-0123456789abcdef"
        data="/tmp/runner/e05-hosted-pg.abc/db"
        port=55221
        server_ip="172.19.0.4"
        detail={
            "Name":"/"+name,
            "State":{"Running":True},
            "Mounts":[{"Type":"bind","Source":data,"Destination":data,"RW":True}],
            "NetworkSettings":{
                "Ports":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":str(port)}]},
                "Networks":{"e05bridge":{"IPAddress":server_ip}}
            }
        }
        self.assertTrue(self.mod.attested_pg_connection(
            detail,name,data,port,server_ip))
        self.assertNotIn("p[1]=='127.0.0.1'",self.s)
        mutations=(
            lambda d:d["State"].update({"Running":False}),
            lambda d:d.update({"Name":"/another-container"}),
            lambda d:d["Mounts"][0].update({"Source":"/var/lib/postgresql/data"}),
            lambda d:d["Mounts"][0].update({"Type":"volume"}),
            lambda d:d["Mounts"][0].update({"RW":False}),
            lambda d:d["NetworkSettings"]["Ports"]["5432/tcp"][0].update(
                {"HostIp":"0.0.0.0"}),
            lambda d:d["NetworkSettings"]["Ports"]["5432/tcp"][0].update(
                {"HostPort":"5432"}),
            lambda d:d["NetworkSettings"]["Networks"]["e05bridge"].update(
                {"IPAddress":"172.19.0.9"}),
        )
        for mutation in mutations:
            wrong=copy.deepcopy(detail)
            mutation(wrong)
            with self.assertRaises(self.mod.Held):
                self.mod.attested_pg_connection(
                    wrong,name,data,port,server_ip)
        with self.assertRaises(self.mod.Held):
            self.mod.attested_pg_connection(detail,name,data,port,"127.0.0.1")

    def test_fail_closed_on_other_platform(self):
        with patch.object(self.mod.platform,"system",return_value="Darwin"):
            with self.assertRaises(self.mod.Held):
                self.mod.run(Path("/none"),Path("/none"),"/none","/none")

    def test_cleanups_only_job_owned_dir_and_no_foreign_delete(self):
        s=self.s
        self.assertIn("resources['name']=name",s)
        self.assertIn("resources['dbroot']=root",s)
        self.assertIn("temp in root.resolve().parents",s)
        self.assertIn("root.name.startswith('e05-hosted-pg.')",s)
        self.assertIn("try:clean_docker(resources,temp)",s)
        self.assertIn("'sudo','rm','-rf','--',str(root)",s)
        with patch.object(self.mod.subprocess,"run",side_effect=AssertionError("must not execute")):
            with self.assertRaises(self.mod.Held):
                self.mod.clean_docker({"dbroot":Path("/var/lib/foreign"),
                                       "name":None},Path("/tmp/job-e05"))

if __name__=="__main__":
    unittest.main()
