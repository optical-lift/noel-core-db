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
            first = function_sql.splitlines()[0]
            raise SystemExit(f"PL/pgSQL grammar error in {path.relative_to(root)}: {first}: {e}")
        parsed += 1
        functions += 1
    print(f"PASS PostgreSQL grammar {path.relative_to(root)}: "
          f"{len(statements)} SQL statements, {parsed} PL/pgSQL functions")
if functions < 20:
    raise SystemExit(f"Too few PL/pgSQL bodies parsed ({functions})")
print(f"PASS SQL and PL/pgSQL grammar on {len(paths)} held candidates, "
      f"{functions} function bodies")
print("PENDING disposable production-schema compilation and independent signed acceptance")
