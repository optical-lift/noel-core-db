#!/usr/bin/env python3
"""HELD first-mowing P3 scratch SQL framing, never a source/migration edit.

PostgreSQL pg_get_functiondef source (held P3 01 and 11) deliberately has no
terminating SQL statement semicolon. The frozen P3 assembler preserves those
source bytes, but an executable psql file needs a statement delimiter after
each dollar-quoted function body. Add ONLY two exact delimiters to a verified
TEST_ONLY scratch file. Refuse any unknown source, filename or output drift.
No database or credentials are used.
"""
import hashlib
import os
from pathlib import Path
import re
import sys
import tempfile

NAME="20261107211000_atlas_uni_ops_p3_6a_TEST_ONLY.sql"
# Exact assembled, disposable SQL file from protected first P3 PG run
# #43614482791. All 18 U2/U4 and eight P3 blobs were already checked.
SOURCE_SHA256="0b765e95d9a5c6ce0f5f38954ee2ab3cc37f15b51c73c7920aeba148aa5b64bd"
REVIEWED={
 "01_result_only_rhythm_evaluator_held.sql":"155bb1c154903becdbb489c6bddb895aa9a6b597",
 "11_governed_rhythm_clock_signal_specific_hold_held.sql":"95b93e896ceaae90d9bfe59eefda695dad204e72",
}

def git_blob(payload):
    return hashlib.sha1(
        b"blob "+str(len(payload)).encode("ascii")+b"\0"+payload
    ).hexdigest()

def source_bytes(parent):
    p=Path(parent)
    if not p.is_dir() or p.is_symlink():
        raise AssertionError("Reviewed P3 source directory missing")
    bodies={}
    for filename,pin in REVIEWED.items():
        f=p/filename
        if not f.is_file() or f.is_symlink():
            raise AssertionError("Reviewed P3 source not an ordinary file")
        b=f.read_bytes()
        if git_blob(b)!=pin:
            raise AssertionError("P3 source body pin changed: "+filename)
        bodies[filename]=b.decode("utf8")
    if not bodies["01_result_only_rhythm_evaluator_held.sql"].rstrip().endswith(
            "$function$"):
        raise AssertionError("Exact evaluator function source framing drift")
    if bodies["11_governed_rhythm_clock_signal_specific_hold_held.sql"].count(
            "end;$function$\n\nCOMMIT;")!=1:
        raise AssertionError("Exact signal function source framing drift")
    return bodies

def frame(source,bodies):
    """Return ONLY two punctuation insertions for exact verified P3 stages."""
    if source.count("-- BEGIN PINNED STAGE ")!=18 or (
            source.count("-- END PINNED STAGE ")!=18):
        raise AssertionError("Expected intact 18-stage U2/U4 provenance")
    if source.count("-- BEGIN PINNED P3 6A HELD STAGE ")!=8 or (
            source.count("-- END PINNED P3 6A HELD STAGE ")!=8):
        raise AssertionError("Expected exactly eight pinned held P3 stages")
    result=source
    for name,pin in REVIEWED.items():
        begin="\n-- BEGIN PINNED P3 6A HELD STAGE "+name+" "+pin+"\n"
        end="\n-- END PINNED P3 6A HELD STAGE "+name+"\n"
        if result.count(begin)!=1 or result.count(end)!=1:
            raise AssertionError("Missing/duplicate exact P3 stage markers")
        prefix,remaining=result.split(begin,1)
        body,suffix=remaining.split(end,1)
        # The frozen 22 composer adds exactly ONE newline after source text.
        if body!=bodies[name]+"\n":
            raise AssertionError("P3 held source differs from pinned body")
        if name.startswith("01_"):
            patched=bodies[name].rstrip()+";\n\n"
        else:
            patched=bodies[name].replace(
                "end;$function$\n\nCOMMIT;",
                "end;$function$;\n\nCOMMIT;",1)
        # Source is never edited; only its scratch SQL representation gets a
        # required terminator. Exactly one trailing assembler newline remains.
        result=prefix+begin+patched+"\n"+end+suffix
    if result.count("-- BEGIN PINNED P3 6A HELD STAGE ")!=8 or (
            result.count("-- END PINNED P3 6A HELD STAGE ")!=8):
        raise AssertionError("Stage identities changed")
    # Both targeted source functions need one semicolon; no other modification.
    if result.count("end;$function$;\n\nCOMMIT;")<1:
        raise AssertionError("Signal function terminator absent")
    return result

def main(argv):
    if len(argv)!=3:
        raise SystemExit("Usage: frame-uniops-p3-6a-disposable-sql.py ABSOLUTE_P3_TEST_ONLY.sql ABSOLUTE_PINNED_P3_SOURCE_DIR")
    scratch=Path(argv[1])
    root=Path(argv[2])
    if scratch.name!=NAME or not scratch.is_absolute() or scratch.is_symlink() or (
            not scratch.is_file()):
        raise SystemExit("Refuse anything except an ordinary P3 TEST_ONLY scratch")
    resolved=scratch.resolve()
    authorized=[Path(tempfile.gettempdir()).resolve()]
    if os.environ.get("RUNNER_TEMP"):
        authorized.append(Path(os.environ["RUNNER_TEMP"]).resolve())
    if not any(resolved.is_relative_to(prefix) for prefix in authorized):
        raise SystemExit("Refuse SQL outside the disposable runner temp root")
    data=scratch.read_bytes()
    if hashlib.sha256(data).hexdigest()!=SOURCE_SHA256:
        raise SystemExit("P3 SQL scratch bytes differ from first owner-signed verified assembly")
    original=data.decode("utf8")
    revised=frame(original,source_bytes(root))
    if revised==original:
        raise SystemExit("No exact SQL terminators were inserted")
    # Atomic temp-file update, still confined to the original disposable dir.
    fd,filename=tempfile.mkstemp(prefix=".p3-6a-terminators-",dir=str(scratch.parent))
    try:
        with os.fdopen(fd,"wb") as file:
            os.chmod(file.fileno(),0o600)
            file.write(revised.encode("utf8"))
            file.flush()
            os.fsync(file.fileno())
        os.replace(filename,scratch)
    finally:
        if os.path.exists(filename):
            os.unlink(filename)
    print("P3_6A_SQL_STATEMENT_TERMINATORS=2_EXACT_PINNED_SCRATCH_ONLY")
    print("P3_6A_FRAMED_SCRATCH_SHA256="+hashlib.sha256(
        revised.encode("utf8")).hexdigest())
    print("PRODUCTION_MUTATION=NONE")

if __name__=="__main__":
    main(sys.argv)
