#!/usr/bin/env python3
"""HELD C1 disposable-clone ACL parity observation. No SQL writes.

Only accepts the canonical local PostgreSQL clone URL, executes one fixed
SELECT across six exact C1 functions, and emits only a fixed public-safe
difference code. Never prints SQL errors, role/catalog rows, schema dumps,
passwords, session tokens, or a connection string.
"""
from __future__ import annotations

import argparse
import re
import subprocess

CLONE_URL = re.compile(
    r"^postgresql://postgres:postgres@127\.0\.0\.1:([0-9]{4,5})/postgres$"
)
FUNCTIONS = (
    "atlas_establish",
    "atlas_revise",
    "atlas_read",
    "public_establish",
    "public_revise",
    "public_read",
)
# Source-of-truth permission contract in pinned C1 migration:
# each public and Atlas function: anon=NO, authenticated=YES, PUBLIC=NO.
EXPECTED = ("f", "t", "f")
LABELS = ("anon", "authenticated", "public")
FALLBACK = "unclassified"

# SQL is constant; no user input, db or log data is interpolated into it.
QUERY = """WITH targets(idx, signature) AS (
  VALUES
    (1, 'atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'),
    (2, 'atlas.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'),
    (3, 'atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'),
    (4, 'public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'),
    (5, 'public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'),
    (6, 'public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)')
), resolved AS (
  SELECT idx, signature::regprocedure AS func_oid FROM targets
)
SELECT r.idx,
       CASE WHEN has_function_privilege('anon',r.func_oid,'EXECUTE')
         THEN 't' ELSE 'f' END,
       CASE WHEN has_function_privilege('authenticated',r.func_oid,'EXECUTE')
         THEN 't' ELSE 'f' END,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p,
              LATERAL aclexplode(
                COALESCE(p.proacl,acldefault('f',p.proowner))) e
         WHERE p.oid=r.func_oid
           AND e.grantee=0 AND e.privilege_type='EXECUTE'
       ) THEN 't' ELSE 'f' END
FROM resolved r ORDER BY r.idx;
"""


def classify(rows: str) -> str:
    observed = rows.strip().splitlines()
    if len(observed) != len(FUNCTIONS):
        return FALLBACK
    mismatches = []
    for index, line in enumerate(observed):
        fields = line.split("|")
        if len(fields) != 4 or fields[0] != str(index + 1):
            return FALLBACK
        if any(bit not in ("t", "f") for bit in fields[1:]):
            return FALLBACK
        for i, (actual, expected) in enumerate(zip(fields[1:], EXPECTED)):
            if actual != expected:
                mismatches.append(FUNCTIONS[index] + "_" + LABELS[i])
    return "pass" if not mismatches else ",".join(mismatches)


def local_clone_url(value: str) -> bool:
    match = CLONE_URL.fullmatch(value)
    return bool(match and 1024 <= int(match.group(1)) <= 65535)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--db-url", required=True)
    args = p.parse_args()
    answer = FALLBACK
    if local_clone_url(args.db_url):
        try:
            psql = subprocess.run(
                ["psql", args.db_url, "-X", "-A", "-t", "-F", "|",
                 "-v", "ON_ERROR_STOP=1", "-c", QUERY],
                capture_output=True, text=True, timeout=20, check=False)
            if psql.returncode == 0 and len(psql.stdout) <= 8192:
                answer = classify(psql.stdout)
        except (OSError, subprocess.TimeoutExpired, UnicodeError):
            pass
    print("C1_CLONE_ACL=" + answer)


if __name__ == "__main__":
    main()
