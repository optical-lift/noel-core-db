#!/usr/bin/env python3
"""Exact signed shared-mail disclosure acceptance on a disposable local clone.
Never contacts real Supabase, real mailboxes, or creates a production grant.
"""
import argparse
import importlib.util
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "original_event_signed",ROOT/"validate-atlas-one-event-schedule-writer-signed-http.py")
event=importlib.util.module_from_spec(spec)
spec.loader.exec_module(event)
ENDPOINT="f5ab0000-0000-4000-8000-000000000101"
SOURCE="f5ab0000-0000-4000-8000-000000000102"
BATCH="f5ab0000-0000-4000-8000-000000000103"
THREAD="f5ab0000-0000-4000-8000-000000000104"
THREAD2="f5ab0000-0000-4000-8000-000000000105"
BEFORE="f5ab0000-0000-4000-8000-000000000201"
AT="f5ab0000-0000-4000-8000-000000000202"
AFTER="f5ab0000-0000-4000-8000-000000000203"
FALLBACK="f5ab0000-0000-4000-8000-000000000204"

def assert_true(value,detail):
    if not value: raise AssertionError(detail)

def signed(api,key,token,name,params):
    return event.request(api,key,"/rest/v1/rpc/"+name,params,token)

def accepted(api,key,token,name,params):
    code,obj=signed(api,key,token,name,params)
    assert_true(code==200 and isinstance(obj,dict) and obj.get("ok") is True,
                f"{name} signed success unavailable: {code} {str(obj)[:420]}")
    return obj

def denied(api,key,token,name,params,label):
    code,obj=signed(api,key,token,name,params)
    assert_true(code in (401,403) and isinstance(obj,dict)
                and (token is None or obj.get("code")=="42501"),
                f"{label} needs actual denial (never a 404): {code} {str(obj)[:350]}")
    print("PASS",label)

def seed(db):
    fixture=ROOT.parent/"validation/fixtures/20261022195549_atlas_one_event_schedule_writer_v1.sql"
    subprocess.run(["psql",db,"-X","-v","ON_ERROR_STOP=1","-f",str(fixture)],
                   check=True,capture_output=True,text=True)
    event.sql(db,f"""UPDATE atlas.ledger_organization_participations
      SET participation_kind='governing',is_compatibility_primary=true
      WHERE ledger_id='{event.LEDGER}'::uuid AND organization_id='{event.ORG}'::uuid""")
    event.sql(db,f"""INSERT INTO atlas.communication_endpoints
      (id,organization_id,endpoint_kind,address,address_normalized,display_name)
      VALUES('{ENDPOINT}','{event.ORG}','email',
        'hello@fictional-mail.invalid','hello@fictional-mail.invalid','Synthetic Shared Mail')""")
    event.sql(db,f"""INSERT INTO atlas.connected_sources
      (id,custodian_organization_id,provider_key,provider_account_key,display_label)
      VALUES('{SOURCE}','{event.ORG}','fake_mail','mail-probe-only','Synthetic Closed Mail')""")
    event.sql(db,f"""INSERT INTO atlas.communication_ingest_batches
      (id,organization_id,connected_source_id,capture_mode,supplied_count,admitted_count)
      VALUES('{BATCH}','{event.ORG}','{SOURCE}','live_relay',4,4)""")
    for thread,title in ((THREAD,"Private old subject"),(THREAD2,"Recent unrelated subject")):
        event.sql(db,f"""INSERT INTO atlas.communication_conversations
          (id,organization_id,stable_key,subject)
          VALUES('{thread}','{event.ORG}','synthetic-mail-{thread}','{title}')""")
    rows=[
       (BEFORE,THREAD,"2026-08-28 04:59:59+00","Hidden pre-cutoff message","Old classified body",False),
       (AT,THREAD,"2026-08-28 05:00:00+00","Cutoff allowed reply","Visible boundary body",False),
       (AFTER,THREAD2,"2026-09-04 11:00+00","Later admitted message","Visible later body",False),
       (FALLBACK,THREAD,"2026-10-27 18:00+00","Unverified date source","Excluded fallback body",True),
    ]
    for i,(eid,thread,stamp,subject,body,is_fallback) in enumerate(rows):
        captured=stamp if is_fallback else "2026-10-27 21:00+00"
        event.sql(db,f"""INSERT INTO atlas.communication_events(
          id,organization_id,connected_source_id,ingest_batch_id,
          source_event_ref,occurred_at,captured_at,direction,speaker_is_self,
          speaker_address,body,body_state,source_content_hash,custody_source_hash,
          canonical_event)
        VALUES('{eid}','{event.ORG}','{SOURCE}','{BATCH}',
          'synthetic-mail-{i}','{stamp}'::timestamptz,'{captured}'::timestamptz,
          'incoming',false,'writer@example.invalid','{body}','exact_text',
          repeat('{i+1}',64),repeat('{i+1}',64),
          jsonb_build_object('captureMode','live_relay',
            'source',jsonb_build_object('kind','email'),
            'subject','{subject}','occurredAt','{stamp}'::text,
            'capturedAt','{captured}'::text))""")
        event.sql(db,f"""INSERT INTO atlas.communication_conversation_events
            (communication_conversation_id,communication_event_id,
             communication_endpoint_id,continuity_basis,occurred_at)
             VALUES('{thread}','{eid}','{ENDPOINT}','synthetic_original_email','{stamp}'::timestamptz)""")

def authenticate(db):
    api,key=event.local_endpoint()
    for uid,suffix in ((event.MEMBER,"member"),(event.OUTSIDER,"outsider"),(event.ROOT,"root")):
        addr=f"atlas-mail-{suffix}@example.invalid"
        fake='{"is_owner":true,"role":"root_governing"}' if suffix=="member" else "{}"
        event.sql(db,f"""UPDATE auth.users SET
          instance_id='00000000-0000-0000-0000-000000000000',
          email='{addr}',
          encrypted_password=extensions.crypt('{event.PASSWORD}',extensions.gen_salt('bf')),
          email_confirmed_at=now(),confirmation_token='',recovery_token='',
          email_change='',email_change_token_new='',email_change_token_current='',
          phone_change='',phone_change_token='',reauthentication_token='',
          raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
          raw_user_meta_data='{fake}'::jsonb
          WHERE id='{uid}'::uuid""")
        event.sql(db,f"""INSERT INTO auth.identities
          (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES(gen_random_uuid(),'{addr}','{uid}'::uuid,
          jsonb_build_object('sub','{uid}','email','{addr}'),'email',now(),now())""")
    event.sql(db,"notify pgrst, 'reload schema'")
    identities={}
    for uid,suffix in ((event.MEMBER,"member"),(event.OUTSIDER,"outsider"),(event.ROOT,"root")):
        token,claims=event.signed_session(api,key,f"atlas-mail-{suffix}@example.invalid")
        assert_true(claims.get("sub")==uid and claims.get("session_id"),
                    "Person mismatch for signed "+suffix)
        assert_true(event.sql(db,f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
                    "Signed session missing durable GoTrue receipt")
        identities[suffix]=token
    return api,key,identities

def read(api,key,token):
    return accepted(api,key,token,"person_mail_events_self_v1",
      dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None))

def decide(api,key,token,enabled,action,date="2026-08-28"):
    return signed(api,key,token,"set_person_mail_read_self_v1",dict(
      p_endpoint_id=ENDPOINT,p_ledger_id=event.LEDGER,
      p_target_person_id=event.MEMBER_PERSON,
      p_start_date=date if enabled else None,
      p_timezone="America/Chicago" if enabled else None,
      p_enabled=enabled,p_action_id=action,
      p_reason="Explicit synthetic governor time-bounded shared-mail disclosure"))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    opts=parser.parse_args()
    assert_true(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",opts.db_url),
                "This test categorically refuses production or network databases")
    seed(opts.db_url)
    api,key,tokens=authenticate(opts.db_url)
    member=tokens["member"];root=tokens["root"];outsider=tokens["outsider"]
    denied(api,key,member,"person_mail_events_self_v1",
           dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None),
           "Member's native Ledger seat alone cannot read mail")
    denied(api,key,outsider,"person_mail_events_self_v1",
           dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None),
           "Outsider cannot read institutional mailbox")
    denied(api,key,None,"person_mail_events_self_v1",
           dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None),
           "Anonymous caller cannot read mailbox")
    code,out=decide(api,key,member,True,"f5ab0000-0000-4000-8000-000000000301")
    assert_true(code in (401,403) and isinstance(out,dict) and out.get("code")=="42501",
                f"Ordinary member forged governor: {code} {str(out)[:220]}")
    choices=accepted(api,key,root,"person_mail_governor_choices_self_v1",{})
    assert_true(any(x.get("endpointId")==ENDPOINT for x in choices.get("items",[])),
                "Governing root cannot discover shared address")
    root_receipt_code,root_receipt=decide(api,key,root,True,"f5ab0000-0000-4000-8000-000000000302")
    assert_true(root_receipt_code==200 and root_receipt.get("ok") is True,
                f"Real signed governor cannot grant read: {root_receipt_code} {root_receipt}")
    assert_true(root_receipt.get("earliestEventAt")=="2026-08-28T05:00:00+00:00",
                "Inclusive America/Chicago date offset disagrees with cutoff")
    shown=read(api,key,member)
    ids=[m.get("eventId") for m in shown.get("items",[])]
    assert_true(set(ids)=={AT,AFTER} and BEFORE not in ids and FALLBACK not in ids,
                f"Date or fallback leaked: {ids}")
    assert_true(not any("Old classified body" in str(x) or "Private old subject" in str(x)
                for x in shown.get("items",[])), "Original pre-cutoff thread leaked")
    assert_true(shown.get("readOnly") is True and shown.get("attachmentsDisclosed") is False,
                "Read projection improperly grants attachments or operation rights")
    # Person's grant never makes obsolete institutional membership readers accessible.
    denied(api,key,member,"institutional_shared_inbox_self_v3",
           dict(p_communication_endpoint_id=ENDPOINT,p_limit=100),
           "Old institutional reader not a backdoor")
    # Broad organization membership or forged editable JWT metadata cannot grant mail to outsider.
    denied(api,key,outsider,"person_mail_events_self_v1",
           dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None),
           "Outsider remains denied after someone else gained access")
    narrow_code,narrow=decide(api,key,root,True,"f5ab0000-0000-4000-8000-000000000303",
                              date="2026-09-01")
    assert_true(narrow_code==200 and narrow.get("ok") is True,"Root date narrowing denied")
    assert_true([x.get("eventId") for x in read(api,key,member).get("items",[])]==[AFTER],
                "Changing date failed to remove the original boundary message")
    revoke_code,revoke=decide(api,key,root,False,"f5ab0000-0000-4000-8000-000000000304")
    assert_true(revoke_code==200 and revoke.get("ok") is True,"Owner revoke failed")
    denied(api,key,member,"person_mail_events_self_v1",
           dict(p_endpoint_id=ENDPOINT,p_limit=100,p_before_at=None,p_before_id=None),
           "Revoked Person cannot fetch even a cached pagination cursor")
    assert_true(event.sql(opts.db_url,
                "select count(*) from atlas.communication_person_mail_read_decisions_v1")=="3",
                "Immutable decision history not preserved")
    Path(opts.output).write_text(
      "PASS true signed root grants; connected Person cutoff and narrowing; outsider, anonymous, legacy reader and revoked denials; synthetic source unchanged.\n")
    print("PASS native Person shared-mail signed acceptance on disposable clone")

if __name__=="__main__":main()
