"""HELD U2 signed governor call-stack evidence on an existing disposable DB.

Observe the local PostgreSQL container's already-produced server error context.
No SQL function, grant, GUC, Docker container, or database is created or
modified. Raw logs, function identities, error text and JWTs stay in memory;
only fixed enums are returned. If context is unavailable, fail closed.
"""
from datetime import datetime, timezone
import base64
import re
import subprocess
from urllib.parse import urlsplit

_STAGES = {
    "atlas.finalize_accepted_governed_prework_self_api_v1": "u2b_finalizer",
    "atlas.governor_approve_rhythm_opportunity_self_api_v1": "r02_adapter",
    "atlas.owner_establish_standing_continuing_care_work_self_api_v1": "r01_writer",
    "atlas.establish_continuing_original_work_internal_v1": "canonical_original",
    "atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1": "native_allocation",
    "atlas.company_work_native_ledger_owner_self_v1": "native_governor",
    "atlas.require_accepted_prework_standing_original_v1": "accepted_first_guard",
}
_UNOBSERVED = ("unobservable", "unverified")
_FRAMES = frozenset(("raise_frame_match", "call_path_match",
                     "different_origin", "unobservable"))


def local_probe_started():
    """UTC instant for Docker's local-only --since, called before the real RPC."""
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _matching_private_function(db_url, message, local_sql):
    if not isinstance(message, str) or not 0 < len(message) <= 512:
        return None
    if any(ord(ch) < 32 for ch in message):
        return None
    encoded = base64.b64encode(message.encode("utf-8")).decode("ascii")
    # The private function name is returned ONLY to this process in a
    # disposable clone; this function never logs or exposes it.
    statement = """
SELECT CASE WHEN count(*)=1 THEN min(n.nspname||'.'||p.proname)
 ELSE 'not_unique' END
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_language l ON l.oid=p.prolang
WHERE n.nspname IN ('atlas','public','ledger','reality','auth')
  AND p.prokind='f' AND l.lanname IN ('plpgsql','sql')
  AND pg_catalog.strpos(
      p.prosrc,pg_catalog.quote_literal(
        pg_catalog.convert_from(
          pg_catalog.decode('%s','base64'),'UTF8'))) > 0;
""" % encoded
    try:
        name = local_sql(db_url, statement)
    except Exception:
        return None
    if isinstance(name, str) and re.fullmatch(
        r"[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*", name, re.ASCII
    ):
        return name
    return None


def _local_db_port(db_url):
    try:
        parsed = urlsplit(db_url)
        if (parsed.scheme not in ("postgres", "postgresql")
                or parsed.hostname != "127.0.0.1"
                or parsed.path != "/postgres"):
            return None
        if parsed.port is None or not 1024 <= parsed.port <= 65535:
            return None
        return parsed.port
    except (TypeError, ValueError):
        return None


def _run(command, runner):
    try:
        result = runner(command, capture_output=True, text=True, timeout=8,
                        check=False)
        if result.returncode != 0:
            return None
        output = result.stdout + result.stderr
        if len(output) > 2_000_000:
            return None
        return output
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def _database_container_id(port, runner):
    rows = _run(["docker", "ps", "--format", "{{.ID}}|{{.Ports}}"], runner)
    if rows is None:
        return None
    matches = []
    for line in rows.splitlines():
        parts = line.split("|", 1)
        if len(parts) != 2 or not re.fullmatch(r"[a-f0-9]{12,64}", parts[0]):
            continue
        if re.search(r"(?<!\d)" + str(port) + r"->5432/tcp", parts[1]):
            matches.append(parts[0])
    return matches[0] if len(matches) == 1 else None


def _stack_evidence(log_text, exact_message, private_name):
    """Read only the error block belonging to the exact signed RPC refusal."""
    lines = log_text.splitlines()
    blocks = []
    for i, line in enumerate(lines):
        match = re.search(r"\bERROR:\s*(.*)$", line)
        if match is None or match.group(1).strip() != exact_message:
            continue
        frames = []
        for next_line in lines[i+1:i+22]:
            if re.search(r"\b(?:ERROR|LOG|FATAL):\s", next_line):
                break
            for frame in re.finditer(
                r"(?i)PL/pgSQL function ([a-z][a-z0-9_]*\.[a-z][a-z0-9_]*)\(",
                next_line
            ):
                frames.append((frame.group(1).lower(), "at RAISE" in next_line))
        blocks.append(frames)
    # Without one specific matching ERROR block there is no defensible
    # attribution to the signed governor request (including zero/duplicates).
    if len(blocks) != 1 or not blocks[0]:
        return _UNOBSERVED
    frames = blocks[0]
    if frames[0] == (private_name, True):
        return ("raise_frame_match", _STAGES.get(private_name, "inherited_or_other"))
    if any(name == private_name for name, _ in frames):
        return ("call_path_match", _STAGES.get(private_name, "inherited_or_other"))
    return ("different_origin", "unverified")


def inspect_signed_denial_stack(db_url, exact_message, since_utc,
                                local_sql, runner=subprocess.run):
    """Finite tuple ONLY. No private function name or container log leaves here."""
    if (not isinstance(since_utc, str) or
        not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{6})?Z", since_utc)):
        return _UNOBSERVED
    port = _local_db_port(db_url)
    if port is None:
        return _UNOBSERVED
    private_name = _matching_private_function(db_url, exact_message, local_sql)
    if private_name is None:
        return _UNOBSERVED
    container_id = _database_container_id(port, runner)
    if container_id is None:
        return _UNOBSERVED
    logs = _run(["docker", "logs", "--timestamps", "--since", since_utc,
                 "--tail", "400", container_id], runner)
    if logs is None:
        return _UNOBSERVED
    evidence = _stack_evidence(logs, exact_message, private_name)
    if (evidence[0] not in _FRAMES or
        evidence[1] not in frozenset(_STAGES.values()) |
            frozenset(("unverified", "inherited_or_other"))):
        return _UNOBSERVED
    return evidence
