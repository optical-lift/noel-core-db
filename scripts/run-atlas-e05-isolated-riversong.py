#!/usr/bin/env python3
"""Execute the ALREADY-AUTHORED E05 signed test on a pre-established RiverSong clone.

This does not provision a clone, alter CI, restore a schema, touch Production,
generate credentials or expose secrets. The named fresh job-local PostgreSQL
cluster AND GoTrue/PostgREST services must already exist. Exact three-actor
signed acceptance is performed by the reviewed Atlas runner, not this wrapper.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlsplit

import importlib.util

HERE = Path(__file__).resolve().parent
PREPARER = HERE / "prepare-atlas-e05-nonfarm-clone-fixture.py"
EXPECTED_ATLAS_RUNNER_BLOB = "d386ff1d752cceea631316a84692088d6257b94d"

class Refused(RuntimeError):
    pass

def require(ok, reason):
    if not ok:
        raise Refused(reason)

def load_preparer():
    spec = importlib.util.spec_from_file_location("e05_fixture_preparer", PREPARER)
    require(spec is not None and spec.loader is not None,
            "No reviewed E05 fixture preparer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def file_blob_sha(path):
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\\0" + data).hexdigest()

def validate(config, preparer):
    db = config.db_url
    preparer.db_name(db)
    api = urlsplit(config.api_url)
    require(api.scheme == "http" and api.hostname == "127.0.0.1"
            and api.port is not None and not api.path and
            not api.query and not api.fragment and not api.username
            and not api.password,
            "Only a loopback local GoTrue/PostgREST origin is allowed")
    temp = preparer.job_temp()
    runner = Path(config.atlas_runner)
    require(runner.is_file() and not runner.is_symlink(),
            "An exact reviewed Atlas runner file is required")
    require(file_blob_sha(runner) == EXPECTED_ATLAS_RUNNER_BLOB,
            "Atlas E05 runner source does not match the pinned draft")
    creds = preparer.credentials()
    require(os.environ.get("ATLAS_E05_LOCAL_ANON_KEY", "").strip() != ""
            and len(os.environ["ATLAS_E05_LOCAL_ANON_KEY"]) > 20,
            "Local REST anon key must be provided in job environment")
    manifest = temp / "e05-local-fixture-manifest.json"
    receipt = temp / "e05-local-signed-result.json"
    require(not manifest.exists() and not receipt.exists(),
            "Fresh job-only fixture and receipt paths required")
    require(len(creds) == 3, "Three genuine distinct actors required")
    return temp, runner, manifest, receipt

def invoke(argv, timeout):
    # Keep all raw diagnostics in this isolated process. Never print subprocess
    # output to workflow logs: SQL, error bodies or credentials may be present.
    try:
        result = subprocess.run(argv, capture_output=True, text=True,
                                timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        raise Refused("E05 isolated execution command unavailable") from None
    return result.returncode

def execute(config):
    preparer = load_preparer()
    _temp, runner, manifest, receipt = validate(config, preparer)
    # Before any mutation, confirm cluster's actual PGDATA is job-owned,
    # connection is loopback and all relevant tables are empty.
    preparer.guard(config.db_url, preparer.job_temp())
    status = invoke([
        sys.executable, str(PREPARER),
        "--db-url", config.db_url,
        "--output", str(manifest),
    ], 150)
    require(status == 0 and manifest.is_file(),
            "E05 source fixture refused or failed (private details withheld)")
    status = invoke([
        sys.executable, str(runner),
        "--db-url", config.db_url,
        "--api-url", config.api_url,
        "--fixture", str(manifest),
        "--output", str(receipt),
    ], 480)
    require(receipt.is_file(),
            "E05 signed runner produced no bounded result receipt")
    try:
        result = json.loads(receipt.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise Refused("E05 signed result receipt is invalid") from None
    require(status == 0 and result.get("signedSourceAcceptance") == "PASS"
            and result.get("state") == "SIGNED_SOURCE_PASS_BROWSER_HELD"
            and result.get("separateRealGoTrueSessions") == 3
            and result.get("governorAcceptedResultHistoryVerified") is True
            and result.get("connectedRecipientIndependentHistory") == "NOT_PROVED"
            and result.get("browserUserJourney") == "NOT_RUN"
            and result.get("productionChanges") is False,
            "E05 signed source acceptance did not pass all reviewed assertions")
    print("E05_SIGNED_SOURCE_ACCEPTANCE=PASS; BROWSER=NOT_RUN; RECIPIENT_HISTORY=HELD")
    return 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--atlas-runner", required=True)
    args = parser.parse_args()
    try:
        return execute(args)
    except (Refused, OSError, ValueError) as exc:
        # Do not log connection strings, environment, SQL or raw HTTP errors.
        print(str(exc) if isinstance(exc, Refused)
              else "E05 isolated signed execution unavailable")
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
