import importlib.util
import pathlib
import sys
import unittest

MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "communications" / "generic_email_transport_verify.py"
spec = importlib.util.spec_from_file_location("generic_email_transport_verify", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class FakeImap:
    def __init__(self):
        self.calls = []
    def login(self, username, password):
        self.calls.append(("login", username, password))
        return "OK", [b"authenticated"]
    def logout(self):
        self.calls.append(("logout",))
        return "BYE", [b""]


class FakeSmtp:
    def __init__(self):
        self.calls = []
    def ehlo(self):
        self.calls.append(("ehlo",))
        return 250, b"ok"
    def starttls(self, context=None):
        self.calls.append(("starttls",))
        return 220, b"ready"
    def login(self, username, password):
        self.calls.append(("login", username, password))
        return 235, b"authenticated"
    def quit(self):
        self.calls.append(("quit",))
        return 221, b"bye"
    def close(self):
        self.calls.append(("close",))


class FakeAtlas:
    def __init__(self, config):
        self.config = config
        self.recorded = []
    def transport_config(self):
        return self.config
    def record_verification(self, imap_ok, smtp_ok, details):
        self.recorded.append((imap_ok, smtp_ok, details))
        return {"authorizationState": "pending", "communicationCapture": False, "communicationSend": False}


class VerificationTests(unittest.TestCase):
    def test_imap_verifier_authenticates_without_mailbox_commands(self):
        fake = FakeImap()
        result = module.verify_imap_auth(
            {"host": "imap.example.test", "port": 993, "security": "ssl"},
            "mailbox@example.test",
            "secret",
            ssl_factory=lambda *args, **kwargs: fake,
        )
        self.assertTrue(result["ok"])
        self.assertEqual([call[0] for call in fake.calls], ["login", "logout"])

    def test_smtp_verifier_authenticates_without_envelope_or_data(self):
        fake = FakeSmtp()
        result = module.verify_smtp_auth(
            {"host": "smtp.example.test", "port": 587, "security": "starttls"},
            "mailbox@example.test",
            "secret",
            plain_factory=lambda *args, **kwargs: fake,
        )
        self.assertTrue(result["ok"])
        self.assertEqual([call[0] for call in fake.calls], ["ehlo", "starttls", "ehlo", "login", "quit"])

    def test_run_records_both_results_but_does_not_activate(self):
        atlas = FakeAtlas({
            "mailConfig": {
                "imap": {"host": "imap.example.test", "port": 993, "security": "ssl"},
                "smtp": {"host": "smtp.example.test", "port": 587, "security": "starttls"},
                "username": "mailbox@example.test",
                "password": "secret",
            }
        })
        settings = module.RuntimeSettings("https://example.supabase.co", "service", "source-id")
        result = module.run_once(
            settings,
            atlas_client=atlas,
            imap_verifier=lambda config, username, password: {"ok": True, "phase": "authenticated"},
            smtp_verifier=lambda config, username, password: {"ok": True, "phase": "authenticated"},
        )
        self.assertTrue(result["verified"])
        self.assertEqual(len(atlas.recorded), 1)
        imap_ok, smtp_ok, details = atlas.recorded[0]
        self.assertTrue(imap_ok)
        self.assertTrue(smtp_ok)
        self.assertEqual(details["mode"], "authentication_only")
        self.assertEqual(result["receipt"]["authorizationState"], "pending")
        self.assertFalse(result["receipt"]["communicationCapture"])
        self.assertFalse(result["receipt"]["communicationSend"])

    def test_static_authority_boundary(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        forbidden = [".select(", ".search(", ".fetch(", ".uid(", ".mail(", ".rcpt(", ".data(", ".sendmail(", ".send_message("]
        for token in forbidden:
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
