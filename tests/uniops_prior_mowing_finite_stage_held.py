#!/usr/bin/env python3
"""HELD TEST ONLY: decorate an already-pinned prior-mowing signed DRIVER COPY.

Retains the entire SQL and prior-mowing fixture untouched. Adds only an
allowlisted, non-sensitive phase marker immediately BEFORE each frozen fixture
statement. This identifies where a future owner-approved disposable run stops
without printing SQL, row data, actor secrets, psql stderr or exceptions.

Input/output are ordinary non-symlink files under the explicit ephemeral
RUNNER_TEMP; no database, HTTP, actor or protected action is invoked here.
"""
import argparse
import ast
from pathlib import Path
import os

SEED_ANCHOR="    _legacy.install(a.db_url,sql)\n    _legacy_initial=_legacy.capture(a.db_url,sql)\n"
SAFE_OUTPUT="validate-uniops-prior-mowing-staged-local-only.py"
STAGE_PATCH='''    # No SQL semantic change: finite fixture phase markers before source calls.
    # The first successfully entered phase that lacks its successor localizes
    # the exception without releasing SQL, data, secret or Python stack trace.
    print("UNI_OPS_PRIOR_MOWING_PHASE=install_entered",flush=True)
    _prior_mowing_stage=["before_census"]
    def _prior_mowing_traced_sql(_db,_statement):
        _current=_prior_mowing_stage[0]
        if _current=="before_census" and _statement==_legacy.NONCARRIER_CENSUS_SQL:
            _next="before_census_called"
        elif _current=="before_census_called" and _statement==_legacy.INSTALL_SQL:
            _next="physical_seed_called"
        elif _current=="physical_seed_called" and _statement==_legacy.NONCARRIER_CENSUS_SQL:
            _next="after_census_called"
        else:
            raise _legacy.PriorMowingRefusal("Unexpected prior-mowing fixture SQL call order")
        _prior_mowing_stage[0]=_next
        print("UNI_OPS_PRIOR_MOWING_PHASE="+_next,flush=True)
        return sql(_db,_statement)
    _legacy.install(a.db_url,_prior_mowing_traced_sql)
    check(_prior_mowing_stage[0]=="after_census_called",
          "Prior mowing source census was incomplete")
    print("UNI_OPS_PRIOR_MOWING_PHASE=fixture_install_complete",flush=True)
    print("UNI_OPS_PRIOR_MOWING_PHASE=initial_capture_called",flush=True)
    _legacy_initial=_legacy.capture(a.db_url,sql)
    print("UNI_OPS_PRIOR_MOWING_PHASE=initial_capture_complete",flush=True)
'''
ALLOWLIST=(
    "install_entered","before_census_called","physical_seed_called",
    "after_census_called","fixture_install_complete","initial_capture_called",
    "initial_capture_complete",
)

class FiniteStageRefusal(AssertionError):
    pass

def inject(source):
    if not isinstance(source,bytes):
        raise FiniteStageRefusal("Immutable exact driver bytes required")
    try:
        text=source.decode("utf8")
    except UnicodeError:
        raise FiniteStageRefusal("Invalid signed-driver encoding") from None
    if text.count(SEED_ANCHOR)!=1:
        raise FiniteStageRefusal("Prior-mowing frozen seed anchor missing/ambiguous")
    if ("UNI_OPS_PRIOR_MOWING_PHASE=" in text
        or text.count("UNI_OPS_PRIOR_MOWING_FIXTURE=SEEDED_BEFORE_GOVERNANCE")!=1
        or text.count("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")!=1
        or text.count("_legacy.require_preserved(")!=1):
        raise FiniteStageRefusal("Signed legacy composer custody changed")
    output=text.replace(SEED_ANCHOR,STAGE_PATCH,1)
    ast.parse(output)
    if output.count("UNI_OPS_PRIOR_MOWING_PHASE=")!=7:
        raise FiniteStageRefusal("Finite stage cardinality changed")
    return output.encode("utf8")

def extract_stage(logtext):
    """Return ONLY the final allowlisted marker, never a private log substring."""
    if not isinstance(logtext,str):
        return "not_reported"
    observed=[]
    prefix="UNI_OPS_PRIOR_MOWING_PHASE="
    for line in logtext.splitlines():
        if line.startswith(prefix):
            phase=line[len(prefix):]
            if phase in ALLOWLIST:
                observed.append(phase)
            else:
                return "untrusted_marker"
    return observed[-1] if observed else "not_reported"

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--source",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    args=parser.parse_args()
    root=os.environ.get("RUNNER_TEMP")
    if not root or not Path(root).is_dir():
        raise FiniteStageRefusal("Ephemeral runner scratch required")
    parent=Path(root).resolve()
    if not args.source.is_file() or args.source.is_symlink():
        raise FiniteStageRefusal("No reviewed signed driver input")
    if (not args.output.is_absolute() or args.output.parent.resolve()!=parent
        or args.output.name!=SAFE_OUTPUT or args.output.exists()):
        raise FiniteStageRefusal("Exact new disposable stage driver output required")
    prepared=inject(args.source.read_bytes())
    with args.output.open("xb") as stream:
        stream.write(prepared)
    os.chmod(args.output,0o600)
    print("PASS finite prior mowing staged-driver SOURCE ONLY; NO SQL, ACTOR OR SIGNED RUN")

if __name__=="__main__":
    main()
