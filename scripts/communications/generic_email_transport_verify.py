#!/usr/bin/env python3
"""Verify a generic Atlas institutional mailbox without reading or sending mail.

The verifier authenticates to IMAP and SMTP only. It never selects a mailbox, lists,
searches, fetches, or changes messages, and it never issues SMTP MAIL/RCPT/DATA.
Verification evidence is reported to Atlas; activation remains a separate owner action.
"""

from __future__ import annotations

import argparse
import imaplib
import json
import os
import smtplib
import ssl
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable


class AtlasVerificationError(RuntimeError):
    """Configuration, Atlas-contract, or authentication verification failure."""


@dataclass(frozen=True)
class RuntimeSettings:
    supabase_url: str
    service_role_key: str
    connected_source_id: str

    @classmethod
    def from_env(cls, connected_source_id: str | None = None) -> "RuntimeSettings":
        source_id = connected_source_id or os.environ.get("ATLAS_CONNECTED_SOURCE_ID", "")
        if not source_id:
            raise AtlasVerificationError("ATLAS_CONNECTED_SOURCE_ID or --connected-source-id is required")
        return cls(
            supabase_url=os.environ["SUPABASE_URL"].rstrip("/"),
            service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            connected_source_id=source_id,
        )


class AtlasClient:
    def __init__(self, settings: RuntimeSettings, opener: Callable[..., Any] = urllib.request.urlopen):
        self.settings = settings
        self._opener = opener

    def rpc(self, function_name: str, payload: dict[str, Any]) -> Any:
        request = urllib.request.Request(
            f"{self.settings.supabase_url}/rest/v1/rpc/{function_name}",
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={
                "apikey": self.settings.service_role_key,
                "Authorization": f"Bearer {self.settings.service_role_key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with self._opener(request, timeout=45) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise AtlasVerificationError(f"Atlas HTTP {exc.code}: {body[:1000]}") from exc
        return json.loads(raw.decode("utf-8")) if raw else None

    def transport_config(self) -> dict[str, Any]:
        return self.rpc(
            "generic_email_transport_config_service_v1",
            {"p_connected_source_id": self.settings.connected_source_id},
        ) or {}

    def record_verification(self, imap_ok: bool, smtp_ok: bool, details: dict[str, Any]) -> dict[str, Any]:
        return self.rpc(
            "record_generic_email_transport_verification_service_v1",
            {
                "p_connected_source_id": self.settings.connected_source_id,
                "p_imap_ok": imap_ok,
                "p_smtp_ok": smtp_ok,
                "p_details": details,
            },
        ) or {}


def _mail_config(config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], str, str]:
    mail = config.get("mailConfig") or {}
    imap = mail.get("imap") or {}
    smtp = mail.get("smtp") or {}
    username = str(mail.get("username") or "").strip()
    password = str(mail.get("password") or "")
    if not username or not password:
        raise AtlasVerificationError("Atlas generic email credentials are incomplete")
    return imap, smtp, username, password


def verify_imap_auth(
    imap_config: dict[str, Any],
    username: str,
    password: str,
    *,
    ssl_factory: Callable[..., Any] = imaplib.IMAP4_SSL,
    plain_factory: Callable[..., Any] = imaplib.IMAP4,
) -> dict[str, Any]:
    host = str(imap_config.get("host") or "").strip()
    port = int(imap_config.get("port") or 0)
    security = str(imap_config.get("security") or "").strip().lower()
    if not host or not port or security not in {"ssl", "tls", "starttls"}:
        raise AtlasVerificationError("IMAP config requires host, port, and security=ssl|tls|starttls")

    context = ssl.create_default_context()
    client = None
    try:
        if security in {"ssl", "tls"}:
            client = ssl_factory(host, port, ssl_context=context)
        else:
            client = plain_factory(host, port)
            status, _ = client.starttls(ssl_context=context)
            if status != "OK":
                raise AtlasVerificationError("IMAP STARTTLS failed")
        status, _ = client.login(username, password)
        if status != "OK":
            raise AtlasVerificationError("IMAP authentication failed")
        return {"ok": True, "host": host, "port": port, "security": security, "phase": "authenticated"}
    finally:
        if client is not None:
            try:
                client.logout()
            except Exception:
                pass


def verify_smtp_auth(
    smtp_config: dict[str, Any],
    username: str,
    password: str,
    *,
    ssl_factory: Callable[..., Any] = smtplib.SMTP_SSL,
    plain_factory: Callable[..., Any] = smtplib.SMTP,
) -> dict[str, Any]:
    host = str(smtp_config.get("host") or "").strip()
    port = int(smtp_config.get("port") or 0)
    security = str(smtp_config.get("security") or "").strip().lower()
    if not host or not port or security not in {"ssl", "tls", "starttls"}:
        raise AtlasVerificationError("SMTP config requires host, port, and security=ssl|tls|starttls")

    context = ssl.create_default_context()
    client = None
    try:
        if security in {"ssl", "tls"}:
            client = ssl_factory(host, port, timeout=30, context=context)
        else:
            client = plain_factory(host, port, timeout=30)
            client.ehlo()
            client.starttls(context=context)
            client.ehlo()
        client.login(username, password)
        return {"ok": True, "host": host, "port": port, "security": security, "phase": "authenticated"}
    finally:
        if client is not None:
            try:
                client.quit()
            except Exception:
                try:
                    client.close()
                except Exception:
                    pass


def _failure_detail(kind: str, config: dict[str, Any], exc: Exception) -> dict[str, Any]:
    return {
        "ok": False,
        "host": str(config.get("host") or "").strip() or None,
        "port": int(config.get("port") or 0) or None,
        "security": str(config.get("security") or "").strip().lower() or None,
        "phase": "authentication",
        "errorType": type(exc).__name__,
        "transport": kind,
    }


def run_once(
    settings: RuntimeSettings,
    *,
    atlas_client: AtlasClient | None = None,
    imap_verifier: Callable[[dict[str, Any], str, str], dict[str, Any]] = verify_imap_auth,
    smtp_verifier: Callable[[dict[str, Any], str, str], dict[str, Any]] = verify_smtp_auth,
) -> dict[str, Any]:
    atlas = atlas_client or AtlasClient(settings)
    config = atlas.transport_config()
    imap_config, smtp_config, username, password = _mail_config(config)

    imap_ok = False
    smtp_ok = False
    try:
        try:
            imap_detail = imap_verifier(imap_config, username, password)
            imap_ok = True
        except Exception as exc:
            imap_detail = _failure_detail("imap", imap_config, exc)

        try:
            smtp_detail = smtp_verifier(smtp_config, username, password)
            smtp_ok = True
        except Exception as exc:
            smtp_detail = _failure_detail("smtp", smtp_config, exc)

        details = {
            "contractVersion": "generic_email_transport_verifier_v1",
            "mode": "authentication_only",
            "imap": imap_detail,
            "smtp": smtp_detail,
        }
        receipt = atlas.record_verification(imap_ok, smtp_ok, details)
        return {
            "contractVersion": "generic_email_transport_verifier_v1",
            "connectedSourceId": settings.connected_source_id,
            "verified": imap_ok and smtp_ok,
            "imapOk": imap_ok,
            "smtpOk": smtp_ok,
            "receipt": receipt,
        }
    finally:
        password = ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connected-source-id")
    args = parser.parse_args(argv)
    settings = RuntimeSettings.from_env(args.connected_source_id)
    print(json.dumps(run_once(settings), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
