#!/usr/bin/env python3
"""Provider-neutral Atlas institutional email inbound runtime.

The runtime has mailbox transport authority only. It reads physical RFC/MIME evidence
from a configured generic IMAP source and submits those facts to Atlas. Atlas owns
canonical Communication Event construction, deduplication, threading/admission,
relationship reconciliation, and response-state consequences.
"""

from __future__ import annotations

import argparse
import email
import hashlib
import imaplib
import json
import os
import re
import ssl
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from email.header import decode_header, make_header
from email.message import Message
from email.policy import default
from email.utils import getaddresses, parsedate_to_datetime
from typing import Any, Callable, Iterable


class AtlasInboundError(RuntimeError):
    """Inbound transport or Atlas-contract failure."""


@dataclass(frozen=True)
class RuntimeSettings:
    supabase_url: str
    service_role_key: str
    connected_source_id: str
    mailbox: str = "INBOX"
    limit: int = 100

    @classmethod
    def from_env(cls, connected_source_id: str | None = None) -> "RuntimeSettings":
        source_id = connected_source_id or os.environ.get("ATLAS_CONNECTED_SOURCE_ID", "")
        if not source_id:
            raise AtlasInboundError("ATLAS_CONNECTED_SOURCE_ID or --connected-source-id is required")
        return cls(
            supabase_url=os.environ["SUPABASE_URL"].rstrip("/"),
            service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            connected_source_id=source_id,
            mailbox=os.environ.get("ATLAS_EMAIL_MAILBOX", "INBOX"),
            limit=int(os.environ.get("ATLAS_EMAIL_INBOUND_LIMIT", "100")),
        )


class AtlasClient:
    def __init__(self, settings: RuntimeSettings, opener: Callable[..., Any] = urllib.request.urlopen):
        self.settings = settings
        self._opener = opener

    def rpc(self, function_name: str, payload: dict[str, Any]) -> Any:
        url = f"{self.settings.supabase_url}/rest/v1/rpc/{function_name}"
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={
                "apikey": self.settings.service_role_key,
                "Authorization": f"Bearer {self.settings.service_role_key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with self._opener(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise AtlasInboundError(f"Atlas HTTP {exc.code}: {body[:1500]}") from exc
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))

    def transport_config(self) -> dict[str, Any]:
        return self.rpc(
            "generic_email_transport_config_service_v1",
            {"p_connected_source_id": self.settings.connected_source_id},
        ) or {}

    def capture_cursor(self, mailbox: str) -> dict[str, Any]:
        return self.rpc(
            "institutional_email_capture_cursor_service_v1",
            {"p_connected_source_id": self.settings.connected_source_id, "p_mailbox": mailbox},
        ) or {}

    def ingest_message(self, facts: dict[str, Any]) -> dict[str, Any]:
        payload = {"p_connected_source_id": self.settings.connected_source_id, **facts}
        return self.rpc("ingest_institutional_email_transport_service_v1", payload) or {}

    def record_cursor(self, mailbox: str, uid_validity: int, uid: int) -> dict[str, Any]:
        return self.rpc(
            "record_institutional_email_capture_cursor_service_v1",
            {
                "p_connected_source_id": self.settings.connected_source_id,
                "p_mailbox": mailbox,
                "p_uid_validity": uid_validity,
                "p_last_uid": uid,
            },
        ) or {}


def _decode_header(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        return str(make_header(decode_header(value))).strip() or None
    except Exception:
        return value.strip() or None


def _addresses(values: Iterable[str | None]) -> list[dict[str, str]]:
    decoded = [_decode_header(value) or "" for value in values if value]
    rows: list[dict[str, str]] = []
    for name, address in getaddresses(decoded):
        address = address.strip()
        if not address:
            continue
        row = {"address": address}
        decoded_name = _decode_header(name)
        if decoded_name:
            row["name"] = decoded_name
        rows.append(row)
    return rows


def _message_ids(value: str | None) -> list[str]:
    if not value:
        return []
    bracketed = re.findall(r"<[^<>\s]+>", value)
    if bracketed:
        return bracketed
    return [token for token in value.split() if token]


def _decoded_payload(part: Message) -> bytes:
    payload = part.get_payload(decode=True)
    if payload is not None:
        return payload
    text = part.get_payload()
    if isinstance(text, str):
        charset = part.get_content_charset() or "utf-8"
        return text.encode(charset, errors="replace")
    return b""


def _decoded_text(part: Message) -> str:
    data = _decoded_payload(part)
    charset = part.get_content_charset() or "utf-8"
    try:
        return data.decode(charset, errors="replace")
    except LookupError:
        return data.decode("utf-8", errors="replace")


def parse_rfc822(raw: bytes, *, mailbox: str, uid_validity: int, uid: int) -> dict[str, Any]:
    message = email.message_from_bytes(raw, policy=default)
    text_parts: list[str] = []
    html_parts: list[str] = []
    attachments: list[dict[str, Any]] = []
    part_index = 0

    for part in message.walk():
        if part.is_multipart():
            continue
        part_index += 1
        content_disposition = (part.get_content_disposition() or "").lower()
        filename = _decode_header(part.get_filename())
        content_type = part.get_content_type().lower()
        payload = _decoded_payload(part)

        if content_disposition == "attachment" or filename:
            item: dict[str, Any] = {
                "sourceAttachmentRef": f"imap:{uid_validity}:{uid}:part:{part_index}",
                "mimeType": content_type,
                "sourceContentHash": hashlib.sha256(payload).hexdigest(),
                "metadata": {"byteLength": len(payload), "partIndex": part_index},
            }
            if filename:
                item["transferName"] = filename
            content_id = (part.get("Content-ID") or "").strip()
            if content_id:
                item["metadata"]["contentId"] = content_id
            attachments.append(item)
            continue

        if content_type == "text/plain":
            text_parts.append(_decoded_text(part))
        elif content_type == "text/html":
            html_parts.append(_decoded_text(part))

    body_text = "\n".join(piece for piece in text_parts if piece).strip() or None
    body_html = "\n".join(piece for piece in html_parts if piece).strip() or None

    occurred_at: str | None = None
    if message.get("Date"):
        try:
            parsed = parsedate_to_datetime(message.get("Date"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            occurred_at = parsed.astimezone(timezone.utc).isoformat()
        except (TypeError, ValueError, OverflowError):
            occurred_at = None

    from_rows = _addresses(message.get_all("From", []))
    if len(from_rows) > 1:
        raise AtlasInboundError("Inbound RFC message has more than one From address")

    references: list[str] = []
    for header in message.get_all("References", []):
        references.extend(_message_ids(header))

    return {
        "p_mailbox": mailbox,
        "p_uid_validity": uid_validity,
        "p_uid": uid,
        "p_message_id": (message.get("Message-ID") or "").strip() or None,
        "p_in_reply_to": (message.get("In-Reply-To") or "").strip() or None,
        "p_references": references,
        "p_from": from_rows[0] if from_rows else {},
        "p_to": _addresses(message.get_all("To", [])),
        "p_cc": _addresses(message.get_all("Cc", [])),
        "p_bcc": _addresses(message.get_all("Bcc", [])),
        "p_subject": _decode_header(message.get("Subject")),
        "p_occurred_at": occurred_at,
        "p_body_text": body_text,
        "p_body_html": body_html,
        "p_attachments": attachments,
        "p_raw_mime_sha256": hashlib.sha256(raw).hexdigest(),
        "p_raw_byte_length": len(raw),
        "p_captured_at": datetime.now(timezone.utc).isoformat(),
    }


def _imap_security(config: dict[str, Any]) -> tuple[str, int, str]:
    mail_config = config.get("mailConfig") or {}
    imap = mail_config.get("imap") or {}
    host = str(imap.get("host") or "").strip()
    port = int(imap.get("port") or 0)
    security = str(imap.get("security") or "").strip().lower()
    if not host or not port or security not in {"ssl", "tls", "starttls"}:
        raise AtlasInboundError("Atlas generic email IMAP configuration is incomplete")
    return host, port, security


def open_imap(config: dict[str, Any]) -> imaplib.IMAP4:
    host, port, security = _imap_security(config)
    mail_config = config.get("mailConfig") or {}
    username = str(mail_config.get("username") or "")
    password = str(mail_config.get("password") or "")
    if not username or not password:
        raise AtlasInboundError("Atlas generic email IMAP credentials are incomplete")

    context = ssl.create_default_context()
    if security in {"ssl", "tls"}:
        client: imaplib.IMAP4 = imaplib.IMAP4_SSL(host, port, ssl_context=context)
    else:
        client = imaplib.IMAP4(host, port)
        status, _ = client.starttls(ssl_context=context)
        if status != "OK":
            raise AtlasInboundError("IMAP STARTTLS failed")
    status, _ = client.login(username, password)
    if status != "OK":
        raise AtlasInboundError("IMAP authentication failed")
    return client


def _uid_validity(client: imaplib.IMAP4) -> int:
    response = client.response("UIDVALIDITY")
    if not response or not response[1]:
        raise AtlasInboundError("IMAP server did not report UIDVALIDITY")
    raw = response[1][0]
    if isinstance(raw, bytes):
        raw = raw.decode("ascii", errors="strict")
    return int(str(raw))


def _uid_search(client: imaplib.IMAP4, start_uid: int, limit: int) -> list[int]:
    status, data = client.uid("SEARCH", None, f"UID {max(start_uid, 1)}:*")
    if status != "OK":
        raise AtlasInboundError("IMAP UID SEARCH failed")
    raw = (data[0] or b"") if data else b""
    uids = [int(value) for value in raw.split() if value]
    return uids[:limit]


def _uid_fetch(client: imaplib.IMAP4, uid: int) -> bytes:
    status, data = client.uid("FETCH", str(uid), "(BODY.PEEK[])")
    if status != "OK":
        raise AtlasInboundError(f"IMAP UID FETCH failed for UID {uid}")
    for item in data or []:
        if isinstance(item, tuple) and len(item) >= 2 and isinstance(item[1], bytes):
            return item[1]
    raise AtlasInboundError(f"IMAP UID FETCH returned no RFC822 bytes for UID {uid}")


def run_once(settings: RuntimeSettings, *, atlas_client: AtlasClient | None = None) -> dict[str, Any]:
    atlas = atlas_client or AtlasClient(settings)
    config = atlas.transport_config()
    cursor = atlas.capture_cursor(settings.mailbox)
    processed: list[dict[str, Any]] = []

    client = open_imap(config)
    try:
        status, _ = client.select(settings.mailbox, readonly=True)
        if status != "OK":
            raise AtlasInboundError(f"Unable to select IMAP mailbox {settings.mailbox!r}")
        uid_validity = _uid_validity(client)
        previous_validity = cursor.get("uidValidity")
        previous_uid = int(cursor.get("lastUid") or 0)
        start_uid = previous_uid + 1 if previous_validity == uid_validity else 1

        for uid in _uid_search(client, start_uid, settings.limit):
            raw = _uid_fetch(client, uid)
            facts = parse_rfc822(raw, mailbox=settings.mailbox, uid_validity=uid_validity, uid=uid)
            receipt = atlas.ingest_message(facts)
            atlas.record_cursor(settings.mailbox, uid_validity, uid)
            processed.append({"uid": uid, "receipt": receipt})
    finally:
        try:
            client.logout()
        except Exception:
            pass

    return {
        "contractVersion": "institutional_email_inbound_runtime_v1",
        "connectedSourceId": settings.connected_source_id,
        "mailbox": settings.mailbox,
        "processedCount": len(processed),
        "processed": processed,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connected-source-id")
    parser.add_argument("--mailbox")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args(argv)

    settings = RuntimeSettings.from_env(args.connected_source_id)
    if args.mailbox:
        settings = RuntimeSettings(**{**settings.__dict__, "mailbox": args.mailbox})
    if args.limit is not None:
        settings = RuntimeSettings(**{**settings.__dict__, "limit": args.limit})
    if settings.limit < 1 or settings.limit > 1000:
        raise AtlasInboundError("Inbound limit must be between 1 and 1000")

    print(json.dumps(run_once(settings), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
