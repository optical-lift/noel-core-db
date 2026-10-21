-- Universal connected-Person Ledger correspondence. Draft for governed validation only.
begin;

create table atlas.ledger_person_dispatches (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references atlas.organizations(id),
 ledger_id uuid not null references atlas.ledgers(id),
 sender_person_id uuid not null references reality.entities(id),
 recipient_person_id uuid not null references reality.entities(id),
 source_action_id text not null,
 dispatch_kind text not null check (dispatch_kind in ('notice','work_request')),
 body text not null check (length(btrim(body)) between 1 and 500),
 dispatch_state text not null default 'pending'
   check (dispatch_state in ('pending','acknowledged','declined','accepted')),
 created_at timestamptz not null default now(),
 responded_at timestamptz,
 linked_work_item_id uuid references atlas.work_items(id),
 check (sender_person_id <> recipient_person_id),
 check (length(btrim(source_action_id)) between 1 and 128),
 check (
   (dispatch_state='pending' and responded_at is null and linked_work_item_id is null)
   or (dispatch_state='acknowledged' and dispatch_kind='notice' and responded_at is not null and linked_work_item_id is null)
   or (dispatch_state='declined' and dispatch_kind='work_request' and responded_at is not null and linked_work_item_id is null)
   or (dispatch_state='accepted' and dispatch_kind='work_request' and responded_at is not null and linked_work_item_id is not null)
 ),
 unique(sender_person_id,source_action_id)
);
create index ledger_person_dispatches_received_idx
 on atlas.ledger_person_dispatches(recipient_person_id,created_at desc,id desc);
alter table atlas.ledger_person_dispatches enable row level security;
revoke all on atlas.ledger_person_dispatches from public,anon,authenticated;

create or replace function atlas.connected_ledger_person_choices_self_api_v1(
 p_ledger_id uuid,p_limit integer default 100,p_after_person_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_self uuid;v_items jsonb;v_next uuid;v_more boolean;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 if p_limit not between 1 and 100 then
   raise exception 'Page size out of range' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('personId',x.id,'name',x.display_name)
  order by x.id),'[]'::jsonb) into v_items from (
  select distinct e.id,e.display_name from ledger.seats s
  join reality.entities e on e.id=s.person_entity_id
  where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
   and e.entity_kind='person' and e.identity_state='canonical'
   and e.id<>v_self and (p_after_person_id is null or e.id>p_after_person_id)
  order by e.id limit p_limit) x;
 if jsonb_array_length(v_items)>0 then
   v_next:=(v_items->(jsonb_array_length(v_items)-1)->>'personId')::uuid;
   select exists(select 1 from ledger.seats s
    join reality.entities e on e.id=s.person_entity_id
    where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
     and e.entity_kind='person' and e.identity_state='canonical'
     and e.id<>v_self and e.id>v_next) into v_more;
 else v_more:=false;end if;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_person_choices_v1',
 'ledgerId',p_ledger_id,'items',v_items,'hasMore',v_more,
 'nextPersonId',case when v_more then v_next else null end,
 'rootAuthorityNotRequired',true);
end$fn$;


create or replace function atlas.connected_ledger_send_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_body text,p_kind text,p_source_action_id text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_self uuid;v_org uuid;v_count integer;v_row atlas.ledger_person_dispatches%rowtype;
v_body text:=nullif(btrim(coalesce(p_body,'')),'');
v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 if p_ledger_id is null or p_recipient_person_id is null or v_self=p_recipient_person_id
 or p_kind not in ('notice','work_request') or v_body is null or length(v_body)>500
 or v_action is null or length(v_action)>128 then
  raise exception 'Exact Ledger, distinct Person, sentence and source action required' using errcode='22023';end if;
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 select count(*),min(lop.organization_id) into v_count,v_org
 from atlas.ledger_organization_participations lop
 join atlas.ledgers l on l.id=lop.ledger_id and l.status='active'
 join ledger.ledgers nl on nl.id=lop.ledger_id and nl.ledger_state='active' and nl.retired_at is null
 where lop.ledger_id=p_ledger_id and lop.status='active' and lop.ended_at is null
 and lop.participation_kind in ('governing','operating');
 if v_count<>1 or not atlas.person_has_native_ledger_connection_v1(v_org,p_ledger_id,p_recipient_person_id)
 then raise exception 'Both Persons must be connected to the same active Ledger' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('atlas.ledger.peer:'||v_self::text||':'||v_action,0));
 select * into v_row from atlas.ledger_person_dispatches
 where sender_person_id=v_self and source_action_id=v_action for update;
 if v_row.id is not null then
  if v_row.ledger_id is distinct from p_ledger_id
   or v_row.organization_id is distinct from v_org
   or v_row.recipient_person_id is distinct from p_recipient_person_id
   or v_row.dispatch_kind is distinct from p_kind or v_row.body is distinct from v_body then
   raise exception 'This source action belongs to a different Ledger message' using errcode='23505';end if;
 else
  insert into atlas.ledger_person_dispatches(
   organization_id,ledger_id,sender_person_id,recipient_person_id,source_action_id,dispatch_kind,body)
  values(v_org,p_ledger_id,v_self,p_recipient_person_id,v_action,p_kind,v_body)
  returning * into v_row;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_dispatch_v1',
  'dispatchId',v_row.id,'ledgerId',v_row.ledger_id,'recipientPersonId',v_row.recipient_person_id,
  'kind',v_row.dispatch_kind,'state',v_row.dispatch_state,
  'workItemId',v_row.linked_work_item_id,
  'recipientViewed',false,'notificationDelivered',false,'rootAuthorityRequired',false);
end$fn$;

create or replace function atlas.connected_ledger_inbox_self_api_v1(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_self uuid;v_items jsonb;v_total integer;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 if p_limit not between 1 and 100 then raise exception 'Page size out of range' using errcode='22023';end if;
 select count(*) into v_total from atlas.ledger_person_dispatches d
 where d.recipient_person_id=v_self and d.dispatch_state='pending'
 and atlas.person_has_native_ledger_connection_v1(d.organization_id,d.ledger_id,v_self);
 select coalesce(jsonb_agg(jsonb_build_object(
  'dispatchId',x.id,'ledgerId',x.ledger_id,'ledgerName',x.ledger_name,
  'senderPersonId',x.sender_person_id,'senderName',x.sender_name,
  'kind',x.dispatch_kind,'body',x.body,'createdAt',x.created_at,'state',x.dispatch_state)
  order by x.created_at desc,x.id desc),'[]'::jsonb) into v_items
 from (select d.*,l.name ledger_name,e.display_name sender_name
  from atlas.ledger_person_dispatches d
  join atlas.ledgers l on l.id=d.ledger_id
  join reality.entities e on e.id=d.sender_person_id
  where d.recipient_person_id=v_self and d.dispatch_state='pending'
  and atlas.person_has_native_ledger_connection_v1(d.organization_id,d.ledger_id,v_self)
  order by d.created_at desc,d.id desc limit p_limit) x;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_inbox_v1',
  'items',v_items,'total',v_total,'truncated',v_total>p_limit,'rootAuthorityRequired',false);
end$fn$;


-- Existing receipt tables used by receiver-accepted Person-native allocations.
-- A Ledger connection cannot manufacture a legacy Organization membership.
alter table atlas.company_work_initial_responsibility_offers
  alter column offered_by_membership_id drop not null;
alter table atlas.company_work_result_contract_bindings_v1
  alter column actor_membership_id drop not null;

-- Separate participant-authored evidence from owner attestation. Neither is
-- source-verified by an external booking provider.
alter table atlas.company_work_native_ledger_relevance
 drop constraint company_work_native_ledger_relevance_evidence_kind_check;
alter table atlas.company_work_native_ledger_relevance
 add constraint company_work_native_ledger_relevance_evidence_kind_check
 check (evidence_kind in ('owner_attested','participant_attested','source_verified'));
alter table atlas.company_work_native_ledger_relevance
 drop constraint company_work_relevance_evidence_separation_v1;
alter table atlas.company_work_native_ledger_relevance
 add constraint company_work_relevance_evidence_separation_v1 check(
 (evidence_kind in ('owner_attested','participant_attested')
   and nullif(btrim(attestation_source_ref),'') is not null
   and nullif(btrim(attestation_reason),'') is not null
   and source_schema is null and source_table is null and source_id is null and verified_at is null)
 or
 (evidence_kind='source_verified'
   and attestation_source_ref is null and attestation_reason is null
   and source_schema='ledger' and source_table in ('booking_requests','booking_offerings')
   and source_id is not null and verified_at is not null)
 );

-- Guarded exact-text updates of only the two existing Person-native acceptance
-- clauses. Refuse a source mismatch rather than reintroducing an owner credential.
do $patch$
declare v_source text;v_old text;v_new text;
begin
 v_source:=pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure);
 v_old:='o.offered_by_membership_id=new.assigned_by_membership_id';
 v_new:='o.offered_by_membership_id is not distinct from new.assigned_by_membership_id';
 if length(v_source)-length(replace(v_source,v_old,''))<>length(v_old) then
  raise exception 'Exact Person-native offer guard source changed; review required';
 end if;
 execute replace(v_source,v_old,v_new);
 v_source:=pg_get_functiondef('atlas.establish_connected_person_company_work_from_offer_v1(uuid,text,text,uuid)'::regprocedure);
 v_old:='rel.evidence_kind=''owner_attested'' or';
 v_new:='rel.evidence_kind in (''owner_attested'',''participant_attested'') or';
 if length(v_source)-length(replace(v_source,v_old,''))<>length(v_old) then
  raise exception 'Exact Person-native offer establishment source changed; review required';
 end if;
 execute replace(v_source,v_old,v_new);
end$patch$;


create or replace function atlas.connected_ledger_respond_self_api_v1(
 p_dispatch_id uuid,p_decision text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 v_self uuid;v_d atlas.ledger_person_dispatches%rowtype;
 v_work atlas.work_items%rowtype;v_offer atlas.company_work_initial_responsibility_offers%rowtype;
 v_allocation jsonb;v_decision text:=lower(btrim(coalesce(p_decision,'')));
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 select * into v_d from atlas.ledger_person_dispatches where id=p_dispatch_id for update;
 if v_d.id is null or v_d.recipient_person_id<>v_self
 then raise exception 'Only the exact recipient can respond' using errcode='42501';end if;
 if not atlas.person_has_native_ledger_connection_v1(v_d.organization_id,v_d.ledger_id,v_self)
 then raise exception 'Recipient no longer connected to this Ledger' using errcode='42501';end if;
 if (v_d.dispatch_kind='notice' and v_decision<>'acknowledge')
 or (v_d.dispatch_kind='work_request' and v_decision not in ('accept','decline'))
 then raise exception 'Invalid decision for exact message kind' using errcode='22023';end if;
 if v_d.dispatch_state<>'pending' then
   if (v_d.dispatch_state='acknowledged' and v_decision='acknowledge')
   or (v_d.dispatch_state='accepted' and v_decision='accept')
   or (v_d.dispatch_state='declined' and v_decision='decline')
   then return jsonb_build_object('ok',true,'contractVersion','connected_ledger_response_v1',
     'dispatchId',v_d.id,'state',v_d.dispatch_state,
     'workItemId',v_d.linked_work_item_id,'idempotent',true);end if;
   raise exception 'Message already resolved in another way' using errcode='23514';
 end if;
 if v_decision in ('acknowledge','decline') then
   update atlas.ledger_person_dispatches
   set dispatch_state=case when v_decision='acknowledge' then 'acknowledged' else 'declined' end,
       responded_at=now() where id=v_d.id;
   return jsonb_build_object('ok',true,'contractVersion','connected_ledger_response_v1',
     'dispatchId',v_d.id,'state',
     case when v_decision='acknowledge' then 'acknowledged' else 'declined' end,
     'workCreated',false,'idempotent',false);
 end if;
 if not atlas.person_has_native_ledger_connection_v1(
   v_d.organization_id,v_d.ledger_id,v_d.sender_person_id)
 then raise exception 'Original sender is no longer connected; cannot establish new Work'
 using errcode='23514';end if;
 if not exists(select 1 from atlas.work_result_contract_policies policy
  where policy.contract_key='ordinary_company_work_worker_attestation_v1'
  and policy.active and policy.source_domain='organization'
  and policy.acceptance_mode='worker_attestation')
 then raise exception 'Ordinary Company Work result policy unavailable' using errcode='23514';end if;
 -- Materialize exactly one Work only after the recipient chooses acceptance.
 -- The authenticated recipient did not author the source request.
 insert into atlas.work_items(
   organization_id,title,work_state,source_object_type,source_object_id,
   result_contract_key,stable_key,metadata)
 values(v_d.organization_id,v_d.body,'open','ledger_person_dispatch',v_d.id,
  'ordinary_company_work_worker_attestation_v1',
  'peer-dispatch:'||v_d.id::text,
  jsonb_build_object('sourceContract','connected_ledger_dispatch_v1',
   'sourceSurface','connected_ledger_inbox','sourceDispatchId',v_d.id,
   'sentByPersonId',v_d.sender_person_id,'acceptedByPersonId',v_self,
   'custody','institutional','notAnExecutionDate',true))
 returning * into v_work;
 insert into atlas.company_work_native_ledger_relevance(
  organization_id,work_item_id,ledger_id,evidence_kind,attestation_source_ref,
  attestation_reason,established_by_person_id)
 values(v_d.organization_id,v_work.id,v_d.ledger_id,'participant_attested',
  'atlas.ledger_person_dispatches:'||v_d.id::text,
  'Exact sender Ledger connection and the recipient acceptance of requested Work.',
  v_d.sender_person_id);
 insert into atlas.company_work_result_contract_bindings_v1(
  organization_id,ledger_id,work_item_id,actor_person_id,actor_membership_id,
  contract_key,reason)
 values(v_d.organization_id,v_d.ledger_id,v_work.id,v_d.sender_person_id,null,
  'ordinary_company_work_worker_attestation_v1',
  'An authentic connected Person requested ordinary Work and the recipient accepted it.');
 insert into atlas.company_work_initial_responsibility_offers(
  organization_id,work_item_id,ledger_id,offered_by_person_id,
  offered_by_membership_id,target_person_id,target_membership_id,reason)
 values(v_d.organization_id,v_work.id,v_d.ledger_id,v_d.sender_person_id,
  null,v_self,null,'The original connected Person request was accepted by the recipient.')
 returning * into v_offer;
 v_allocation:=atlas.establish_connected_person_company_work_from_offer_v1(
   v_offer.id,'recipient_self_accepted',null,null);
 if v_allocation->>'state'<>'accepted'
 or v_allocation->>'workItemId' is distinct from v_work.id::text then
  raise exception 'Accepted canonical responsibility could not be verified' using errcode='23514';
 end if;
 update atlas.ledger_person_dispatches
 set dispatch_state='accepted',responded_at=now(),linked_work_item_id=v_work.id
 where id=v_d.id;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_response_v1',
  'dispatchId',v_d.id,'state','accepted','workItemId',v_work.id,
  'allocationId',v_allocation->>'allocationId','workCreated',true,
  'executionDateEstablished',false,'idempotent',false);
end$fn$;

revoke all on function atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)
 from public,anon;
revoke all on function atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)
 from public,anon;
revoke all on function atlas.connected_ledger_inbox_self_api_v1(integer)
 from public,anon;
revoke all on function atlas.connected_ledger_respond_self_api_v1(uuid,text)
 from public,anon;
grant execute on function atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)
 to authenticated;
grant execute on function atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)
 to authenticated;
grant execute on function atlas.connected_ledger_inbox_self_api_v1(integer)
 to authenticated;
grant execute on function atlas.connected_ledger_respond_self_api_v1(uuid,text)
 to authenticated;


-- The Work origin is participant-attested, not owner-attested. Show the same
-- authentic Person-native Work on Ledger accountability and planning reads;
-- preserve all original ROOT gates on owner-only management operations.
do $projections$
declare v_source text;v_old text:='evidence_kind=''owner_attested''';
v_new text:='evidence_kind in (''owner_attested'',''participant_attested'')';
v_expected integer;v_signature text;
begin
 for v_signature,v_expected in
  select signature,num from (values
   ('atlas.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)',2),
   ('atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)',2),
   ('atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)',1),
   ('atlas.owner_native_ledger_blocker_detail_self_api_v1(uuid,uuid)',1)
  ) x(signature,num)
 loop
  v_source:=pg_get_functiondef(to_regprocedure(v_signature));
  if v_source is null or
    (length(v_source)-length(replace(v_source,v_old,'')))
      <>length(v_old)*v_expected
  then raise exception 'Ledger evidence reader changed: %',v_signature;end if;
  execute replace(v_source,v_old,v_new);
 end loop;
end$projections$;

commit;
