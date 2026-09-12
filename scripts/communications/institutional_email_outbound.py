#!/usr/bin/env python3
"""Provider-neutral Atlas institutional email outbound runtime.

This runtime has transport authority only. User/application send authority lives in
Atlas and produces durable outbound operations before this worker sees them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import smtplib
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import formataddr, formatdate, make_msgid
from typing import Any, Callable


class AtlasTransportError(RuntimeError):
    """Known transport failure that occurred before SMTP DATA ambiguity."""


class AtlasContractError(RuntimeError):
    """Atlas service contract was missing or inconsistent."""


@dataclass(frozen=True)
class RuntimeSettings:
    supabase_url: str
    service_role_key: str
    connected_source_id: str
    lease_owner: str
    lease_limit: int = 10
    lease_seconds: int = 120

    @classmethod
    def from_env(cls, connected_source_id: str | None = None) -> "RuntimeSettings":
        source_id = connected_source_id or os.environ.get("ATLAS_CONNECTED_SOURCE_ID", "")
        return cls(
            supabase_url=os.environ["SUPABASE_URL"].rstrip("/"),
            service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            connected_source_id=source_id,
            lease_owner=os.environ.get("ATLAS_EMAIL_LEASE_OWNER", f"institutional-email-{uuid.uuid4()}"),
            lease_limit=int(os.environ.get("ATLAS_EMAIL_LEASE_LIMIT", "10")),
            lease_seconds=int(os.environ.get("ATLAS_EMAIL_LEASE_SECONDS", "120")),
        )


class AtlasClient:
    def __init__(self, settings: RuntimeSettings, opener: Callable[..., Any] = urllib.request.urlopen):
        self.settings = settings
        self._opener = opener

    def _request(self, url: str, *, data: bytes | None = None, method: str = "POST", timeout: int = 45) -> bytes:
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "apikey": self.settings.service_role_key,
                "Authorization": f"Bearer {self.settings.service_role_key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with self._opener(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise AtlasTransportError(f"Atlas HTTP {exc.code}: {body[:1000]}") from exc

    def rpc(self, function_name: str, payload: dict[str, Any]) -> Any:
        raw = self._request(
            f"{self.settings.supabase_url}/rest/v1/rpc/{function_name}",
            data=json.dumps(payload).encode("utf-8"),
        )
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))

    def mark_expired_uncertain(self) -> Any:
        return self.rpc(
            "mark_expired_communication_outbound_leases_uncertain_service_v1",
            {"p_connected_source_id": self.settings.connected_source_id},
        )

    def lease(self) -> list[dict[str, Any]]:
        result = self.rpc(
            "lease_communication_outbound_operations_service_v1",
            {
                "p_connected_source_id": self.settings.connected_source_id,
                "p_lease_owner": self.settings.lease_owner,
                "p_limit": self.settings.lease_limit,
                "p_lease_seconds": self.settings.lease_seconds,
            },
        )
        if isinstance(result, dict):
            return list(result.get("items") or [])
        return list(result or [])

    def transport_config(self) -> dict[str, Any]:
        return self.rpc(
            "generic_email_transport_config_service_v1",
            {"p_connected_source_id": self.settings.connected_source_id},
        ) or {}

    def payload(self, operation_id: str) -> dict[str, Any]:
        return self.rpc(
            "communication_outbound_transport_payload_service_v1",
            {"p_outbound_operation_id": operation_id},
        ) or {}

    def reply_context(self, event_id: str) -> dict[str, Any]:
        return self.rpc(
            "communication_reply_transport_context_service_v1",
            {"p_communication_event_id": event_id},
        ) or {}

    def attachment_manifest(self, operation_id: str) -> list[dict[str, Any]]:
        result = self.rpc(
            "communication_outbound_attachment_transport_service_v1",
            {"p_outbound_operation_id": operation_id},
        )
        if isinstance(result, dict):
            return list(result.get("items") or [])
        return list(result or [])

    def download_attachment(self, bucket: str, path: str) -> bytes:
        encoded_path = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/"))
        encoded_bucket = urllib.parse.quote(bucket, safe="")
        return self._request(
            f"{self.settings.supabase_url}/storage/v1/object/{encoded_bucket}/{encoded_path}",
            method="GET",
            timeout=60,
        )

    def finalize_transport(
        self,
        operation_id: str,
        result_state: str,
        provider_message_ref: str | None,
        provider_response: dict[str, Any],
        recipient_results: list[dict[str, Any]],
        completed_at: str | None = None,
    ) -> Any:
        return self.rpc(
            "finalize_communication_outbound_transport_service_v1",
            {
                "p_outbound_operation_id": operation_id,
                "p_lease_owner": self.settings.lease_owner,
                "p_result_state": result_state,
                "p_provider_message_ref": provider_message_ref,
                "p_provider_response": provider_response,
                "p_recipient_results": recipient_results,
                "p_transport_completed_at": completed_at or datetime.now(timezone.utc).isoformat(),
            },
        )


def recipient_rows(payload: dict[str, Any]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for role in ("to", "cc", "bcc"):
        for item in payload.get(role) or []:
            address = str(item.get("address") or "").strip()
            if address:
                rows.append({"role": role, "address": address, "name": str(item.get("name") or "").strip()})
    return rows


def display_address(item: dict[str, str]) -> str:
    return formataddr((item["name"], item["address"])) if item.get("name") else item["address"]


def build_message(
    payload: dict[str, Any],
    reply_context: dict[str, Any] | None,
    attachments: list[tuple[dict[str, Any], bytes]],
) -> tuple[EmailMessage, list[dict[str, str]], str]:
    message = EmailMessage(policy=SMTP)
    from_address = payload["fromAddress"]
    from_display = payload.get("fromDisplayName") or ""
    message["From"] = formataddr((from_display, from_address)) if from_display else from_address

    rows = recipient_rows(payload)
    to_rows = [row for row in rows if row["role"] == "to"]
    cc_rows = [row for row in rows if row["role"] == "cc"]
    if to_rows:
        message["To"] = ", ".join(display_address(row) for row in to_rows)
    if cc_rows:
        message["Cc"] = ", ".join(display_address(row) for row in cc_rows)

    message["Subject"] = payload.get("subject") or ""
    message["Date"] = formatdate(localtime=False, usegmt=True)
    domain = from_address.rsplit("@", 1)[-1] if "@" in from_address else None
    message_id = make_msgid(domain=domain)
    message["Message-ID"] = message_id

    context = reply_context or {}
    in_reply_to = context.get("messageId") or context.get("inReplyTo")
    if in_reply_to:
        message["In-Reply-To"] = str(in_reply_to)
    references = context.get("references") or []
    if isinstance(references, str):
        references = [references]
    refs = [str(value).strip() for value in references if str(value).strip()]
    if in_reply_to and str(in_reply_to) not in refs:
        refs.append(str(in_reply_to))
    if refs:
        message["References"] = " ".join(refs)

    body_text = payload.get("bodyText")
    body_html = payload.get("bodyHtml")
    if body_text is not None:
        message.set_content(str(body_text))
        if body_html is not None:
            message.add_alternative(str(body_html), subtype="html")
    elif body_html is not None:
        message.set_content(str(body_html), subtype="html")
    else:
        message.set_content("")

    for manifest, content in attachments:
        mime_type = manifest.get("mimeType") or mimetypes.guess_type(manifest.get("fileName") or "")[0] or "application/octet-stream"
        maintype, subtype = mime_type.split("/", 1) if "/" in mime_type else ("application", "octet-stream")
        message.add_attachment(
            content,
            maintype=maintype,
            subtype=subtype,
            filename=manifest.get("fileName") or "attachment",
        )

    return message, rows, message_id


def load_verified_attachments(client: AtlasClient, operation_id: str) -> list[tuple[dict[str, Any], bytes]]:
    result: list[tuple[dict[str, Any], bytes]] = []
    for item in client.attachment_manifest(operation_id):
        content = client.download_attachment(item["bucket"], item["path"])
        expected_length = item.get("byteLength")
        if expected_length is not None and len(content) != int(expected_length):
            raise AtlasTransportError(f"attachment byte length mismatch: {item.get('fileName') or item.get('attachmentId')}")
        expected_hash = str(item.get("sha256") or "").lower()
        actual_hash = hashlib.sha256(content).hexdigest()
        if expected_hash and actual_hash != expected_hash:
            raise AtlasTransportError(f"attachment hash mismatch: {item.get('fileName') or item.get('attachmentId')}")
        result.append((item, content))
    return result


def classify_code(code: int) -> str:
    if 400 <= code < 500:
        return "deferred"
    if code >= 500:
        return "rejected"
    return "unknown"


def response_detail(code: int, message: bytes | str) -> dict[str, Any]:
    text = message.decode("utf-8", errors="replace") if isinstance(message, bytes) else str(message)
    return {"smtpCode": int(code), "smtpMessage": text[:500]}


def smtp_session(config: dict[str, Any]):
    host = config.get("host")
    port = int(config.get("port") or 0)
    security = str(config.get("security") or "").lower()
    if not host or not port or security not in {"ssl", "tls", "starttls"}:
        raise AtlasContractError("SMTP config requires host, port, and security=ssl|tls|starttls")
    context = ssl.create_default_context()
    if security in {"ssl", "tls"}:
        return smtplib.SMTP_SSL(host, port, timeout=30, context=context)
    smtp = smtplib.SMTP(host, port, timeout=30)
    smtp.ehlo()
    smtp.starttls(context=context)
    smtp.ehlo()
    return smtp


def validate_leased_payload(payload: dict[str, Any], settings: RuntimeSettings) -> str:
    operation_id = str(payload.get("outboundOperationId") or "")
    if not operation_id:
        raise AtlasContractError("transport payload missing outboundOperationId")
    if payload.get("operationState") != "leased":
        raise AtlasContractError(f"operation {operation_id} is not leased")
    if payload.get("leaseOwner") != settings.lease_owner:
        raise AtlasContractError(f"operation {operation_id} lease owner mismatch")
    if str(payload.get("connectedSourceId")) != settings.connected_source_id:
        raise AtlasContractError(f"operation {operation_id} connected source mismatch")
    return operation_id


def send_operation(
    client: AtlasClient,
    payload: dict[str, Any],
    config: dict[str, Any],
    smtp_factory: Callable[[dict[str, Any]], Any] = smtp_session,
) -> str:
    settings = client.settings
    operation_id = validate_leased_payload(payload, settings)
    reply_context: dict[str, Any] = {}
    if payload.get("replyToCommunicationEventId"):
        reply_context = client.reply_context(payload["replyToCommunicationEventId"])

    try:
        attachments = load_verified_attachments(client, operation_id)
        message, recipients, message_id = build_message(payload, reply_context, attachments)
    except Exception as exc:
        client.finalize_transport(
            operation_id,
            "transport_error",
            None,
            {"phase": "pre_data", "exception": type(exc).__name__, "message": str(exc)[:500]},
            [],
        )
        return "transport_error"

    smtp = None
    data_started = False
    try:
        smtp_config = (config.get("mailConfig") or {}).get("smtp") or config.get("smtp") or {}
        username = (config.get("mailConfig") or {}).get("username") or config.get("username")
        password = (config.get("mailConfig") or {}).get("password") or config.get("password")
        smtp = smtp_factory(smtp_config)
        if username:
            smtp.login(username, password or "")

        code, detail = smtp.mail(payload["fromAddress"])
        if int(code) >= 400:
            raise AtlasTransportError(f"MAIL FROM rejected: {code} {detail!r}")

        unique: dict[str, dict[str, Any]] = {}
        for row in recipients:
            unique.setdefault(row["address"].lower(), row)
        rcpt_outcomes: dict[str, tuple[int, bytes | str]] = {}
        accepted_addresses: set[str] = set()
        for normalized, row in unique.items():
            code, detail = smtp.rcpt(row["address"])
            rcpt_outcomes[normalized] = (int(code), detail)
            if 200 <= int(code) < 300:
                accepted_addresses.add(normalized)

        recipient_results: list[dict[str, Any]] = []
        for row in recipients:
            code, detail = rcpt_outcomes[row["address"].lower()]
            state = "accepted" if 200 <= code < 300 else classify_code(code)
            recipient_results.append({
                "role": row["role"],
                "address": row["address"],
                "state": state,
                "providerResponse": response_detail(code, detail),
            })

        if not accepted_addresses:
            state = "temporary_failure" if any(row["state"] == "deferred" for row in recipient_results) else "rejected"
            client.finalize_transport(operation_id, state, None, {"phase": "rcpt", "smtp": "no recipients accepted"}, recipient_results)
            return state

        raw_message = message.as_bytes(policy=SMTP)
        raw_hash = hashlib.sha256(raw_message).hexdigest()
        data_started = True
        data_code, data_detail = smtp.data(raw_message)
        if 200 <= int(data_code) < 300:
            accepted_count = sum(1 for row in recipient_results if row["state"] == "accepted")
            result_state = "accepted" if accepted_count == len(recipient_results) else "partially_accepted"
            completed_at = datetime.now(timezone.utc).isoformat()
            client.finalize_transport(
                operation_id,
                result_state,
                message_id,
                {"phase": "data", "rawMimeSha256": raw_hash, **response_detail(int(data_code), data_detail)},
                recipient_results,
                completed_at,
            )
            return result_state

        state = "temporary_failure" if 400 <= int(data_code) < 500 else "rejected"
        recipient_state = "deferred" if state == "temporary_failure" else "rejected"
        for row in recipient_results:
            if row["state"] == "accepted":
                row["state"] = recipient_state
                row["providerResponse"] = response_detail(int(data_code), data_detail)
        client.finalize_transport(operation_id, state, None, {"phase": "data", **response_detail(int(data_code), data_detail)}, recipient_results)
        return state

    except Exception as exc:
        if data_started:
            print(f"Atlas outbound {operation_id}: transport_uncertain pending reconciliation ({type(exc).__name__}: {exc})", file=sys.stderr)
            return "transport_uncertain"
        client.finalize_transport(
            operation_id,
            "transport_error",
            None,
            {"phase": "pre_data", "exception": type(exc).__name__, "message": str(exc)[:500]},
            [],
        )
        return "transport_error"
    finally:
        if smtp is not None:
            try:
                smtp.quit()
            except Exception:
                pass


def run_once(client: AtlasClient, smtp_factory: Callable[[dict[str, Any]], Any] = smtp_session) -> list[tuple[str, str]]:
    client.mark_expired_uncertain()
    config = client.transport_config()
    results: list[tuple[str, str]] = []
    for lease in client.lease():
        operation_id = str(lease.get("outboundOperationId") or lease.get("id") or "")
        if not operation_id:
            continue
        payload = client.payload(operation_id)
        if payload.get("operationState") == "transport_uncertain":
            continue
        state = send_operation(client, payload, config, smtp_factory=smtp_factory)
        results.append((operation_id, state))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Atlas institutional email outbound runtime")
    parser.add_argument("--connected-source-id", default=None)
    args = parser.parse_args(argv)
    settings = RuntimeSettings.from_env(args.connected_source_id)
    if not settings.connected_source_id:
        parser.error("connected source id required via --connected-source-id or ATLAS_CONNECTED_SOURCE_ID")
    client = AtlasClient(settings)
    for operation_id, state in run_once(client):
        print(f"Atlas outbound {operation_id}: {state}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
