-- Run against disposable clone after migration, then read-only production.
do $verify$
declare
  v_fn text;
begin
  if to_regclass('atlas.person_contact_inquiry_intents') is null then
    raise exception 'Private inquiry source substrate missing';
  end if;
  if not (select c.relrowsecurity and c.relforcerowsecurity
    from pg_class c where c.oid='atlas.person_contact_inquiry_intents'::regclass) then
    raise exception 'Private inquiry source row security disabled';
  end if;
  if has_table_privilege('anon','atlas.person_contact_inquiry_intents','SELECT')
    or has_table_privilege('authenticated','atlas.person_contact_inquiry_intents','SELECT')
    or has_table_privilege('service_role','atlas.person_contact_inquiry_intents','INSERT') then
    raise exception 'Inquiry raw data granted to an API role';
  end if;
  if not exists(select 1 from pg_trigger t
    where t.tgrelid='atlas.person_contact_inquiry_intents'::regclass
      and t.tgname='person_inquiry_source_immutable_v1' and t.tgenabled='O') then
    raise exception 'Immutable source evidence trigger missing';
  end if;
  if not has_function_privilege('authenticated',
    'public.create_person_contact_inquiry_intent_owner_self_api_v1(uuid,text,text,text,text,text,uuid)',
    'EXECUTE') or has_function_privilege('anon',
    'public.create_person_contact_inquiry_intent_owner_self_api_v1(uuid,text,text,text,text,text,uuid)',
    'EXECUTE') or has_function_privilege('anon',
    'public.person_contact_inquiry_intent_owner_self_api_v1(uuid,uuid)','EXECUTE') then
    raise exception 'Unauthenticated Person intake access or missing signed-in action';
  end if;
  v_fn:=pg_get_functiondef(
    'atlas.create_person_contact_inquiry_intent_owner_self_api_v1(uuid,text,text,text,text,text,uuid)'::regprocedure);
  if position('principal_has_ledger_authority_v1' in v_fn)=0
    or position('current_active_ledger_seat_v1' in v_fn)=0
    or position('source_record_state' in v_fn)=0
    or position('messageSent' in v_fn)=0
    or position('hashtextextended' in v_fn)=0 then
    raise exception 'Canonical owner, source, idempotency, or no-send contract missing';
  end if;
  if exists(select 1 from atlas.person_contact_inquiry_intents) then
    raise exception 'Source-only deployment inserted real private inquiry records';
  end if;
end $verify$;
select 'atlas_person_contact_inquiry_source_intent_v1' as contract,
  count(*) as private_inquiry_records from atlas.person_contact_inquiry_intents;
