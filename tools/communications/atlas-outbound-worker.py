#!/usr/bin/env python3

import fcntl
import hashlib
import json
import mimetypes
import os
import smtplib
import ssl
import sys
import urllib.error
import urllib.request

from datetime import datetime, timezone
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import formataddr, formatdate, make_msgid
from pathlib import Path

HOME = Path.home()

RELAY_SECRET_FILE = HOME / ".atlas-outbound-secret"
MAILBOX_PASSWORD_FILE = HOME / ".atlas-mailbox-password"
LOCK_FILE = HOME / ".atlas-outbound-worker.lock"

RELAY_KEY = "elmfarm-hello-dreamhost-outbound-v1"
RELAY_URL = (
    "https://zirqkouammpwxlqfbsvf.supabase.co/"
    "functions/v1/atlas-outbound-email-relay"
)


def atlas_call(payload):
    secret = RELAY_SECRET_FILE.read_text().strip()

    request = urllib.request.Request(
        RELAY_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Atlas-Outbound-Relay-Key": RELAY_KEY,
            "X-Atlas-Outbound-Relay-Secret": secret,
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Atlas relay HTTP {exc.code}: {body[:1200]}"
        ) from exc

    result = json.loads(raw)

    if not result.get("ok"):
        raise RuntimeError(
            f"Atlas relay rejected request: {raw[:1200]}"
        )

    return result


def recipients(job):
    rows = []

    for role, key in (
        ("to", "to"),
        ("cc", "cc"),
        ("bcc", "bcc"),
    ):
        for item in job.get(key) or []:
            address = (item.get("address") or "").strip()
            if address:
                rows.append({
                    "role": role,
                    "address": address,
                    "name": (item.get("name") or "").strip(),
                })

    return rows


def display_address(item):
    if item.get("name"):
        return formataddr((item["name"], item["address"]))
    return item["address"]


def fetch_attachment(item):
    url = item.get("downloadUrl")
    if not url:
        raise RuntimeError(
            f"Attachment {item.get('attachmentId')} has no signed URL"
        )

    with urllib.request.urlopen(url, timeout=60) as response:
        content = response.read()

    expected_hash = (item.get("sha256") or "").lower()
    actual_hash = hashlib.sha256(content).hexdigest()

    if expected_hash and actual_hash != expected_hash:
        raise RuntimeError(
            f"Attachment hash mismatch for {item.get('fileName')}"
        )

    expected_length = item.get("byteLength")
    if expected_length is not None and len(content) != int(expected_length):
        raise RuntimeError(
            f"Attachment byte length mismatch for {item.get('fileName')}"
        )

    return content


def build_message(job, from_address, from_display):
    msg = EmailMessage(policy=SMTP)

    if from_display:
        msg["From"] = formataddr((from_display, from_address))
    else:
        msg["From"] = from_address

    rows = recipients(job)
    to_rows = [r for r in rows if r["role"] == "to"]
    cc_rows = [r for r in rows if r["role"] == "cc"]

    if to_rows:
        msg["To"] = ", ".join(display_address(r) for r in to_rows)
    if cc_rows:
        msg["Cc"] = ", ".join(display_address(r) for r in cc_rows)

    msg["Subject"] = job.get("subject") or ""
    msg["Date"] = formatdate(localtime=False, usegmt=True)

    domain = (
        from_address.split("@", 1)[1]
        if "@" in from_address
        else "localhost"
    )
    message_id = make_msgid(domain=domain)
    msg["Message-ID"] = message_id

    reply_id = job.get("replyMessageId")
    if reply_id:
        msg["In-Reply-To"] = reply_id

    refs = [
        str(value).strip()
        for value in (job.get("replyReferences") or [])
        if str(value).strip()
    ]
    if refs:
        msg["References"] = " ".join(refs)

    body_text = job.get("bodyText")
    body_html = job.get("bodyHtml")

    if body_text is not None:
        msg.set_content(body_text)
        if body_html is not None:
            msg.add_alternative(body_html, subtype="html")
    elif body_html is not None:
        msg.set_content(body_html, subtype="html")
    else:
        msg.set_content("")

    for item in job.get("attachments") or []:
        content = fetch_attachment(item)
        mime_type = (
            item.get("mimeType")
            or mimetypes.guess_type(item.get("fileName") or "")[0]
            or "application/octet-stream"
        )
        maintype, subtype = (
            mime_type.split("/", 1)
            if "/" in mime_type
            else ("application", "octet-stream")
        )
        msg.add_attachment(
            content,
            maintype=maintype,
            subtype=subtype,
            filename=item.get("fileName") or "attachment",
        )

    return msg, rows, message_id


def classify_refusal(value):
    code, message = value
    try:
        code = int(code)
    except Exception:
        code = 0

    if isinstance(message, bytes):
        message = message.decode("utf-8", errors="replace")
    else:
        message = str(message)

    if 400 <= code < 500:
        state = "deferred"
    elif code >= 500:
        state = "rejected"
    else:
        state = "unknown"

    return state, {
        "smtpCode": code,
        "smtpMessage": message[:500],
    }


def report_result(payload):
    return atlas_call({"action": "result", **payload})


def send_job(job, lease_owner, smtp_config, username):
    operation_id = job["outboundOperationId"]
    host = smtp_config.get("host") or "smtp.dreamhost.com"
    port = int(smtp_config.get("port") or 587)
    password = MAILBOX_PASSWORD_FILE.read_text()
    from_address = job["fromAddress"]
    from_display = job.get("fromDisplayName")

    msg, recipient_rows, message_id = build_message(
        job,
        from_address,
        from_display,
    )
    raw_message = msg.as_bytes(policy=SMTP)
    raw_hash = hashlib.sha256(raw_message).hexdigest()

    unique_addresses = []
    seen = set()
    for row in recipient_rows:
        normalized = row["address"].lower()
        if normalized not in seen:
            seen.add(normalized)
            unique_addresses.append(row["address"])

    smtp = None
    data_attempted = False

    try:
        smtp = smtplib.SMTP(host, port, timeout=30)
        smtp.ehlo()
        smtp.starttls(context=ssl.create_default_context())
        smtp.ehlo()
        smtp.login(username, password)
        data_attempted = True

        refused = smtp.sendmail(
            from_address,
            unique_addresses,
            raw_message,
        )

        result_rows = []
        for row in recipient_rows:
            refusal = refused.get(row["address"])
            if refusal is None:
                result_rows.append({
                    "role": row["role"],
                    "address": row["address"],
                    "state": "accepted",
                    "providerResponse": {},
                })
            else:
                state, detail = classify_refusal(refusal)
                result_rows.append({
                    "role": row["role"],
                    "address": row["address"],
                    "state": state,
                    "providerResponse": detail,
                })

        accepted = sum(
            1 for row in result_rows if row["state"] == "accepted"
        )

        if accepted == len(result_rows):
            result_state = "accepted"
        elif accepted:
            result_state = "partially_accepted"
        elif any(row["state"] == "deferred" for row in result_rows):
            result_state = "temporary_failure"
        else:
            result_state = "rejected"

        sent_at = datetime.now(timezone.utc).isoformat()

        response = report_result({
            "outboundOperationId": operation_id,
            "leaseOwner": lease_owner,
            "resultState": result_state,
            "providerMessageRef": message_id,
            "messageId": message_id,
            "sentAt": sent_at,
            "rawMimeSha256": raw_hash,
            "recipientResults": result_rows,
            "providerResponse": {
                "smtpHost": host,
                "smtpPort": port,
                "transportResult": result_state,
            },
        })

        print(
            f"Atlas outbound {operation_id}: "
            f"{response.get('result', {}).get('operationState', result_state)}"
        )

    except smtplib.SMTPRecipientsRefused as exc:
        result_rows = []
        for row in recipient_rows:
            refusal = exc.recipients.get(row["address"])
            if refusal:
                state, detail = classify_refusal(refusal)
            else:
                state, detail = "unknown", {}
            result_rows.append({
                "role": row["role"],
                "address": row["address"],
                "state": state,
                "providerResponse": detail,
            })

        state = (
            "temporary_failure"
            if any(r["state"] == "deferred" for r in result_rows)
            else "rejected"
        )

        report_result({
            "outboundOperationId": operation_id,
            "leaseOwner": lease_owner,
            "resultState": state,
            "providerMessageRef": None,
            "recipientResults": result_rows,
            "providerResponse": {
                "smtpHost": host,
                "exception": "SMTPRecipientsRefused",
            },
        })
        print(f"Atlas outbound {operation_id}: {state}")

    except smtplib.SMTPDataError as exc:
        state = (
            "temporary_failure"
            if 400 <= int(exc.smtp_code) < 500
            else "rejected"
        )
        recipient_state = (
            "deferred" if state == "temporary_failure" else "rejected"
        )
        result_rows = [{
            "role": row["role"],
            "address": row["address"],
            "state": recipient_state,
            "providerResponse": {
                "smtpCode": int(exc.smtp_code),
                "smtpMessage": (
                    exc.smtp_error.decode("utf-8", errors="replace")
                    if isinstance(exc.smtp_error, bytes)
                    else str(exc.smtp_error)
                )[:500],
            },
        } for row in recipient_rows]

        report_result({
            "outboundOperationId": operation_id,
            "leaseOwner": lease_owner,
            "resultState": state,
            "providerMessageRef": None,
            "recipientResults": result_rows,
            "providerResponse": {
                "smtpHost": host,
                "exception": "SMTPDataError",
            },
        })
        print(f"Atlas outbound {operation_id}: {state}")

    except Exception as exc:
        if data_attempted:
            print(
                f"Atlas outbound {operation_id}: TRANSPORT UNCERTAIN — "
                f"{type(exc).__name__}: {exc}",
                file=sys.stderr,
            )
            return

        report_result({
            "outboundOperationId": operation_id,
            "leaseOwner": lease_owner,
            "resultState": "transport_error",
            "providerMessageRef": None,
            "recipientResults": [],
            "providerResponse": {
                "smtpHost": host,
                "exception": type(exc).__name__,
                "message": str(exc)[:500],
            },
        })
        print(
            f"Atlas outbound {operation_id}: transport_error",
            file=sys.stderr,
        )

    finally:
        if smtp is not None:
            try:
                smtp.quit()
            except Exception:
                pass


def main():
    LOCK_FILE.touch(mode=0o600, exist_ok=True)

    with LOCK_FILE.open("r+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0

        lease = atlas_call({
            "action": "lease",
            "limit": 10,
        })

        jobs = lease.get("jobs") or []

        print("Outbound relay authentication: OK")
        print(
            "Outbound endpoint:",
            lease.get("endpointAddress") or "unknown",
        )
        print("Jobs leased:", len(jobs))

        smtp_config = lease.get("smtp") or {}
        username = lease.get("username") or lease.get("endpointAddress")
        lease_owner = lease["leaseOwner"]

        for job in jobs:
            send_job(job, lease_owner, smtp_config, username)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Atlas outbound worker error: {exc}", file=sys.stderr)
        raise SystemExit(1)
