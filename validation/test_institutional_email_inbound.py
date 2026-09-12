#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import sys
import unittest

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "communications" / "institutional_email_inbound.py"
spec = importlib.util.spec_from_file_location("institutional_email_inbound", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class InstitutionalEmailInboundParserTests(unittest.TestCase):
    def test_parse_rfc822_preserves_headers_participants_body_attachment_and_raw_hash(self):
        raw = (
            b"From: Alice Example <alice@example.com>\r\n"
            b"To: Elm <fixture-mailbox@example.invalid>\r\n"
            b"Cc: Bob <bob@example.com>\r\n"
            b"Subject: Re: Fixture thread\r\n"
            b"Date: Sat, 12 Sep 2026 16:05:00 +0000\r\n"
            b"Message-ID: <reply-1@example.com>\r\n"
            b"In-Reply-To: <atlas-outbound@example.invalid>\r\n"
            b"References: <root@example.com> <atlas-outbound@example.invalid>\r\n"
            b"MIME-Version: 1.0\r\n"
            b"Content-Type: multipart/mixed; boundary=outer\r\n\r\n"
            b"--outer\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello Atlas.\r\n"
            b"--outer\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=note.txt\r\n\r\nattachment bytes\r\n"
            b"--outer--\r\n"
        )
        facts = module.parse_rfc822(raw, mailbox="INBOX", uid_validity=55, uid=77)
        self.assertEqual(facts["p_message_id"], "<reply-1@example.com>")
        self.assertEqual(facts["p_in_reply_to"], "<atlas-outbound@example.invalid>")
        self.assertEqual(facts["p_references"], ["<root@example.com>", "<atlas-outbound@example.invalid>"])
        self.assertEqual(facts["p_from"]["address"], "alice@example.com")
        self.assertEqual(facts["p_to"][0]["address"], "fixture-mailbox@example.invalid")
        self.assertEqual(facts["p_cc"][0]["address"], "bob@example.com")
        self.assertEqual(facts["p_body_text"], "Hello Atlas.")
        self.assertEqual(len(facts["p_attachments"]), 1)
        self.assertEqual(facts["p_attachments"][0]["transferName"], "note.txt")
        self.assertEqual(facts["p_raw_mime_sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(facts["p_raw_byte_length"], len(raw))

    def test_bcc_delivery_can_arrive_without_self_address_in_visible_headers(self):
        raw = (
            b"From: sender@example.com\r\n"
            b"To: public@example.com\r\n"
            b"Message-ID: <bcc-test@example.com>\r\n"
            b"Content-Type: text/plain; charset=utf-8\r\n\r\n"
            b"secret delivery\r\n"
        )
        facts = module.parse_rfc822(raw, mailbox="INBOX", uid_validity=1, uid=2)
        self.assertEqual(facts["p_to"][0]["address"], "public@example.com")
        self.assertEqual(facts["p_bcc"], [])
        self.assertEqual(facts["p_body_text"], "secret delivery")

    def test_message_without_message_id_still_has_transport_identity_inputs(self):
        raw = b"From: sender@example.com\r\nTo: box@example.com\r\n\r\nhello\r\n"
        facts = module.parse_rfc822(raw, mailbox="Archive", uid_validity=9, uid=10)
        self.assertIsNone(facts["p_message_id"])
        self.assertEqual(facts["p_mailbox"], "Archive")
        self.assertEqual(facts["p_uid_validity"], 9)
        self.assertEqual(facts["p_uid"], 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
