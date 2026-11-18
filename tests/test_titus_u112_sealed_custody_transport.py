"""U1.12 synthetic-only X.509 CMS AES-256-GCM custody transport proof."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/titus-u112-sealed-custody-transport.py"
BYTES = b"FICTIONAL only\\r\\nclass & homework\\n" + "song 🌾 history".encode("utf-8")


class TestTitusU112SealedTransport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.vault = base / "vault"
        self.vault.mkdir(mode=0o700)
        self.key = base / "fictional-private.pem"
        self.cert = base / "fictional-public.pem"
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:3072",
             "-nodes", "-keyout", str(self.key), "-out", str(self.cert),
             "-days", "1", "-subj", "/CN=fictional-u112-test-only"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=True, timeout=30,
        )

    def run_cmd(self, mode="seal", data=None, extra=(), name="fictional"):
        cmd = [sys.executable, str(SCRIPT), mode,
               "--vault-dir", str(self.vault), "--name", name,
               "--certificate", str(self.cert)]
        if mode == "verify":
            cmd.extend(["--private-key", str(self.key)])
        cmd.extend(extra)
        return subprocess.run(cmd, input=data, capture_output=True,
                              timeout=30)

    def test_encrypted_independent_process_roundtrip(self):
        initial = self.run_cmd(data=BYTES)
        self.assertEqual(initial.returncode, 0, initial.stderr)
        self.assertIn(b"PASS", initial.stdout)
        self.assertNotIn(BYTES[:12], initial.stdout + initial.stderr)
        files = sorted(self.vault.iterdir())
        self.assertEqual(len(files), 2)
        for f in files:
            self.assertEqual(f.stat().st_mode & 0o077, 0)
            self.assertNotIn(BYTES, f.read_bytes())
        # This is a new verifier process, with private key; not a plaintext export.
        second = self.run_cmd("verify")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn(b"PASS independently verified", second.stdout)
        self.assertNotIn(BYTES[:12], second.stdout + second.stderr)
        self.assertEqual(self.run_cmd(data=BYTES).returncode, 2,
                         "custody evidence must never be overwritten")

    def test_corrupt_ciphertext_and_wrong_key_fail_closed(self):
        self.assertEqual(self.run_cmd(data=BYTES).returncode, 0)
        capsule = self.vault / "fictional.capsule.cms"
        blob = bytearray(capsule.read_bytes())
        blob[-3] ^= 0x20
        capsule.write_bytes(blob)
        self.assertEqual(self.run_cmd("verify").returncode, 2)
        self.assertEqual(self.run_cmd("verify").stdout, b"")
        # Even the correct ciphertext cannot be opened by another identity.
        self.assertEqual(self.run_cmd(data=BYTES, name="second").returncode, 0)
        other_key = Path(self.tmp.name) / "wrong.pem"
        other_cert = Path(self.tmp.name) / "wrong-cert.pem"
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:3072",
             "-nodes", "-keyout", str(other_key), "-out", str(other_cert),
             "-days", "1", "-subj", "/CN=wrong-test-only"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=True, timeout=30,
        )
        wrong = self.run_cmd("verify", name="second",
                             extra=["--private-key", str(other_key)])
        self.assertEqual(wrong.returncode, 2)
        self.assertEqual(wrong.stdout, b"")

    def test_reject_unsafe_vault_empty_input_and_name(self):
        self.assertEqual(self.run_cmd(data=b"").returncode, 2)
        self.assertEqual(list(self.vault.iterdir()), [])
        self.assertEqual(self.run_cmd(data=BYTES, name="../../secret").returncode, 2)
        self.assertEqual(list(self.vault.iterdir()), [])
        self.vault.chmod(0o755)
        self.assertEqual(self.run_cmd(data=BYTES).returncode, 2)
        self.assertEqual(list(self.vault.iterdir()), [])

    def test_repo_and_auth_never_touched_by_transport(self):
        source = SCRIPT.read_text()
        for prohibited in (
            "NOEL_CORE_DATABASE_URL", "SUPABASE_SERVICE_ROLE_KEY",
            "pg_dump", "pg_restore", "github.com", "DELETE FROM",
            "DROP TABLE", "apply_migration",
        ):
            self.assertNotIn(prohibited, source)
        self.assertIn("-aes-256-gcm", source)
        self.assertIn("O_EXCL", source)
        self.assertIn("authenticated sealed archive decryption failed", source)


if __name__ == "__main__":
    unittest.main()
