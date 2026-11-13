#!/usr/bin/env python3
"""Create one E05 synthetic nonfarm original-Work fixture, LOCAL CLONE ONLY.

This is a fixture *preparer*, not a schema-clone launcher or acceptance proof.
It does not use service_role, forge a bearer, create a migration, or touch
Production. A fresh PostgreSQL cluster must already be running on 127.0.0.1,
with PGDATA inside RUNNER_TEMP, a new atlas_e05_<nonce> database and a restored
Noel schema and roles. The local GoTrue/PostgREST stack must be separately
configured to talk to exactly that database before running Atlas's signed
acceptance runner.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

DATABASE = re.compile(r"^atlas_e05_[0-9a-f]{8,24}$")
FAKE_MAIL = re.compile(r"^e05-[a-z0-9-]+@example[.]invalid$")
IDENTITIES = {
    "governor": "e5200000-0000-4000-8000-000000000001",
    "recipient": "e5200000-0000-4000-8000-000000000002",
    "outsider": "e5200000-0000-4000-8000-000000000003",
}
ORG = "e5200000-0000-4000-8000-000000000801"
LEDGER = "e5200000-0000-4000-8000-000000000401"
FOREIGN_LEDGER = "e5200000-0000-4000-8000-000000000402"
WORK = "e5200000-0000-4000-8000-000000000901"
PERSON = "e5200000-0000-4000-8000-000000000102"
SEAT = "e5200000-0000-4000-8000-000000000502"
TITLE = "E05 SYNTHETIC nonprofit archive review"
FIXTURE = (Path(__file__).resolve().parents[1]
           / "candidates/atlas/atlas_e05_nonfarm_original_work_clone_only/fixture.sql")

class Refused(RuntimeError):
    pass

def require(value, reason):
    if not value:
        raise Refused(reason)

def db_name(url):
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        raise Refused("Invalid E05 clone URL") from None
    require(parsed.scheme == "postgresql" and parsed.hostname == "127.0.0.1"
            and port is not None and parsed.path.count("/") == 1
            and DATABASE.fullmatch(parsed.path[1:]) is not None
            and parsed.query in ("", "sslmode=disable")
            and not parsed.fragment, "Only a named local E05 test database is allowed")
    return parsed.path[1:]

def job_temp():
    supplied = os.environ.get("RUNNER_TEMP")
    require(bool(supplied), "RUNNER_TEMP is required")
    supplied_path = Path(supplied)
    require(not supplied_path.is_symlink(),
            "RUNNER_TEMP must not be a symbolic link")
    path = supplied_path.resolve(strict=True)
    require(path.is_dir(),
            "RUNNER_TEMP must be a real job-owned directory")
    return path

def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"

def psql(db_url, sql):
    try:
        completed = subprocess.run(
            ["psql", db_url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
             "-v", "VERBOSITY=terse"],
            input=sql, capture_output=True, text=True, check=False, timeout=70)
    except (OSError, subprocess.SubprocessError):
        raise Refused("Local E05 Postgres unavailable; private diagnostics withheld") from None
    require(completed.returncode == 0,
            "Local E05 SQL failed; private diagnostics withheld")
    return completed.stdout.strip()

def guard(db_url, temp):
    database = db_name(db_url)
    columns = psql(db_url,
        "SELECT current_database(), inet_server_addr()::text, current_setting('data_directory');")
    fields = columns.split("|")
    require(len(fields) == 3 and fields[0] == database and fields[1] == "127.0.0.1",
            "Wrong local E05 source server")
    pgdata = Path(fields[2]).resolve(strict=True)
    require(temp in pgdata.parents and pgdata.is_dir(),
            "PGDATA must be inside this fresh job-only RUNNER_TEMP")
    # Fresh clone, before any fixture mutation. Do not treat an old
    # noel_schema_clone or a filled application DB as disposable.
    untouched = psql(db_url, """
        SELECT (SELECT count(*) FROM auth.users),
               (SELECT count(*) FROM atlas.organizations),
               (SELECT count(*) FROM atlas.work_items),
               (SELECT count(*) FROM reality.entities),
               (SELECT count(*) FROM ledger.seats);
    """)
    require(untouched == "0|0|0|0|0",
            "E05 fixture requires a truly empty schema-only named clone")
    return database

def credentials():
    values = {}
    for actor in IDENTITIES:
        email = os.environ.get("ATLAS_E05_" + actor.upper() + "_EMAIL", "")
        password = os.environ.get("ATLAS_E05_" + actor.upper() + "_PASSWORD", "")
        require(FAKE_MAIL.fullmatch(email) is not None
                and email.startswith("e05-" + actor + "-")
                and len(password) >= 12,
                "Three different fictional job-only E05 login credentials required")
        values[actor] = (email, password)
    require(len({v[0] for v in values.values()}) == 3 and
            len({v[1] for v in values.values()}) == 3,
            "E05 actor email/password pairs must be distinct")
    return values

def auth_sql(actors):
    statements = []
    for role, uid in IDENTITIES.items():
        email, password = actors[role]
        e, p = sql_literal(email), sql_literal(password)
        statements.append(f"""
            UPDATE auth.users SET
                instance_id='00000000-0000-0000-0000-000000000000'::uuid,
                email={e},
                encrypted_password=extensions.crypt({p},extensions.gen_salt('bf')),
                email_confirmed_at=now(),
                confirmation_token='',recovery_token='',email_change='',
                email_change_token_new='',email_change_token_current='',
                phone_change='',phone_change_token='',
                reauthentication_token='',
                raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
                raw_user_meta_data='{{}}'::jsonb
            WHERE id='{uid}'::uuid;
            INSERT INTO auth.identities
                (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
            VALUES (gen_random_uuid(),{e},'{uid}'::uuid,
                jsonb_build_object('sub','{uid}','email',{e}),
                'email',now(),now());
        """)
    statements.append("""
        DO $e05_auth$
        BEGIN
            IF (SELECT count(*) FROM auth.users
                WHERE id IN ('e5200000-0000-4000-8000-000000000001'::uuid,
                             'e5200000-0000-4000-8000-000000000002'::uuid,
                             'e5200000-0000-4000-8000-000000000003'::uuid)
                  AND email_confirmed_at IS NOT NULL
                  AND encrypted_password IS NOT NULL) != 3
              OR (SELECT count(*) FROM auth.identities
                  WHERE provider='email'
                    AND user_id IN ('e5200000-0000-4000-8000-000000000001'::uuid,
                                    'e5200000-0000-4000-8000-000000000002'::uuid,
                                    'e5200000-0000-4000-8000-000000000003'::uuid)) != 3
            THEN RAISE EXCEPTION 'E05 synthetic Auth fixture incomplete'; END IF;
        END; $e05_auth$;
        NOTIFY pgrst, 'reload schema';
    """)
    return "\n".join(statements)

def manifest():
    return {
        "contractVersion": "atlas_e05_nonfarm_clone_fixture_v1",
        "organizationId": ORG,
        "ledgerId": LEDGER,
        "foreignLedgerId": FOREIGN_LEDGER,
        "workItemId": WORK,
        "workerPersonId": PERSON,
        "workerSeatId": SEAT,
        "actorIds": IDENTITIES,
        "title": TITLE,
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    db_name(args.db_url)
    temp = job_temp()
    output = Path(args.output).resolve()
    require(temp in output.parents and not output.exists(),
            "New manifest path must be inside RUNNER_TEMP")
    require(FIXTURE.is_file() and not FIXTURE.is_symlink(),
            "Exact source-owned E05 fixture file missing")
    creds = credentials()
    guard(args.db_url, temp)
    # The entire source fixture plus Auth bootstrap is atomic. In case of
    # failure Postgres rolls back, and the only returned result is a refusal.
    source = FIXTURE.read_text(encoding="utf-8")
    require("E05 SYNTHETIC nonprofit archive review" in source
            and re.search(r"insert\\s+into\\s+atlas[.]farms\\b", source, re.I) is None,
            "Unrecognized or agricultural E05 fixture source")
    psql(args.db_url, "BEGIN;\n" + source + "\n" + auth_sql(creds)
         + "\nCOMMIT;\n")
    confirmed = psql(args.db_url, f"""
        SELECT (SELECT count(*) FROM atlas.farms WHERE organization_id='{ORG}'::uuid),
               (SELECT count(*) FROM atlas.work_items WHERE id='{WORK}'::uuid
                   AND work_state='open'
                   AND result_contract_key='ordinary_company_work_worker_attestation_v1'),
               (SELECT count(*) FROM ledger.seats WHERE id='{SEAT}'::uuid
                   AND seat_state='active');
    """)
    require(confirmed == "0|1|1", "E05 source postconditions not confirmed")
    # Exclusive private creation: the manifest must never be world-readable,
    # even between opening the file and applying a later chmod.
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(manifest(), handle, indent=2)
        handle.write("\\n")
    print("E05_SYNTHETIC_NONFARM_FIXTURE_PREPARED; SIGNED_ACCEPTANCE_NOT_RUN")

if __name__ == "__main__":
    try:
        main()
    except (Refused, OSError, ValueError) as exc:
        # Never echo SQL, credentials or connection strings.
        print(str(exc) if isinstance(exc, Refused) else "E05 fixture preparation unavailable")
        raise SystemExit(1) from None
