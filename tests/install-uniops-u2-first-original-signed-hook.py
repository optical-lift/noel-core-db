#!/usr/bin/env python3
"""Add exact test-only U2 signed hook to a checked-out validator COPY.

The canonical validator on Noel main remains unmodified. Fail closed on drift.
"""
from pathlib import Path
import hashlib
import sys

def fail(message):
    raise SystemExit("STOP isolated U2 test hook: " + message)

if len(sys.argv)!=2:
    fail("usage: installer DISPOSABLE_LOCAL_VALIDATOR_COPY")
path=Path(sys.argv[1])
if not path.is_file() or path.is_symlink():
    fail("regular ephemeral validator required")
data=path.read_text()
git_blob=hashlib.sha1(b"blob "+str(len(data.encode())).encode()+b"\0"+data.encode()).hexdigest()
if git_blob!="39f526cd8671f0aadbaab61c66dfc4971ef52131":
    fail("canonical validator source drift")
anchors=(
 ("signed_http_probe=false\n", "signed_http_probe=false\nsigned_accepted_first_probe=true\n"),
 ('if [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||',
  'if [ "$signed_accepted_first_probe" = true ] || [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||'),
 ('if [ "$signed_care_single_done_probe" = true ] ||',
  'if [ "$signed_accepted_first_probe" = true ] || [ "$signed_care_single_done_probe" = true ] ||'),
)
for old,new in anchors:
    if data.count(old)!=1:
        fail("missing or ambiguous canonical authorization / local startup anchor")
    data=data.replace(old,new,1)
marker='phase="candidate domain schema lint"\n'
if data.count(marker)!=1:
    fail("candidate lint hook anchor changed")
hook='''# Source-pinned HELD U1B/U2 real-signed proof; all data fictional.
phase="signed integrated U1B source and U2 accepted-first original"
test -s "$repo_root/tests/uniops-option-a-first-mowing-signed-fixture.sql"
test -s "$repo_root/tests/validate-uniops-option-a-u2-accepted-first-signed.py"
psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$repo_root/tests/uniops-option-a-first-mowing-signed-fixture.sql" >"$artifacts_dir/uniops-u2-fictional-fixture.log" 2>&1
python3 "$repo_root/tests/validate-uniops-option-a-u2-accepted-first-signed.py" --db-url "$database_url" --output "$artifacts_dir/uniops-u2-signed-summary.txt" >"$artifacts_dir/uniops-u2-signed.log" 2>&1
test -s "$artifacts_dir/uniops-u2-signed-summary.txt"
grep -q '^PASS genuine separate signed local' "$artifacts_dir/uniops-u2-signed-summary.txt"

'''
data=data.replace(marker,hook+marker,1)
if data.count("signed_accepted_first_probe")!=3:
    fail("not exactly one U2 opt-in path")
path.write_text(data)
print("PASS one locally copied source-checked validator signed U2 hook (no production or migration)")
