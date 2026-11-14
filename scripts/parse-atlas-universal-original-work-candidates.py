#!/usr/bin/env python3
"""Run the PostgreSQL SQL and PL/pgSQL grammar parsers on every held candidate.

No schema changes, network access, production credentials or migration apply.
Grammar parsing is NOT table/column/function resolution or a signed acceptance.
"""
from pathlib import Path
import re
from pglast import parse_plpgsql, parse_sql

root = Path(__file__).resolve().parents[1] / "candidates" / "atlas"
paths = sorted(root.glob("*/candidate.sql"))
paths += sorted(root.glob("*/guarded_native_reader_extensions.sql"))
paths += sorted(root.glob("*/postconditions.sql"))
if len(paths) < 15:
    raise SystemExit(f"Missing original SQL candidate sources (found {len(paths)})")

functions = 0
for path in paths:
    sql = path.read_text()
    try:
        statements = parse_sql(sql)
    except Exception as e:
        raise SystemExit(f"PostgreSQL SQL syntax error in {path.relative_to(root)}: {e}")
    if not statements:
        raise SystemExit(f"Zero SQL statements in {path.relative_to(root)}")
    # This uses the real PL/pgSQL parser, rather than just counting paired
    # dollar quotes (whose content the outer SQL parser regards as a literal).
    fn = re.finditer(
        r"CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+"
        r"(?:atlas|public)\.[a-z_0-9]+\s*\("
        r"[\s\S]*?\$function\$[\s\S]*?\$function\$;",
        sql, re.IGNORECASE
    )
    parsed = 0
    for match in fn:
        function_sql = match.group(0)
        if not re.search(r"\bLANGUAGE\s+plpgsql\b", function_sql, re.IGNORECASE):
            continue
        try:
            parse_plpgsql(function_sql)
        except Exception as e:
            # pglast's isolated PL/pgSQL grammar lacks a catalog that knows
            # Atlas/Noel schemas. This *specific* namespace-resolution
            # limitation is not a PostgreSQL syntax error. Normalize only
            # known schema qualifiers for a second syntax-only parse.
            # The unmodified SQL is still parsed above and compiled by the
            # protected disposable real-Postgres schema-clone runner.
            if "LookupExplicitNamespace only supports pg_catalog and public" not in str(e):
                first = function_sql.splitlines()[0]
                raise SystemExit(f"PL/pgSQL grammar error in {path.relative_to(root)}: {first}: {e}")
            normalized = re.sub(
                r"\b(?:atlas|auth|ledger|reality|local_intel|household)\.",
                "public.", function_sql, flags=re.IGNORECASE)
            if normalized == function_sql:
                first = function_sql.splitlines()[0]
                raise SystemExit(f"Unresolved parser namespace in {path.relative_to(root)}: {first}: {e}")
            try:
                parse_plpgsql(normalized)
            except Exception as retry_error:
                first = function_sql.splitlines()[0]
                raise SystemExit(
                    f"PL/pgSQL syntax still unparsed after schema-only normalization "
                    f"in {path.relative_to(root)}: {first}: {retry_error}")
            print(f"NOTE parser-only namespace normalization {path.relative_to(root)}: "
                  f"{function_sql.splitlines()[0]}; original SQL still requires real clone compile")
        parsed += 1
        functions += 1
    print(f"PASS PostgreSQL grammar {path.relative_to(root)}: "
          f"{len(statements)} SQL statements, {parsed} PL/pgSQL functions")
if functions < 20:
    raise SystemExit(f"Too few PL/pgSQL bodies parsed ({functions})")
print(f"PASS SQL and PL/pgSQL grammar on {len(paths)} held candidates and postconditions, "
      f"{functions} function bodies")
print("PENDING disposable production-schema compilation and independent signed acceptance")

# W07 ordinary comments are held source code, not an installed RPC. Validate
# the local-only signed probe source on the same PR without any database access.
w07=root/"atlas_native_original_work_comments_v1"
if w07.is_dir():
    import ast
    probe=root.parents[1]/"scripts"/"validate-atlas-native-original-work-comments-signed-http.py"
    if not probe.is_file():
        raise SystemExit("W07 held candidate is missing its signed local probe")
    source=probe.read_text()
    ast.parse(source, filename=str(probe))
    sql=(w07/"candidate.sql").read_text()
    required_sql=(
        "native_original_work_comments_v1",
        "append_native_original_work_comment_self_api_v1",
        "read_native_original_work_comments_self_api_v1",
        "native_original_work_comment_actor_v1",
        "BEFORE UPDATE OR DELETE",
        "originalWorkStateUnchanged",
        "notificationDelivered",
        "isWorkResult",
        "authorIdentityDisclosure",
        "p_after_recorded_at",
    )
    required_signed=(
        "127[.]0[.]0[.]1",
        "c1.local_status()",
        "base.setup_auth",
        "c1.sign_in",
        '"owner", "worker", "outsider", "no-seat"',
        "revoked worker",
        "different",
        "original Work",
        "work_execution_results",
    )
    for token in required_sql:
        if token not in sql:
            raise SystemExit("W07 SQL source required token absent: "+token)
    if "m.user_id=auth.uid()" not in sql or "m.person_id=v_person" in sql:
        raise SystemExit("W07 accepted membership must match signed Auth owner, not legacy Person ID")
    if "'self_adoption'" in sql:
        raise SystemExit("W07 must not admit a retired allocation establishment basis")
    for token in required_signed:
        if token.lower() not in source.lower():
            raise SystemExit("W07 signed local probe required token absent: "+token)
    if "mcp.supabase.com" in source or "zirqkouammpwxlqfbsvf.supabase.co" in source:
        raise SystemExit("W07 local-only signed probe contains a production endpoint")
    print("PASS W07 source grammar plus parseable local-only signed GoTrue/REST probe")
    print("PENDING W07 real protected disposable signed-clone execution")
