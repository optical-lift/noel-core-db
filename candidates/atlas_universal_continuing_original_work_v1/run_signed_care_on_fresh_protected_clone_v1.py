#!/usr/bin/env python3
"""INTEGRATION TEST ONLY: source-exact two-draft signed care on fresh clone.

Runs only inside an ALREADY STARTED, throwaway Supabase local environment with
a production-SCHEMA-only snapshot. Never starts a server or uses remote URLs.
Uses the canonical held original-Work candidate+fixture and two exact draft
checkouts, then the signed private-source test. All changes are disposable,
but the clone needs to be destroyed after this process (not retained).
DO NOT run against RiverSong's noel_schema_clone:55432 or any live database.
"""
import argparse
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE=Path(__file__).resolve().parent
CARE=HERE.parents[1]
BASE="candidates/atlas_universal_continuing_original_work_v1/"
DONE_SHA="dc793c94365f2f1f68185aa4446f61e17fb10ce6"

def stop(message): raise SystemExit("STOP: "+message)

def head(path):
    try:
        return subprocess.check_output(
          ["git","-C",str(path),"rev-parse","HEAD"],
          text=True,stderr=subprocess.DEVNULL).strip()
    except (OSError,subprocess.CalledProcessError):
        stop("Missing source checkout: "+str(path))

def sql_file(folder,path,wrapped=False):
    src=folder/path
    if not src.is_file(): stop("Missing exact reviewed source "+str(src))
    val=src.read_text(encoding="utf-8")
    if wrapped:
        lines=val.splitlines()
        if len(lines)<3 or lines[0]!="BEGIN;" or lines[-1]!="COMMIT;":
            stop("Unknown SQL transaction boundaries: "+str(src))
        return "\n".join(lines[1:-1])+"\n"
    return val+"\n"

def psql(db,sql,description):
    result=subprocess.run(
      ["psql",db,"-X","-v","ON_ERROR_STOP=1",
       "-v","VERBOSITY=terse","-P","pager=off"],
      input=sql,text=True,capture_output=True)
    if result.returncode:
        stop(description+" failed (disposable clone must be destroyed): "+
             (result.stderr or result.stdout)[-800:])
    print("PASS",description,flush=True)
    return result.stdout

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--main-checkout",required=True,type=Path)
    p.add_argument("--done-checkout",required=True,type=Path)
    p.add_argument("--output",required=True,type=Path)
    args=p.parse_args()
    if not re.fullmatch(
      r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:54322/postgres",args.db_url):
        stop("Only disposable local Supabase Postgres at 127.0.0.1:54322 admitted")
    if head(args.done_checkout)!=DONE_SHA:
        stop("Universal Done source SHA differs from reviewed PR #2368")
    if not head(args.main_checkout) or not head(CARE):
        stop("Missing reviewed original Work and care checkouts")
    local_status=subprocess.run(
      ["supabase","status","-o","env"],text=True,capture_output=True)
    if local_status.returncode or "API_URL=" not in local_status.stdout:
        stop("Supabase local Auth+REST is not started: use protected clone validator")
    guard="""SELECT CASE WHEN current_database()='postgres'
        AND to_regclass('auth.users') IS NOT NULL
        AND to_regclass('atlas.work_items') IS NOT NULL
        AND to_regclass('reality.entities') IS NOT NULL
        AND to_regclass('atlas.work_lifecycle_events_v1') IS NULL
        AND NOT EXISTS(SELECT 1 FROM atlas.growing_objects
          WHERE id='e5200000-0000-4000-8000-000000000b03'::uuid)
      THEN 'FRESH_DISPOSABLE' ELSE 'REFUSE' END;"""
    pre=psql(args.db_url,guard,"native-schema disposable clone preflight")
    if "FRESH_DISPOSABLE" not in pre: stop("Clone is not a fresh synthetic fixture")
    original="supabase/migrations/20261026215011_atlas_universal_original_work_integrated_v1.sql"
    fixture="validation/fixtures/20261026215011_atlas_universal_original_work_integrated_v1.sql"
    psql(args.db_url,sql_file(args.main_checkout,original),
         "held original Work source baseline")
    a="candidates/atlas_universal_work_lifecycle_v1/"
    combined=("BEGIN;\n"+
      sql_file(args.done_checkout,a+"04_shadow_release_candidate.sql",True)+
      sql_file(args.done_checkout,a+"06_single_transition_authority_private.sql")+
      sql_file(CARE,BASE+"release_candidate.sql",True)+
      sql_file(CARE,BASE+"10_care_actual_single_done_cutover_candidate.sql")+
      sql_file(CARE,BASE+"11_care_single_done_cross_draft_postconditions.sql")+
      "\nCOMMIT;\n")
    psql(args.db_url,combined,"combined care/Done private source install in throwaway clone")
    psql(args.db_url,sql_file(args.main_checkout,fixture),
         "canonical fictional original Work fixture")
    psql(args.db_url,sql_file(CARE,BASE+"signed_care_single_done_fictional_fixture_v1.sql"),
         "fictional Bed 3 governed Rhythm/weed source")
    proof=HERE/"validate_signed_care_single_done_clone_v1.py"
    result=subprocess.run(
      [sys.executable,str(proof),"--db-url",args.db_url,
       "--output",str(args.output)],text=True)
    if result.returncode:
        stop("Genuine signed care test failed; dispose of local clone")
    print("PASS protected disposable source+signed care acceptance",flush=True)
    print("CAUTION: proof does NOT establish real public care writer grants,"
          " standing release, or Today successor sequencing",flush=True)

if __name__=="__main__":
    main()
