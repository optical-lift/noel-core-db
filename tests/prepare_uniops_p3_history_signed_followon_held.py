#!/usr/bin/env python3
"""HELD SOURCE ONLY: compose existing historical governor proof AFTER P3 signed mowing.

Must begin with the IMMUTABLE U2 driver and #2368 historical source companion.
Reuses Noel's already source-reviewed history follow-on patch. Adds read-only,
source-pinned P3 snapshot checks immediately around governor retirement.
Never executes this driver here. A NEW and separately authorized owner-only
disposable clone is required before claiming ANY new signed history PASS.
"""
import argparse
import hashlib
import os
from pathlib import Path
import sys

import prepare_uniops_historical_retirement_signed_followon_held as original

PREPARER_BLOB="6ff245eb3c2c3ce007b0a0a59e1d382d7ae0d519"
GUARD_BLOB="a0ab7523f10e9b79d3290871fd5faac777e6e733"
P3_HOOK_BLOB="4efef70ea67209b04def420aade39b8a6fd44f38"
COMPAT_BLOB="7bcd3719aeea3e150770fe4bb4172416a815a38c"
SAFE_OUTPUT="validate-uniops-p3-historical-signed-local-only.py"

HISTORY_START="        history_receipt=hist.prove(\n"
HISTORY_SUCCESS='        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"\n'
HISTORY_PRE='''        # Test-only: capture exact completed mowing source in this same
        # disposable organization, before any separate historic cancellation.
        _p3_spec=importlib.util.spec_from_file_location(
            "uniops_p3_6a_snapshot_hook_held",
            ROOT/"tests"/"uniops_p3_6a_snapshot_hook_held.py")
        check(_p3_spec is not None and _p3_spec.loader is not None,
              "Pinned signed P3 snapshot hook missing")
        _p3=importlib.util.module_from_spec(_p3_spec)
        _p3_spec.loader.exec_module(_p3)
        _pres_spec=importlib.util.spec_from_file_location(
            "uniops_p3_historical_preservation_check_held",
            ROOT/"tests"/"uniops_p3_historical_preservation_check_held.py")
        check(_pres_spec is not None and _pres_spec.loader is not None,
              "Pinned P3 historical preservation guard missing")
        _pres=importlib.util.module_from_spec(_pres_spec)
        _pres_spec.loader.exec_module(_pres)
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=pre_snapshot_started",flush=True)
        _mowing_before_history=_p3.capture(
            a.db_url,sql,_p3.ORG,_p3.STATE,new_work,"replay")
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=pre_snapshot_captured",flush=True)
        # The historical source companion stays immutable. Adapt ONLY its
        # fictional seed through a separately SHA-pinned Person-root wrapper.
        # Retain original fictional member INSERT if absent; reuse exact
        # existing canonical membership if present; refuse conflicting roots.
        # Only the frozen fictional self_adoption allocation is adapted to
        # current governed synthetic responsibility provenance, not real consent.
        from hashlib import sha1 as _sha1
        _compat_path=ROOT/"tests"/"uniops_p3_history_existing_membership_seed_held.py"
        check(_compat_path.is_file() and not _compat_path.is_symlink(),
              "Reviewed history Person-root source missing")
        _compat_bytes=_compat_path.read_bytes()
        check(_sha1(b"blob "+str(len(_compat_bytes)).encode("ascii")+b"\\0"+
                    _compat_bytes).hexdigest()=="7bcd3719aeea3e150770fe4bb4172416a815a38c",
              "History Person-root source pin changed")
        _compat_spec=importlib.util.spec_from_file_location(
            "uniops_p3_history_existing_membership_seed_held",_compat_path)
        check(_compat_spec is not None and _compat_spec.loader is not None,
              "History Person-root fixture adapter unavailable")
        _compat=importlib.util.module_from_spec(_compat_spec)
        _compat_spec.loader.exec_module(_compat)
        _history_fixture_c1=_compat.adapter(base.c1,sql)
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=fixture_adapter_ready",flush=True)
'''
HISTORY_POST='''        print("UNI_OPS_HISTORY_HANDOFF_STAGE=governor_returned",flush=True)
        _mowing_after_history=_p3.capture(
            a.db_url,sql,_p3.ORG,_p3.STATE,new_work,"replay")
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=conservation_started",flush=True)
        check(_pres.require_preserved(_mowing_before_history,
                                     _mowing_after_history) is True,
              "Governed mowing Work/Need changed during separate historic retirement")
        print("UNI_OPS_HISTORY_HANDOFF_STAGE=conservation_verified",flush=True)
        print("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS",flush=True)
        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"
'''

HISTORY_TRACE='''        # Held signed-history trace: public fixed enums only. No SQL, user ids,
        # paths, RPC payload, raw error, JWT or actor credentials are emitted.
        _history_sql_number=[0]
        _history_rpc_number=[0]
        _history_rpc_ops={
            "governor_link_historical_self_adoption_self_api_v1":"link",
            "governor_review_historical_self_adoption_self_api_v1":"review",
            "governor_historical_retirement_preflight_self_api_v1":"preflight",
            "governor_retire_historical_work_self_api_v1":"retire"
        }
        _history_roles={owner:"owner",worker:"worker",outsider:"outsider",
                        signed["no-seat"][0]:"no_seat"}
        def _history_sql_probe(_db,_statement):
            _history_sql_number[0]+=1
            _n=_history_sql_number[0]
            check(1<=_n<=18,"Historical diagnostic SQL count outside fixed source")
            _tag="sql_%02d" % _n
            print("UNI_OPS_HISTORY_CALL_STAGE="+_tag+"_started",flush=True)
            _result=sql(_db,_statement)
            print("UNI_OPS_HISTORY_CALL_STAGE="+_tag+"_returned",flush=True)
            return _result
        def _history_rpc_probe(_api,_key,_token,_name,_params):
            _history_rpc_number[0]+=1
            _n=_history_rpc_number[0]
            _op=_history_rpc_ops.get(_name)
            _role=_history_roles.get(_token)
            check(1<=_n<=18 and _op is not None and _role is not None,
                  "Unrecognized signed history RPC diagnostic source")
            _tag="rpc_%02d_%s_%s" % (_n,_op,_role)
            print("UNI_OPS_HISTORY_CALL_STAGE="+_tag+"_started",flush=True)
            _status,_payload=rpc(_api,_key,_token,_name,_params)
            # Explicit transport categories differentiate PostgREST custom
            # error parsing (PGRST121) from SQLSTATE 40001 mapping; neither
            # result is accepted as a signed success without the original proof.
            _http={200:"ok",400:"bad_request",401:"unauthorized",
                   403:"forbidden",404:"not_found",409:"conflict",
                   422:"unprocessable",429:"rate_limited",
                   500:"internal_error",502:"bad_gateway",
                   503:"unavailable",504:"gateway_timeout"}.get(_status,"other")
            _code=_payload.get("code") if isinstance(_payload,dict) else None
            _error={"42501":"permission_denied","40001":"stale_snapshot",
                    "23514":"source_constraint","23505":"source_conflict",
                    "42883":"missing_function",
                    "PGRST121":"postgrest_custom_json_invalid",
                    "PGRST202":"postgrest_function_cache_missing",
                    "PGRST":"postgrest_custom_unparsed",
                    "PT409":"postgrest_native_conflict"}.get(
                        _code,"other" if _code is not None else "none")
            print("UNI_OPS_HISTORY_CALL_HTTP_CLASS="+_http,flush=True)
            print("UNI_OPS_HISTORY_CALL_ERROR_CLASS="+_error,flush=True)
            print("UNI_OPS_HISTORY_CALL_STAGE="+_tag+"_returned",flush=True)
            return _status,_payload
'''
class P3HistoricalRefusal(RuntimeError):
    pass

def git_blob(payload):
    return hashlib.sha1(b"blob "+str(len(payload)).encode()+b"\0"+payload).hexdigest()

def prepare(driver,bridge,companion,guard,hook,preparer,compat):
    for data,pin,label in (
        (preparer,PREPARER_BLOB,"historical preparer"),
        (guard,GUARD_BLOB,"P3 preservation guard"),
        (hook,P3_HOOK_BLOB,"signed P3 snapshot source"),
        (compat,COMPAT_BLOB,"Person-root historical seed compatibility")):
        if not isinstance(data,bytes) or git_blob(data)!=pin:
            raise P3HistoricalRefusal("Reviewed "+label+" source drift")
    # The existing history preparer authenticates ALL THREE genuine source
    # blobs before producing one copy. It already rejects source tampering.
    prepared=original.prepare(driver,bridge,companion).decode("utf8")
    if prepared.count(HISTORY_START)!=1 or prepared.count(HISTORY_SUCCESS)!=1:
        raise P3HistoricalRefusal("Original signed history driver insertion drift")
    if "UNI_OPS_P3_MOWING_AFTER_HISTORY" in prepared:
        raise P3HistoricalRefusal("History preservation already inserted")
    prepared=prepared.replace(HISTORY_START,HISTORY_PRE+HISTORY_TRACE+
        '        print("UNI_OPS_HISTORY_HANDOFF_STAGE=governor_started",flush=True)\n'+
        HISTORY_START,1)
    tail="sql=sql,rpc=rpc,c1=base.c1)"
    if prepared.count(tail)!=1:
        raise P3HistoricalRefusal("Historical signed actor adapter anchor drift")
    prepared=prepared.replace(tail,
        "sql=_history_sql_probe,rpc=_history_rpc_probe,c1=_history_fixture_c1)",1)
    prepared=prepared.replace(HISTORY_SUCCESS,HISTORY_POST,1)
    for tok in ("--historical-retirement-followon",
                "_mowing_before_history=_p3.capture",
                "history_receipt=hist.prove",
                "_mowing_after_history=_p3.capture",
                "_pres.require_preserved",
                "_history_fixture_c1=_compat.adapter",
                "c1=_history_fixture_c1)",
                "def _history_sql_probe(_db,_statement):",
                "def _history_rpc_probe(_api,_key,_token,_name,_params):",
                "UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"):
        if prepared.count(tok)!=1:
            raise P3HistoricalRefusal("Historical signed source composition not unique")
    return prepared.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    for arg in ("driver","bridge","companion","guard","p3-hook","preparer","compat","output"):
        p.add_argument("--"+arg,required=True,type=Path)
    a=p.parse_args()
    runner=os.environ.get("RUNNER_TEMP")
    if not runner or not Path(runner).is_dir():
        raise P3HistoricalRefusal("Explicit runner scratch required")
    out=a.output
    root=Path(runner).resolve()
    if (not out.is_absolute() or out.parent.resolve()!=root
            or out.name!=SAFE_OUTPUT or out.exists()):
        raise P3HistoricalRefusal("Exact new disposable driver file required")
    inputs=[a.driver,a.bridge,a.companion,a.guard,a.p3_hook,a.preparer,a.compat]
    if any(not inp.is_file() or inp.is_symlink() for inp in inputs):
        raise P3HistoricalRefusal("Reviewed ordinary input file missing")
    data=prepare(*(i.read_bytes() for i in inputs))
    with out.open("xb") as file:
        file.write(data)
    os.chmod(out,0o600)
    print("PASS source-only composite P3 plus separately approved governor history; NO SIGNED RUN")

if __name__=="__main__":
    main()
