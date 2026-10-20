begin;

-- Option C packet 1: private source observation / contact intent ONLY.
-- No Person match, outgoing correspondence, email challenge, Ledger relation,
-- account invitation, employee status, Work assignment or access is made.

create table atlas.person_contact_inquiry_intents (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid references atlas.organizations(id) on delete restrict,
  requested_by_person_id uuid not null references reality.entities(id) on delete restrict,
  source_party_record_id uuid,
  request_key text not null,
  observed_email text not null,
  observed_person_label text,
  purpose text not null,
  relationship_question text not null,
  intake_state text not null default 'pending_source_resolution',
  observed_at timestamptz not null default now(),
  constraint inquiry_source_scope_v1 foreign key(ledger_id,source_party_record_id)
    references atlas.ledger_source_party_records(ledger_id,id) on delete restrict,
  constraint inquiry_request_key_v1 check(length(request_key) between 8 and 120
    and request_key ~ '^[A-Za-z0-9_-]+$'),
  constraint inquiry_email_v1 check(length(observed_email) between 5 and 320
    and observed_email=lower(btrim(observed_email))
    and observed_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  constraint inquiry_person_label_v1 check(observed_person_label is null
    or length(btrim(observed_person_label)) between 1 and 200),
  constraint inquiry_purpose_v1 check(length(btrim(purpose)) between 12 and 1200),
  constraint inquiry_question_v1 check(length(btrim(relationship_question)) between 8 and 800),
  constraint inquiry_initial_state_v1 check(intake_state='pending_source_resolution'),
  constraint inquiry_exact_replay_v1 unique(ledger_id,requested_by_person_id,request_key)
);
comment on table atlas.person_contact_inquiry_intents is
 'Private Ledger source observation, not identity proof, contactability, a send instruction, affiliation, employment, credential, permission or execution grant.';
create index inquiry_recent_owner_v1 on atlas.person_contact_inquiry_intents
  (ledger_id,requested_by_person_id,observed_at desc);
create index inquiry_recent_address_v1 on atlas.person_contact_inquiry_intents
  (ledger_id,observed_email,observed_at desc);
alter table atlas.person_contact_inquiry_intents enable row level security;
alter table atlas.person_contact_inquiry_intents force row level security;
revoke all on table atlas.person_contact_inquiry_intents
  from public,anon,authenticated,service_role;

create function atlas.prevent_person_inquiry_source_rewrite_v1()
returns trigger language plpgsql security invoker set search_path to ''
as $fn$
begin
  raise exception 'Source observations must not be rewritten' using errcode='23514';
end $fn$;
revoke all on function atlas.prevent_person_inquiry_source_rewrite_v1()
  from public,anon,authenticated,service_role;
create trigger person_inquiry_source_immutable_v1 before update or delete
on atlas.person_contact_inquiry_intents for each row
execute function atlas.prevent_person_inquiry_source_rewrite_v1();

create function atlas.create_person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id uuid,p_request_key text,p_observed_email text,p_purpose text,
  p_relationship_question text,p_observed_person_label text default null,
  p_source_party_record_id uuid default null
) returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_person uuid; v_principal uuid; v_org uuid;
  v_key text:=btrim(coalesce(p_request_key,''));
  v_email text:=lower(btrim(coalesce(p_observed_email,'')));
  v_purpose text:=btrim(coalesce(p_purpose,''));
  v_question text:=btrim(coalesce(p_relationship_question,''));
  v_label text:=nullif(btrim(coalesce(p_observed_person_label,'')),'');
  v_existing atlas.person_contact_inquiry_intents%rowtype;
  v_new uuid;
begin
  if auth.uid() is null
    or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
    raise exception 'Authenticated Atlas Person required' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_principal:=atlas.current_principal_id_v1();
  if v_person is null or v_principal is null or
     not atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id) then
    raise exception 'Root governing Ledger Principal required' using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  select l.organization_id into v_org from atlas.ledgers l
    where l.id=p_ledger_id and l.status='active';
  if not found then raise exception 'Active Ledger required' using errcode='42501'; end if;
  if length(v_key) not between 8 and 120
    or v_key !~ '^[A-Za-z0-9_-]+$'
    or length(v_email) not between 5 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or length(v_purpose) not between 12 and 1200
    or length(v_question) not between 8 and 800
    or (v_label is not null and length(v_label)>200) then
    raise exception 'Valid email, purpose, relationship question and key required'
      using errcode='22023';
  end if;
  if p_source_party_record_id is not null and not exists (
    select 1 from atlas.ledger_source_party_records s
    where s.ledger_id=p_ledger_id and s.id=p_source_party_record_id
      and s.source_record_state='current'
  ) then
    raise exception 'Source record does not belong to active Ledger source'
      using errcode='23503';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'person-inquiry:'||p_ledger_id::text||':'||v_person::text,0));
  select * into v_existing from atlas.person_contact_inquiry_intents i
    where i.ledger_id=p_ledger_id and i.requested_by_person_id=v_person
      and i.request_key=v_key;
  if v_existing.id is not null then
    if v_existing.observed_email is distinct from v_email or
      v_existing.purpose is distinct from v_purpose or
      v_existing.relationship_question is distinct from v_question or
      v_existing.observed_person_label is distinct from v_label or
      v_existing.source_party_record_id is distinct from p_source_party_record_id then
      raise exception 'Idempotency key reused for different observation' using errcode='23505';
    end if;
    return jsonb_build_object('inquiryId',v_existing.id,'changed',false,
      'state',v_existing.intake_state,'personFound',null,
      'contactPermitted',null,'messageSent',false,'relationshipEstablished',false);
  end if;
  if (select count(*) from atlas.person_contact_inquiry_intents i
    where i.ledger_id=p_ledger_id and i.requested_by_person_id=v_person
      and i.observed_at>=now()-interval '1 day')>=25 then
    raise exception 'Too many pending inquiries; review current requests'
      using errcode='23514';
  end if;
  if exists(select 1 from atlas.person_contact_inquiry_intents i
    where i.ledger_id=p_ledger_id and i.requested_by_person_id=v_person
      and i.observed_email=v_email and i.relationship_question=v_question
      and i.observed_at>=now()-interval '1 day') then
    raise exception 'Equivalent pending inquiry already recorded' using errcode='23505';
  end if;
  insert into atlas.person_contact_inquiry_intents(
    ledger_id,organization_id,requested_by_person_id,source_party_record_id,
    request_key,observed_email,observed_person_label,purpose,relationship_question)
  values(p_ledger_id,v_org,v_person,p_source_party_record_id,v_key,
    v_email,v_label,v_purpose,v_question) returning id into v_new;
  return jsonb_build_object('inquiryId',v_new,'changed',true,
    'state','pending_source_resolution','personFound',null,
    'contactPermitted',null,'messageSent',false,'relationshipEstablished',false);
end $fn$;
revoke all on function atlas.create_person_contact_inquiry_intent_owner_self_api_v1(
  uuid,text,text,text,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.create_person_contact_inquiry_intent_owner_self_api_v1(
  uuid,text,text,text,text,text,uuid) to authenticated;

create function atlas.person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id uuid,p_inquiry_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare v_person uuid; v_principal uuid; v_i atlas.person_contact_inquiry_intents%rowtype;
begin
  if auth.uid() is null or
    (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
    raise exception 'Authenticated Atlas Person required' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_principal:=atlas.current_principal_id_v1();
  if v_person is null or v_principal is null or
    not atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id) then
    raise exception 'Root governing Ledger Principal required' using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  select * into v_i from atlas.person_contact_inquiry_intents i
    where i.id=p_inquiry_id and i.ledger_id=p_ledger_id
      and i.requested_by_person_id=v_person;
  if v_i.id is null then raise exception 'Inquiry unavailable' using errcode='P0002'; end if;
  return jsonb_build_object('inquiryId',v_i.id,'ledgerId',v_i.ledger_id,
    'state',v_i.intake_state,'observedEmail',v_i.observed_email,
    'observedPersonLabel',v_i.observed_person_label,
    'purpose',v_i.purpose,'relationshipQuestion',v_i.relationship_question,
    'createdAt',v_i.observed_at,'sourcePartyRecordId',v_i.source_party_record_id,
    'personFound',null,'contactPermitted',null,'messageSent',false,
    'identityVerified',false,'relationshipEstablished',false);
end $fn$;
revoke all on function atlas.person_contact_inquiry_intent_owner_self_api_v1(uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function atlas.person_contact_inquiry_intent_owner_self_api_v1(uuid,uuid)
 to authenticated;

create function public.create_person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id uuid,p_request_key text,p_observed_email text,
  p_purpose text,p_relationship_question text,
  p_observed_person_label text default null,p_source_party_record_id uuid default null
) returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.create_person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id,p_request_key,p_observed_email,p_purpose,
  p_relationship_question,p_observed_person_label,p_source_party_record_id) $fn$;
revoke all on function public.create_person_contact_inquiry_intent_owner_self_api_v1(
  uuid,text,text,text,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.create_person_contact_inquiry_intent_owner_self_api_v1(
  uuid,text,text,text,text,text,uuid) to authenticated;

create function public.person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id uuid,p_inquiry_id uuid
) returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.person_contact_inquiry_intent_owner_self_api_v1(
  p_ledger_id,p_inquiry_id) $fn$;
revoke all on function public.person_contact_inquiry_intent_owner_self_api_v1(uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.person_contact_inquiry_intent_owner_self_api_v1(uuid,uuid)
 to authenticated;

commit;
