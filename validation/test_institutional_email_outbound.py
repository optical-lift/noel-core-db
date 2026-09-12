import hashlib
import importlib.util
import pathlib
import sys
import unittest

MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "communications" / "institutional_email_outbound.py"
spec = importlib.util.spec_from_file_location("institutional_email_outbound", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class FakeClient:
    def __init__(self):
        self.settings = mod.RuntimeSettings("https://example.invalid", "secret", "source-1", "worker-1")
        self.results = []
        self.manifest = []
        self.downloads = {}
        self.reply = {"messageId": "<prior@example.org>", "references": ["<root@example.org>"], "sourceThreadRef": "thread-1"}
        self.leases = []
        self.payloads = {}
        self.expired_called = 0

    def finalize_transport(self, *args, **kwargs): self.results.append((args, kwargs))
    def attachment_manifest(self, operation_id): return self.manifest
    def download_attachment(self, bucket, path): return self.downloads[(bucket, path)]
    def reply_context(self, event_id): return self.reply
    def mark_expired_uncertain(self): self.expired_called += 1
    def transport_config(self): return {"mailConfig": {"smtp": {"host": "smtp.example.org", "port": 587, "security": "starttls"}, "username": "sender@example.org", "password": "pw"}}
    def lease(self): return self.leases
    def payload(self, operation_id): return self.payloads[operation_id]


class FakeSMTP:
    def __init__(self, *, rcpt=None, data=(250, b"queued"), data_exc=None, mail=(250, b"ok"), connect_exc=None):
        if connect_exc: raise connect_exc
        self.rcpt_map = rcpt or {}
        self.data_result = data
        self.data_exc = data_exc
        self.data_calls = 0
        self.raw = None
    def login(self, username, password): self.login_args = (username, password)
    def mail(self, address): return (250, b"ok")
    def rcpt(self, address): return self.rcpt_map.get(address, (250, b"ok"))
    def data(self, raw):
        self.data_calls += 1
        self.raw = raw
        if self.data_exc: raise self.data_exc
        return self.data_result
    def quit(self): pass


def payload(state="leased", owner="worker-1"):
    return {
        "outboundOperationId": "op-1", "operationState": state, "leaseOwner": owner,
        "connectedSourceId": "source-1", "fromAddress": "sender@example.org", "fromDisplayName": "Sender",
        "to": [{"address": "to@example.net", "name": "To"}], "cc": [{"address": "cc@example.net"}],
        "bcc": [{"address": "bcc@example.net"}], "subject": "Hello", "bodyText": "Plain", "bodyHtml": "<p>HTML</p>",
        "attachmentRefs": [], "replyToCommunicationEventId": "event-1",
    }


class RuntimeTests(unittest.TestCase):
    def test_no_provider_or_organization_hardcoding(self):
        source = MODULE_PATH.read_text()
        for forbidden in ("dreamhost", "elmfarm", "prepare_institutional_email_send_self_api_v1"):
            self.assertNotIn(forbidden, source.lower())

    def test_lease_must_match_before_smtp(self):
        client = FakeClient()
        called = []
        with self.assertRaises(mod.AtlasContractError):
            mod.send_operation(client, payload(owner="someone-else"), client.transport_config(), lambda cfg: called.append(cfg))
        self.assertEqual([], called)
        self.assertEqual([], client.results)

    def test_mime_threading_and_bcc_envelope_only(self):
        msg, rows, _ = mod.build_message(payload(), client_reply := FakeClient().reply, [])
        self.assertEqual("To <to@example.net>", msg["To"])
        self.assertEqual("cc@example.net", msg["Cc"])
        self.assertIsNone(msg["Bcc"])
        self.assertEqual("<prior@example.org>", msg["In-Reply-To"])
        self.assertIn("<root@example.org>", msg["References"])
        self.assertEqual(3, len(rows))

    def test_attachment_hash_mismatch_blocks_before_data(self):
        client = FakeClient()
        client.manifest = [{"attachmentId":"a1","bucket":"private","path":"x/a.txt","fileName":"a.txt","mimeType":"text/plain","sha256":"00","byteLength":3}]
        client.downloads[("private","x/a.txt")] = b"abc"
        smtp = FakeSMTP()
        state = mod.send_operation(client, payload(), client.transport_config(), lambda cfg: smtp)
        self.assertEqual("transport_error", state)
        self.assertEqual(0, smtp.data_calls)
        self.assertEqual("transport_error", client.results[0][0][1])

    def test_explicit_recipient_rejection_is_recorded(self):
        client = FakeClient()
        smtp = FakeSMTP(rcpt={"to@example.net": (550, b"no"), "cc@example.net": (550, b"no"), "bcc@example.net": (550, b"no")})
        state = mod.send_operation(client, payload(), client.transport_config(), lambda cfg: smtp)
        self.assertEqual("rejected", state)
        self.assertEqual(0, smtp.data_calls)
        self.assertEqual("rejected", client.results[0][0][1])

    def test_pre_data_connection_failure_is_known_transport_error(self):
        client = FakeClient()
        state = mod.send_operation(client, payload(), client.transport_config(), lambda cfg: (_ for _ in ()).throw(ConnectionError("offline")))
        self.assertEqual("transport_error", state)
        self.assertEqual("transport_error", client.results[0][0][1])

    def test_post_data_ambiguity_records_nothing(self):
        client = FakeClient()
        smtp = FakeSMTP(data_exc=TimeoutError("lost after DATA"))
        state = mod.send_operation(client, payload(), client.transport_config(), lambda cfg: smtp)
        self.assertEqual("transport_uncertain", state)
        self.assertEqual(1, smtp.data_calls)
        self.assertEqual([], client.results)

    def test_success_reports_transport_facts_only(self):
        client = FakeClient()
        smtp = FakeSMTP()
        state = mod.send_operation(client, payload(), client.transport_config(), lambda cfg: smtp)
        self.assertEqual("accepted", state)
        args, _ = client.results[0]
        self.assertEqual("accepted", args[1])
        self.assertTrue(args[2].startswith("<"))
        self.assertEqual("data", args[3]["phase"])
        self.assertEqual(3, len(args[4]))
        self.assertEqual(6, len(args))

    def test_worker_never_constructs_canonical_event(self):
        source = MODULE_PATH.read_text()
        self.assertNotIn("build_canonical_event", source)
        self.assertNotIn("record_communication_outbound_result_service_v2", source)
        self.assertIn("finalize_communication_outbound_transport_service_v1", source)

    def test_rpc_wrappers_unwrap_items_contract(self):
        settings = mod.RuntimeSettings("https://example.invalid", "secret", "source-1", "worker-1")
        client = mod.AtlasClient(settings)
        client.rpc = lambda name, payload: {"items": [{"id": "x"}]}
        self.assertEqual([{"id": "x"}], client.lease())
        self.assertEqual([{"id": "x"}], client.attachment_manifest("op-1"))

    def test_transport_uncertain_payload_is_never_sent(self):
        client = FakeClient()
        client.leases = [{"outboundOperationId": "op-1"}]
        client.payloads["op-1"] = payload(state="transport_uncertain")
        called = []
        result = mod.run_once(client, lambda cfg: called.append(cfg))
        self.assertEqual([], result)
        self.assertEqual([], called)
        self.assertEqual(1, client.expired_called)


if __name__ == "__main__":
    unittest.main()
