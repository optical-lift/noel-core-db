#!/usr/bin/env python3
"""Patch an EPHEMERAL checkout's clone validator, never canonical main.

The only additional branch is the precisely named disposable Atlas candidate.
It starts real LOCAL Auth/REST, invokes independent signed validation, and
never changes the production dump/create/authorization workflow.
"""
import argparse
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument("--controller",required=True,type=Path)
args=parser.parse_args()
file=args.controller.resolve()
if file.name!="validate-production-schema-clone.sh" or file.parent.name!="scripts":
    raise SystemExit("Only an ephemeral checked-out canonical clone controller may be patched")
s=file.read_text()
if "signed_option_c_probe" in s:
    raise SystemExit("Refusing duplicate or already modified option C hook")

def once(before,after,label):
    global s
    if s.count(before)!=1:
        raise SystemExit("Refusing changing or ambiguous canonical hook: "+label)
    s=s.replace(before,after,1)

once("signed_venue_bed_probe=false\n",
     """signed_venue_bed_probe=false
signed_option_c_probe=false
# HE LD: specifically named disposable Option C read-only signed clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_option_c_contextual_review_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "scripts/validate-atlas-option-c-contextual-signed-http.py" ]; then
    echo "Option C signed proof requires fictional fixture, postconditions and local test." >&2
    exit 2
  fi
  signed_option_c_probe=true
fi
""","exact signed lane")
once('       [ "$signed_venue_bed_probe" = true ]; then',
     '       [ "$signed_venue_bed_probe" = true ] ||\n'
     '       [ "$signed_option_c_probe" = true ]; then',
     "signed transport startup")
once('       [ "$signed_venue_bed_probe" = true ]; then\n'
     '       supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector',
     '       [ "$signed_venue_bed_probe" = true ] ||\n'
     '       [ "$signed_option_c_probe" = true ]; then\n'
     '       supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector',
     "minimal signed local container runtime")
marker='if [ "$signed_ledger_reciprocal_probe" = true ]; then\n'
if s.count(marker)!=2:
    raise SystemExit("Expected one signed runner block and one summary marker")
runmarker='if [ "$signed_ledger_reciprocal_probe" = true ]; then\n  phase="signed reciprocal Ledger roots, private intake and Person identity"'
block="""if [ "$signed_option_c_probe" = true ]; then
  phase="genuine signed local Option C selected versus primary Ledger authority"
  python3 "$repo_root/scripts/validate-atlas-option-c-contextual-signed-http.py" \\
    --db-url "$database_url" \\
    --output "$artifacts_dir/signed-option-c-context-summary.txt" \\
    >"$artifacts_dir/signed-option-c-context.log" 2>&1
  test -s "$artifacts_dir/signed-option-c-context-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-option-c-context-summary.txt"
fi

"""
once(runmarker,block+runmarker,"local signed HTTP runner")
summarymarker='phase="complete"\n'
once(summarymarker,'''if [ "$signed_option_c_probe" = true ]; then
  echo "SIGNED local Option C contextual governor matrix passed; original Work source not changed." >> "$artifacts_dir/summary.md"
fi
'''+summarymarker,"signed proof summary")
for forbidden in ("supabase db push","supabase migration up","--linked","SUPABASE_SERVICE_ROLE_KEY"):
    if forbidden in s:
        raise SystemExit("Unsafe command appeared in ephemeral clone controller")
file.write_text(s)
print("PASS isolated existing clone harness patched for named Option C disposable signed proof")
