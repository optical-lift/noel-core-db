#!/usr/bin/env python3
"""Two held Noel drafts against the ALREADY EXISTING RiverSong clone.

Uses the precise local connection setup from the previously successful
Build 3 read-only diagnostic. No TCP password guesses, container start,
production URL, release workflow, or permanent installation.

Usage from RiverSong:
  python3 ~/Downloads/noel-care-rhythm-pr2362/candidates/atlas_universal_continuing_original_work_v1/manual_riversong_care_single_done_rollback.py
"""
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

downloads = Path.home() / "Downloads"
done_checkout = downloads / "noel-care-done-pr2368"
care_checkout = Path(__file__).resolve().parents[2]
diagnostic = downloads / "atlas_universal_intelligence_source_v3/diagnose_riversong_clone_readonly.sh"
done_sha = "dc793c94365f2f1f68185aa4446f61e17fb10ce6"

def stop(message):
    raise SystemExit("STOP: " + message)

def git_head(folder):
    try:
        return subprocess.check_output(
            ["git", "-C", str(folder), "rev-parse", "HEAD"],
            text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        stop("Expected checked-out Noel candidate not found: " + str(folder))

if git_head(done_checkout) != done_sha:
    stop("Universal Done checkout is not the exact reviewed PR #2368 revision")
care_head = git_head(care_checkout)

def read_sql(folder, relative, wrapped=False):
    path = folder / relative
    if not path.is_file():
        stop("Required source file is missing: " + str(path))
    # Do not execute uncommitted SQL edits in a supposedly frozen proof.
    status = subprocess.run(
        ["git", "-C", str(folder), "diff", "--quiet", "HEAD", "--", relative])
    if status.returncode != 0:
        stop("Candidate SQL differs from the checked-out commit: " + str(path))
    contents = path.read_text(encoding="utf-8")
    if wrapped:
        parts = contents.splitlines()
        if len(parts) < 3 or parts[0] != "BEGIN;" or parts[-1] != "COMMIT;":
            stop("Unknown SQL transaction boundaries: " + str(path))
        return "\n".join(parts[1:-1]) + "\n"
    return contents + "\n"

if not diagnostic.is_file():
    stop("Existing Build 3 read-only diagnostic not found")

lines = diagnostic.read_text(encoding="utf-8").splitlines(keepends=True)
if (len(lines) < 21 or
    "PSQL_ARGS=" not in lines[13] or
    "noel_schema_clone:55432" not in lines[18] or
    '"$PSQL" "${PSQL_ARGS[@]}"' not in lines[20]):
    stop("Working diagnostic connection setup has changed; refusing to guess")
setup = "".join(lines[:20])

a = "candidates/atlas_universal_work_lifecycle_v1/"
b = "candidates/atlas_universal_continuing_original_work_v1/"
sql = """BEGIN;
-- Do not execute any source unless the very first statement confirms
-- the exact existing local disposable clone and its native Atlas objects.
DO $clone_guard$
BEGIN
 IF current_database() <> 'noel_schema_clone'
    OR current_setting('port') <> '55432'
    OR current_user <> 'postgres'
    OR to_regclass('atlas.work_items') IS NULL
    OR to_regclass('atlas.rhythm_state') IS NULL
    OR to_regclass('atlas.work_execution_results') IS NULL
 THEN
   RAISE EXCEPTION 'Wrong database, user or missing native Atlas schema';
 END IF;
END;
$clone_guard$;
"""
sql += read_sql(done_checkout, a + "04_shadow_release_candidate.sql", True)
sql += read_sql(done_checkout, a + "06_single_transition_authority_private.sql")
sql += read_sql(care_checkout, b + "release_candidate.sql", True)
sql += read_sql(care_checkout, b + "10_care_actual_single_done_cutover_candidate.sql")
sql += read_sql(care_checkout, b + "11_care_single_done_cross_draft_postconditions.sql")
sql += "\nROLLBACK;\n"

print("Universal Done SHA:", done_sha, flush=True)
print("Continuing care SHA:", care_head, flush=True)
print("Target: only verified local noel_schema_clone:55432", flush=True)
print("Mode: one SQL transaction, final ROLLBACK, no releases", flush=True)

with tempfile.TemporaryDirectory(prefix="atlas-care-proof-") as temp:
    path = Path(temp) / "combined.sql"
    path.write_text(sql, encoding="utf-8")
    script = (setup + "\n" +
              '"$PSQL" "${PSQL_ARGS[@]}" -X -w -P pager=off ' +
              '-v ON_ERROR_STOP=1 -v VERBOSITY=terse -f ' +
              shlex.quote(str(path)) + "\n")
    result = subprocess.run(["bash"], input=script, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.splitlines()
    for line in output[-32 if result.returncode else -16:]:
        print(line)
    if result.returncode:
        sys.exit("FAIL: SQL session closed and its open transaction rolled back.")
    if not output or output[-1].strip() != "ROLLBACK":
        stop("SQL exited without evidence of the final ROLLBACK")
    print("PASS: combined SQL and cross-draft structural postconditions.")
    print("All test changes ROLLED BACK; no production change.")
    print("Still outstanding: genuine signed worker/outsider and Today/successor tests.")
