"""U1.15: fictional only; no customer data, live database or owner keys."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/titus-u115-local-owner-vault-drill.py"
SPEC = importlib.util.spec_from_file_location("titus_u115", SCRIPT)
u115 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(u115)


class TestOwnerVaultDrill(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.vault = self.root / "vault"
        self.replica = self.root / "replica"
        self.keydir = self.root / "offline-fictional-key"
        for path in (self.vault, self.replica, self.keydir):
            path.mkdir(mode=0o700)
        self.key = self.keydir / "test-private-key.pem"
        self.cert = self.keydir / "test-cert.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:3072",
            "-nodes", "-keyout", str(self.key), "-out", str(self.cert),
            "-days", "9", "-subj", "/CN=fictional-test-only",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.key.chmod(0o600)

    def tearDown(self):
        self.temp.cleanup()

    def prove(self, key=None, vault=None, replica=None):
        return u115.synthetic_drill(
            str(vault or self.vault),
            str(replica or self.replica), str(self.cert),
            str(key or self.key), fictional_test=True,
        )

    def test_synthetic_encrypted_copy_and_cleanup(self):
        sentinel = self.vault / "KEEP-ME"
        sentinel.write_text("not part of drill")
        receipt = self.prove()
        self.assertTrue(receipt["syntheticRoundtrip"])
        self.assertTrue(receipt["independentDirectoryCopy"])
        self.assertTrue(receipt["encryptedWitnessValidated"])
        self.assertFalse(receipt["productionBackupCreated"])
        self.assertFalse(receipt["offDeviceDisasterRecoveryProved"])
        self.assertEqual(sorted(p.name for p in self.vault.iterdir()),
                         ["KEEP-ME"])
        self.assertEqual(list(self.replica.iterdir()), [])

    def test_wrong_private_key_fails_without_leftovers(self):
        wrong = self.keydir / "wrong-private-key.pem"
        subprocess.run([
            "openssl", "genpkey", "-algorithm", "RSA",
            "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(wrong),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wrong.chmod(0o600)
        with self.assertRaises(ValueError):
            self.prove(key=wrong)
        self.assertEqual(list(self.vault.iterdir()), [])
        self.assertEqual(list(self.replica.iterdir()), [])

    def test_vault_and_replica_cannot_be_same_or_nested(self):
        with self.assertRaises(ValueError):
            self.prove(replica=self.vault)
        nested = self.vault / "subfolder"
        nested.mkdir(mode=0o700)
        with self.assertRaises(ValueError):
            self.prove(replica=nested)

    def test_untrusted_private_key_location_and_permissions(self):
        self.key.chmod(0o644)
        with self.assertRaises(ValueError):
            self.prove()
        self.key.chmod(0o600)
        secret = self.vault / "bad-private.pem"
        secret.write_bytes(self.key.read_bytes())
        secret.chmod(0o600)
        with self.assertRaises(ValueError):
            self.prove(key=secret)

    def test_unsafe_replica_permissions_or_link_denied(self):
        self.replica.chmod(0o755)
        with self.assertRaises(ValueError):
            self.prove()
        self.replica.chmod(0o700)
        symlink = self.root / "linked"
        symlink.symlink_to(self.replica, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.prove(replica=symlink)

    def test_source_is_not_a_customer_exporter(self):
        code = SCRIPT.read_text("utf-8")
        for prohibited in ("NOEL_CORE_DATABASE_URL", "SUPABASE_SERVICE_ROLE_KEY",
                           "pg_dump", "pg_restore", "psycopg", "requests",
                           "execute_sql(", "apply_migration("):
            self.assertNotIn(prohibited, code)


if __name__ == "__main__":
    unittest.main()
