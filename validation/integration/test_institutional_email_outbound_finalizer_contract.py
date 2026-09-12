#!/usr/bin/env python3
"""Black-box contract tests for Atlas's database-owned outbound transport finalizer.

These tests run only against the disposable production-structure clone created by
recovery-outbound-finalizer-postgres-validation.yml. Every scenario is wrapped
in a transaction and rolled back, so the shared synthetic fixture remains intact.
"""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
import unittest


DB_URL = os.environ.get("LOCAL_DB")
if not DB_URL:
    raise SystemExit("LOCAL_DB is required")


def run_sql(sql: str, *, expect_error: str | None = None) -> dict | None:
    script = "BEGIN;\n" + textwrap.dedent(sql).strip() + "\nROLLBACK;\n"
    proc = subprocess.run(
        ["psql", DB_URL, "-X", "-qAt", "-v", "ON_ERROR_STOP=1"],
        input=script,
        text=True,
        capture_output=True,
        check=False,
    )

    if expect_error is not None:
        if proc.returncode == 0:
            raise AssertionError(
                f"Expected database error containing {expect_error!r}, but SQL succeeded.\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )
        combined = proc.stdout + "\n" + proc.stderr
        if expect_error not in combined:
            raise AssertionError(
                f"Expected database error containing {expect_error!r}.\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )
        return None

    if proc.returncode != 0:
        raise AssertionError(
            f"psql failed with exit code {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )

    for line in reversed(proc.stdout.splitlines()):
        if line.startswith("RESULT|"):
            return json.loads(line.removeprefix("RESULT|"))

    raise AssertionError(
        "SQL completed without a RESULT marker.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )


class OutboundFinalizerContractTests(unittest.TestCase):
    maxDiff = None

    def test_invalid_lease_is_rejected_before_accepted_transport_is_recorded(self) -> None:
        run_sql(
            """
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001210'::uuid,
              'not-the-fixture-worker',
              'accepted',
              '<invalid-lease@example.invalid>',
              '{"phase":"data","smtpCode":250}'::jsonb,
              '[{"role":"to","address":"to@example.invalid","state":"accepted"}]'::jsonb,
              '2026-09-12T16:00:00Z'::timestamptz
            );
            """,
            expect_error="Valid outbound transport lease required.",
        )

    def test_accepted_transport_constructs_one_canonical_event(self) -> None:
        result = run_sql(
            """
            CREATE TEMP TABLE _receipt AS
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001210'::uuid,
              'fixture-worker',
              'accepted',
              '<fixture-accepted@example.invalid>',
              '{"phase":"data","smtpCode":250,"smtpMessage":"queued"}'::jsonb,
              '[
                {"role":"to","address":"to@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
                {"role":"cc","address":"cc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
                {"role":"bcc","address":"bcc@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}}
              ]'::jsonb,
              '2026-09-12T16:00:00Z'::timestamptz
            ) AS value;

            SELECT 'RESULT|' || jsonb_build_object(
              'receipt', (SELECT value FROM _receipt),
              'operationState', (
                SELECT operation_state
                FROM atlas.communication_outbound_operations
                WHERE id='00000000-0000-4000-8000-000000001210'::uuid
              ),
              'eventCount', (
                SELECT count(*)
                FROM atlas.communication_events
                WHERE connected_source_id='00000000-0000-4000-8000-000000001204'::uuid
                  AND source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'
              ),
              'participantCount', (
                SELECT count(*)
                FROM atlas.communication_event_participants p
                JOIN atlas.communication_events e ON e.id=p.communication_event_id
                WHERE e.source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'
              ),
              'attemptCount', (
                SELECT count(*)
                FROM atlas.communication_outbound_attempts
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
              ),
              'recipientResultCount', (
                SELECT count(*)
                FROM atlas.communication_outbound_attempt_recipients
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
              ),
              'eventContract', (
                SELECT jsonb_build_object(
                  'direction', direction,
                  'speakerIsSelf', speaker_is_self,
                  'speakerAddress', speaker_address,
                  'body', body,
                  'bodyState', body_state,
                  'sourceAuthority', source_authority,
                  'permittedStateEffect', permitted_state_effect,
                  'governingStateChanged', governing_state_changed,
                  'schemaVersion', canonical_event->>'schemaVersion',
                  'sourceKind', canonical_event#>>'{source,kind}',
                  'accountRef', canonical_event#>>'{source,accountRef}',
                  'threadRef', canonical_event#>>'{source,threadRef}',
                  'messageId', canonical_event#>>'{sourcePayload,messageId}'
                )
                FROM atlas.communication_events
                WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'
              )
            )::text;
            """
        )
        assert result is not None
        receipt = result["receipt"]
        self.assertEqual(receipt["state"], "accepted")
        self.assertTrue(receipt["canonicalEventConstructed"])
        self.assertEqual(receipt["canonicalEventSource"], "atlas_database")
        self.assertEqual(result["operationState"], "accepted")
        self.assertEqual(result["eventCount"], 1)
        self.assertEqual(result["participantCount"], 4)
        self.assertEqual(result["attemptCount"], 1)
        self.assertEqual(result["recipientResultCount"], 3)
        self.assertEqual(
            result["eventContract"],
            {
                "direction": "outgoing",
                "speakerIsSelf": True,
                "speakerAddress": "fixture-mailbox@example.invalid",
                "body": "Accepted body",
                "bodyState": "exact_text",
                "sourceAuthority": "evidence_only",
                "permittedStateEffect": "append_source_attributed_evidence_only",
                "governingStateChanged": False,
                "schemaVersion": "atlas_communication_event_v1",
                "sourceKind": "imap_smtp_email",
                "accountRef": "fixture-mailbox@example.invalid",
                "threadRef": "atlas-institutional-conversation:00000000-0000-4000-8000-000000001207",
                "messageId": "<fixture-accepted@example.invalid>",
            },
        )

    def test_accepted_replay_is_idempotent(self) -> None:
        result = run_sql(
            """
            CREATE TEMP TABLE _first_receipt AS
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001210'::uuid,
              'fixture-worker',
              'accepted',
              '<fixture-accepted@example.invalid>',
              '{"phase":"data","smtpCode":250}'::jsonb,
              '[{"role":"to","address":"to@example.invalid","state":"accepted"}]'::jsonb,
              '2026-09-12T16:00:00Z'::timestamptz
            ) AS value;

            CREATE TEMP TABLE _replay_receipt AS
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001210'::uuid,
              'fixture-worker',
              'accepted',
              '<fixture-accepted@example.invalid>',
              '{"phase":"data","smtpCode":250,"smtpMessage":"replayed response"}'::jsonb,
              '[{"role":"to","address":"to@example.invalid","state":"accepted"}]'::jsonb,
              '2026-09-12T16:00:00Z'::timestamptz
            ) AS value;

            SELECT 'RESULT|' || jsonb_build_object(
              'replayReceipt', (SELECT value FROM _replay_receipt),
              'eventCount', (
                SELECT count(*) FROM atlas.communication_events
                WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001210'
              ),
              'attemptCount', (
                SELECT count(*) FROM atlas.communication_outbound_attempts
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001210'::uuid
              )
            )::text;
            """
        )
        assert result is not None
        self.assertEqual(result["replayReceipt"]["state"], "already_accepted")
        self.assertEqual(result["replayReceipt"]["operationState"], "accepted")
        self.assertEqual(result["eventCount"], 1)
        self.assertEqual(result["attemptCount"], 1)

    def test_partial_acceptance_preserves_recipient_transport_evidence(self) -> None:
        result = run_sql(
            """
            CREATE TEMP TABLE _receipt AS
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001211'::uuid,
              'fixture-worker',
              'partially_accepted',
              '<fixture-partial@example.invalid>',
              '{"phase":"data","smtpCode":250}'::jsonb,
              '[
                {"role":"to","address":"partial-ok@example.invalid","state":"accepted","providerResponse":{"smtpCode":250}},
                {"role":"to","address":"partial-reject@example.invalid","state":"rejected","providerResponse":{"smtpCode":550}}
              ]'::jsonb,
              '2026-09-12T16:01:00Z'::timestamptz
            ) AS value;

            SELECT 'RESULT|' || jsonb_build_object(
              'receipt', (SELECT value FROM _receipt),
              'operationState', (
                SELECT operation_state FROM atlas.communication_outbound_operations
                WHERE id='00000000-0000-4000-8000-000000001211'::uuid
              ),
              'eventCount', (
                SELECT count(*) FROM atlas.communication_events
                WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001211'
              ),
              'acceptedRecipientCount', (
                SELECT count(*) FROM atlas.communication_outbound_attempt_recipients
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid
                  AND result_state='accepted'
              ),
              'rejectedRecipientCount', (
                SELECT count(*) FROM atlas.communication_outbound_attempt_recipients
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001211'::uuid
                  AND result_state='rejected'
              )
            )::text;
            """
        )
        assert result is not None
        self.assertEqual(result["receipt"]["operationState"], "partially_accepted")
        self.assertTrue(result["receipt"]["canonicalEventConstructed"])
        self.assertEqual(result["operationState"], "partially_accepted")
        self.assertEqual(result["eventCount"], 1)
        self.assertEqual(result["acceptedRecipientCount"], 1)
        self.assertEqual(result["rejectedRecipientCount"], 1)

    def test_known_temporary_failure_records_transport_only(self) -> None:
        result = run_sql(
            """
            CREATE TEMP TABLE _receipt AS
            SELECT atlas.finalize_communication_outbound_transport_service_v1(
              '00000000-0000-4000-8000-000000001212'::uuid,
              'fixture-worker',
              'temporary_failure',
              null,
              '{"phase":"rcpt","smtpCode":451}'::jsonb,
              '[{"role":"to","address":"deferred@example.invalid","state":"deferred","providerResponse":{"smtpCode":451}}]'::jsonb,
              '2026-09-12T16:02:00Z'::timestamptz
            ) AS value;

            SELECT 'RESULT|' || jsonb_build_object(
              'receipt', (SELECT value FROM _receipt),
              'operationState', (
                SELECT operation_state FROM atlas.communication_outbound_operations
                WHERE id='00000000-0000-4000-8000-000000001212'::uuid
              ),
              'eventCount', (
                SELECT count(*) FROM atlas.communication_events
                WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001212'
              ),
              'attemptCount', (
                SELECT count(*) FROM atlas.communication_outbound_attempts
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001212'::uuid
              )
            )::text;
            """
        )
        assert result is not None
        self.assertFalse(result["receipt"]["canonicalEventConstructed"])
        self.assertEqual(result["operationState"], "temporary_failure")
        self.assertEqual(result["eventCount"], 0)
        self.assertEqual(result["attemptCount"], 1)

    def test_expired_unresolved_lease_becomes_transport_uncertain_without_invented_attempt(self) -> None:
        result = run_sql(
            """
            CREATE TEMP TABLE _receipt AS
            SELECT atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(
              '00000000-0000-4000-8000-000000001204'::uuid
            ) AS value;

            SELECT 'RESULT|' || jsonb_build_object(
              'receipt', (SELECT value FROM _receipt),
              'operationState', (
                SELECT operation_state FROM atlas.communication_outbound_operations
                WHERE id='00000000-0000-4000-8000-000000001213'::uuid
              ),
              'eventCount', (
                SELECT count(*) FROM atlas.communication_events
                WHERE source_event_ref='atlas-outbound-operation:00000000-0000-4000-8000-000000001213'
              ),
              'attemptCount', (
                SELECT count(*) FROM atlas.communication_outbound_attempts
                WHERE outbound_operation_id='00000000-0000-4000-8000-000000001213'::uuid
              )
            )::text;
            """
        )
        assert result is not None
        self.assertEqual(result["operationState"], "transport_uncertain")
        self.assertEqual(result["eventCount"], 0)
        self.assertEqual(result["attemptCount"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
