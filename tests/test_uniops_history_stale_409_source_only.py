#!/usr/bin/env python3
"""Source-only held historic governor HTTP transport review. NEVER contacts DB.

Compare an isolated proposed version against the original frozen #2368
function. The only permitted semantic delta is stale-preflight error transport.
No signed history PASS or authorization to apply SQL.
"""
import argparse
import hashlib
from pathlib import Path

PINNED_BLOB="93f7b9cf0bad5eb536ffa90d3973aabfe75542d9"
START="CREATE OR REPLACE FUNCTION atlas.governor_retire_historical_work_self_api_v1("
END="REVOKE ALL ON FUNCTION atlas.governor_retire_historical_work_self_api_v1("
OLD="""RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
   USING ERRCODE='40001'; END IF;"""
NEW="""RAISE SQLSTATE 'PGRST' USING
     MESSAGE='{"code":"40001","message":"Retirement preflight stale; refresh impact"}',
     DETAIL='{"status":409}'; END IF;"""
HEADER="""-- HELD / SOURCE-ONLY CANDIDATE, NOT A MIGRATION OR PRODUCTION RELEASE.
-- Replace only stale-token HTTP transport in the exact frozen 20_ governor
-- source for a future separately authorized synthetic clone. Preserve the
-- existing legacy client-visible "40001" code, while replacing dangerous
-- PostgreSQL serialization-failure SQLSTATE with PostgREST custom status 409.
-- The source-review test requires a byte-exact delta against frozen #2368.
-- This candidate MUST NOT be applied to production by itself; requires full
-- reviewed migration and signed negative actor/rollback/clean replay proof.
"""

class SourceRefusal(AssertionError):
    """Fixed safe refusal: never report SQL or actor details."""

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()

def verify(original_bytes,candidate_text):
    if not isinstance(original_bytes,bytes) or git_blob(original_bytes)!=PINNED_BLOB:
        raise SourceRefusal("Frozen governor source SHA changed")
    old=original_bytes.decode("utf8")
    if old.count(START)!=1 or old.count(END)!=1 or old.count(OLD)!=1:
        raise SourceRefusal("Frozen governor SQL structure changed")
    function=START+old.split(START,1)[1].split(END,1)[0]
    if not function.endswith("\n") or function.count("USING ERRCODE='40001'")!=1:
        raise SourceRefusal("Frozen error scope not unique")
    expected=HEADER+function.replace(OLD,NEW,1)
    if candidate_text!=expected:
        raise SourceRefusal("Candidate differs outside exact stale-token branch")
    if candidate_text.count("RAISE SQLSTATE 'PGRST'")!=1:
        raise SourceRefusal("Expected one PostgREST custom error")
    if candidate_text.count('DETAIL=\'{"status":409}\'')!=1:
        raise SourceRefusal("Expected only one HTTP 409 status")
    if "ERRCODE='40001'" in candidate_text:
        raise SourceRefusal("Serialization failure SQLSTATE not eliminated")
    if any(s in candidate_text.lower() for s in
           ("alter table","drop function","create policy","grant execute",
            "disable row level security","set role","begin;","commit;")):
        raise SourceRefusal("Held candidate cannot change privileges or schema")
    return True

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--frozen",type=Path,required=True)
    parser.add_argument("--candidate",type=Path,required=True)
    args=parser.parse_args()
    if not args.frozen.is_file() or not args.candidate.is_file():
        raise SourceRefusal("Exact checked-out source files required")
    original=args.frozen.read_bytes()
    candidate=args.candidate.read_text(encoding="utf8")
    assert verify(original,candidate)
    for corrupted in (candidate.replace("409","200",1),
                      candidate.replace('"code":"40001"','"code":"PT409"',1),
                      candidate.replace("company_work_native_ledger_owner_self_v1",
                                        "fictional_unsupported_actor",1),
                      candidate.replace("apply_work_lifecycle_transition_internal_v1",
                                        "unreviewed_work_writer",1),
                      candidate.replace("md5(v_impact::text)","true",1),
                      candidate+"\nGRANT EXECUTE TO anon;"):
        try:
            verify(original,corrupted)
        except SourceRefusal:
            pass
        else:
            raise SourceRefusal("Unreviewed candidate mutation was accepted")
    print("PASS source-only exact frozen governor stale-error HTTP 409 candidate; NO RUN")

if __name__=="__main__":
    main()
