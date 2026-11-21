"""Unprivileged E05 Supabase stack source contract; all subprocesses mocked."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE=Path(__file__).resolve().parents[1]/"scripts/check-atlas-e05-supported-stack.py"
spec=importlib.util.spec_from_file_location("e05supported",SOURCE)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class SupportedStackSource(unittest.TestCase):
    def test_source_does_not_use_production_or_suggest_signed(self):
        s=SOURCE.read_text()
        self.assertNotIn("${{ secrets.",s)
        self.assertNotIn("supabase db dump",s)
        self.assertNotIn("service_role",s)
        self.assertIn('env.pop("NOEL_CORE_DATABASE_URL",None)',s)
        self.assertIn("E05_SIGNED=NOT_RUN",s)
        self.assertIn("supabase"," ".join(s.splitlines()))

    def test_only_hosted_linux(self):
        with patch.object(m.platform,"system",return_value="Darwin"):
            with self.assertRaises(m.Held):
                m.run()

    def test_unique_project_config_rewrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"config.toml"
            p.write_text('project_id = "default"\n[api]\nport = 54321\n[db]\nport = 54322\n')
            m.configure(p,"e05host_0123456789abcdef",50001,50002)
            text=p.read_text()
            self.assertIn('project_id = "e05host_0123456789abcdef"',text)
            self.assertIn('[api]\nport = 50002',text)
            self.assertIn('[db]\nport = 50001',text)
            with self.assertRaises(m.Held):
                m.configure(p,"production",54322,54321)

    def test_reject_unknown_config_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"config.toml"
            p.write_text('[api]\nport = 54321\n[db]\nport = 54322\n')
            with self.assertRaises(m.Held):
                m.configure(p,"e05host_0123456789abcdef",50001,50002)

    def test_volume_attestation_positive_only_exact_job_identity(self):
        x={"Name":"/supabase_db_e05host_0123456789abcdef",
           "State":{"Running":True},
           "Mounts":[{"Type":"volume","Name":"supabase_db_e05host_0123456789abcdef",
                      "Destination":"/var/lib/postgresql/data"}],
           "NetworkSettings":{"Ports":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"50001"}]},
                              "Networks":{"supabase_network":{"IPAddress":"172.18.0.6"}}}}
        self.assertEqual(m.attested_volume(x,"e05host_0123456789abcdef",
                         "/var/lib/postgresql/data",50001,"172.18.0.6"),
                         "supabase_db_e05host_0123456789abcdef")
        for mutation in (
           lambda y:y["State"].update({"Running":False}),
           lambda y:y.update({"Name":"/supabase_db_another"}),
           lambda y:y["Mounts"][0].update({"Name":"supabase_db_another"}),
           lambda y:y["Mounts"][0].update({"Type":"bind"}),
           lambda y:y["NetworkSettings"]["Ports"]["5432/tcp"][0].update({"HostPort":"54322"}),
           lambda y:y["NetworkSettings"]["Ports"]["5432/tcp"][0].update({"HostIp":"0.0.0.0"}),
           lambda y:y["NetworkSettings"]["Ports"]["5432/tcp"].append({"HostIp":"127.0.0.1","HostPort":"50001"}),
           lambda y:y["NetworkSettings"]["Networks"]["supabase_network"].update({"IPAddress":"172.18.0.7"}),
        ):
            import copy
            altered=copy.deepcopy(x)
            mutation(altered)
            with self.assertRaises(m.Held):
                m.attested_volume(altered,"e05host_0123456789abcdef",
                                 "/var/lib/postgresql/data",50001,"172.18.0.6")

    def test_network_must_be_dedicated_loopback_bridge(self):
        base={"Name":"e05net_0123456789abcdef","Driver":"bridge",
              "Options":{"com.docker.network.bridge.host_binding_ipv4":"127.0.0.1"}}
        self.assertTrue(m.attested_network(base,"e05net_0123456789abcdef"))
        import copy
        for mutate in (
            lambda v:v.update({"Name":"foreign-network"}),
            lambda v:v.update({"Driver":"overlay"}),
            lambda v:v["Options"].update(
                {"com.docker.network.bridge.host_binding_ipv4":"0.0.0.0"}),
            lambda v:v.update({"Options":{}})
        ):
            wrong=copy.deepcopy(base)
            mutate(wrong)
            with self.assertRaises(m.Held):
                m.attested_network(wrong,"e05net_0123456789abcdef")
        s=SOURCE.read_text()
        self.assertIn('"--network-id",network',s)
        self.assertIn('com.docker.network.bridge.host_binding_ipv4=127.0.0.1',s)
        self.assertIn('"docker","network","rm",network',s)

    def test_no_shell_injection_or_log_leaks(self):
        s=SOURCE.read_text()
        self.assertIn("capture_output=True",s)
        self.assertNotIn("shell=True",s)
        self.assertIn("supabase\",\"stop\",\"--no-backup",s)
        self.assertNotIn('"--all"',s)
        self.assertIn('prefix="e05-supported-stack."',s)

if __name__=="__main__":
    unittest.main()
