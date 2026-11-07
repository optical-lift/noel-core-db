#!/usr/bin/env python3
"""Patch a LOCAL COPY of the canonical clone validator for one held signed test.

NEVER edits scripts/validate-production-schema-clone.sh on main. This hook
uses anchored replacements and refuses an unfamiliar upstream script. The
output must stay under the current workspace scripts/ so repo_root resolves.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def exactly_once(text: str, needle: str, replacement: str) -> str:
    count=text.count(needle)
    if count != 1:
        raise RuntimeError("Refuse changed canonical clone anchor: "+repr(needle[:100])+f", count={count}")
    return text.replace(needle,replacement,1)


def install(original: str) -> str:
    src=original
    src=exactly_once(
      src,"signed_person_mail_probe=false\n",
      """signed_person_mail_probe=false
signed_venue_bed_probe=false
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_venue_bed_shared_use_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed Venue Bed clone requires fiction-only fixture and postconditions." >&2
    exit 2
  fi
  signed_venue_bed_probe=true
fi
""")
    src=exactly_once(
      src,'if [ "$signed_http_probe" = true ] ||',
      'if [ "$signed_venue_bed_probe" = true ] ||\n     [ "$signed_http_probe" = true ] ||')
    src=exactly_once(
      src,
      '       [ "$signed_ledger_disposition_v2_probe" = true ]; then\n      supabase start -x',
      '       [ "$signed_ledger_disposition_v2_probe" = true ] ||\n'
      '       [ "$signed_venue_bed_probe" = true ]; then\n      supabase start -x')
    src=exactly_once(
      src,
      'if [ "$signed_http_probe" = true ]; then\n  phase="signed local HTTP API authorization matrix"',
      """if [ "$signed_venue_bed_probe" = true ]; then
  phase="genuine signed local Flower/Venue Bed-use authorization"
  python3 "$repo_root/scripts/validate-atlas-venue-bed-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-venue-bed-summary.txt" \
    >"$artifacts_dir/signed-venue-bed.log" 2>&1
  test -s "$artifacts_dir/signed-venue-bed-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-venue-bed-summary.txt"
fi

if [ "$signed_http_probe" = true ]; then
  phase="signed local HTTP API authorization matrix"\
""")
    assert src.count("signed_venue_bed_probe=true")==1
    assert src.count("signed-venue-bed-summary.txt")==3
    assert "supabase db push" not in src and "supabase db reset --linked" not in src
    return src


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--source",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    source=Path(args.source).resolve()
    out=Path(args.output).resolve()
    if source==out:
        raise SystemExit("Refuse to overwrite canonical clone validator")
    if source.name!="validate-production-schema-clone.sh":
        raise SystemExit("Unexpected canonical source path")
    if out.name!="validate-production-schema-clone-venue-local-only.sh":
        raise SystemExit("Output must be an explicitly local-only controller")
    if source.parent != out.parent:
        raise SystemExit("Must keep patched script inside the canonical scripts directory")
    out.write_text(install(source.read_text(encoding="utf-8")),encoding="utf-8")
    out.chmod(0o700)
    print("PASS installed local-only genuine-signed Venue Bed clone hook; canonical source unchanged")


if __name__=="__main__":
    main()
