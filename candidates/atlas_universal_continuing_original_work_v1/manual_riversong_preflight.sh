#!/usr/bin/env bash
# Local only, non-destructive environment check for Atlas continuing Work.
# This does not read secrets, contact the production DB, or change a DB.
set -u
printf 'ATLAS CONTINUING WORK — RiverSong manual smoke-test readiness\n'
printf 'This check makes no changes.\n'
printf '\n'
for name in git gh docker supabase psql python3; do
  if command -v "$name" >/dev/null 2>&1; then
    printf '%-12s AVAILABLE\n' "$name"
  else
    printf '%-12s MISSING\n' "$name"
  fi
done
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    printf 'Docker engine READY\n'
  else
    printf 'Docker engine NOT RUNNING\n'
  fi
fi
if command -v supabase >/dev/null 2>&1; then
  printf 'Supabase CLI '
  supabase --version | head -1 || :
fi
if command -v psql >/dev/null 2>&1; then
  printf 'PostgreSQL client '
  psql --version | head -1 || :
fi
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    printf 'GitHub CLI authorization READY\n'
    if gh api repos/optical-lift/noel-core-db/commits/cdba9f80ca0575e52779f9e87d85d0a4e51a3f3d >/dev/null 2>&1; then
      printf 'Private Noel candidate READABLE\n'
    else
      printf 'Private Noel candidate NOT READABLE with this CLI credential\n'
    fi
  else
    printf 'GitHub CLI authorization NOT READY\n'
  fi
fi
if [ -d "$HOME/actions-runner" ]; then
  printf 'Atlas runner folder PRESENT (not modified)\n'
else
  printf 'Atlas runner folder not at ~/actions-runner (not a blocker for manual test)\n'
fi
printf '\nPlease paste these status lines into the chat. Do not paste passwords, tokens, database URLs or environment variables.\n