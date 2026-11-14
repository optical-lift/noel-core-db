#!/usr/bin/env python3
"""HELD: append a single reviewed HTTP409 candidate to a TEST_ONLY P3 scratch.

No database access, server calls, credentials, or production release.
For issue #2784 only, after immutable U2/U4/P3 + history assembly and
before the disposable validation starts. Never modify pinned source files.
"""
import hashlib
import os
from pathlib import Path
import sys
import tempfile

SCRATCH_NAME="20261107211000_atlas_uni_ops_p3_6a_TEST_ONLY.sql"
CANDIDATE_BLOB="da3ddafc8f479327df02fbe16e418eb0b094072d"
BEGIN_MARK="-- BEGIN PINNED HISTORICAL STALE HTTP409 OVERRIDE blob:"+CANDIDATE_BLOB
END_MARK="-- END PINNED HISTORICAL STALE HTTP409 OVERRIDE"

class HeldOverlayRefusal(AssertionError):
    pass

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\\0"+raw).hexdigest()

def append_only(base,candidate):
    if not isinstance(base,str) or not isinstance(candidate,bytes):
        raise HeldOverlayRefusal("Ordinary pinned scratch and SQL source required")
    if git_blob(candidate)!=CANDIDATE_BLOB:
        raise HeldOverlayRefusal("HELD candidate source pin changed")
    if (base.count("-- BEGIN PINNED STAGE ")!=18 or
        base.count("-- END PINNED STAGE ")!=18 or
        base.count("-- BEGIN PINNED P3 6A HELD STAGE ")!=8 or
        base.count("-- END PINNED P3 6A HELD STAGE ")!=8 or
        BEGIN_MARK in base or END_MARK in base):
        raise HeldOverlayRefusal("Frozen composite SQL stage count changed or duplicate overlay")
    sql=candidate.decode("utf8")
    if (sql.count("CREATE OR REPLACE FUNCTION atlas.governor_retire_historical_work_self_api_v1(")!=1
        or sql.count("RAISE SQLSTATE 'PGRST'")!=1
        or sql.count('DETAIL=\'{"status":409}\'')!=1
        or "USING ERRCODE='40001'" in sql):
        raise HeldOverlayRefusal("Stale transport candidate no longer reviewed")
    result=(base.rstrip()+"\\n\\n"+BEGIN_MARK+"\\nBEGIN;\\n"+
            sql.rstrip()+"\\nCOMMIT;\\n"+END_MARK+"\\n")
    if result.count(BEGIN_MARK)!=1 or result.count(END_MARK)!=1:
        raise HeldOverlayRefusal("Overlay not unique")
    return result

def main(argv):
    if len(argv)!=3:
        raise SystemExit("Usage: append_..._held.py ABSOLUTE_P3_TEST_ONLY.sql PINNED_CANDIDATE.sql")
    scratch=Path(argv[1])
    candidate=Path(argv[2])
    root=os.environ.get("RUNNER_TEMP")
    if not root or not Path(root).is_dir() or Path(root).is_symlink():
        raise HeldOverlayRefusal("Protected disposable runner scratch root required")
    base=Path(root).resolve()
    if (not scratch.is_absolute() or scratch.name!=SCRATCH_NAME or
        scratch.parent.resolve()!=base or scratch.is_symlink() or
        not scratch.is_file() or not candidate.is_file() or candidate.is_symlink()):
        raise HeldOverlayRefusal("Refuse non-disposable scratch or untrusted SQL file")
    data=scratch.read_bytes()
    if len(data)>30_000_000 or len(data)<2000:
        raise HeldOverlayRefusal("Unexpected composite SQL source bounds")
    new=append_only(data.decode("utf8"),candidate.read_bytes()).encode("utf8")
    fd,tmp=tempfile.mkstemp(prefix=".uniops-history-http409-",dir=str(base))
    try:
        with os.fdopen(fd,"wb") as f:
            os.chmod(f.fileno(),0o600)
            f.write(new)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp,scratch)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print("UNI_OPS_HISTORY_HTTP409_OVERLAY=PINNED_DISPOSABLE_SCRATCH_ONLY")
    print("UNI_OPS_HISTORY_HTTP409_PRODUCTION_MUTATION=NONE")

if __name__=="__main__":
    main(sys.argv)
