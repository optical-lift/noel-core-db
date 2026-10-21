-- Direct Person assignment from any two active connections to the same native Ledger.
-- Active connection is the already-established participation arrangement.
-- Ordinary Work is dated/assigned immediately; an optional request remains separate.
begin;

alter table atlas.work_allocations drop constraint work_allocations_exact_assignee_carrier_v1;
alter table atlas.work_allocations add constraint work_allocations_exact_assignee_carrier_v1
 check (assignee_membership_id is not null or
  (assignee_canonical_person_id is not null and establishment_basis_kind in (
    'person_connection_receiver_uptake','delegated_under_standing_scope',
    'ledger_connection_direct_assignment')));

do $patched$
declare v_source text;v_old text;v_new text;
begin
v_source:=pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure);
v_old:='    ''person_connection_receiver_uptake''
  ) then';v_new:='    ''person_connection_receiver_uptake'',
    ''ledger_connection_direct_assignment''
  ) then';
if length(v_source)-length(replace(v_source,v_old,''))<>length(v_old) then
 raise exception 'Guard source accepted-kind signature changed';end if;
v_source:=replace(v_source,v_old,v_new);
v_old:='  if v_kind=''person_connection_receiver_uptake'' then';v_new:='
  if v_kind=''ledger_connection_direct_assignment'' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>''source'','''')<>''ledger_connected_direct_assignment_v1''
      or coalesce(v_basis->>''contractVersion'','''')<>''exact_work_responsibility_establishment_v2''
      or coalesce(v_basis->>''basisKind'','''')<>v_kind
      or coalesce(v_basis->>''organizationId'','''')<>new.organization_id::text
      or coalesce(v_basis->>''workItemId'','''')<>new.work_item_id::text
      or coalesce(v_basis->>''assigneePersonId'','''')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>''nativeLedgerId'','''') is null
      or nullif(v_basis->>''senderPersonId'','''') is null
      or coalesce(v_basis->>''authorizationBasis'','''')<>''active_mutual_native_ledger_connections''
    then raise exception ''Connected direct assignment requires exact original Person and Ledger source'' using errcode=''23514'';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>''senderPersonId'')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>''nativeLedgerId'')::uuid,
         (v_basis->>''senderPersonId'')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>''nativeLedgerId'')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>''nativeLedgerId'')::uuid
          and rel.attribution_state=''active'' and rel.evidence_kind=''participant_attested''
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state=''open''
           and w.metadata->>''sourceContract''=''ledger_connected_direct_assignment_v1''
           and w.metadata->>''createdByPersonId''=v_basis->>''senderPersonId''
           and w.metadata->>''recipientPersonId''=new.assignee_canonical_person_id::text)
    then raise exception ''Connection-direct responsibility has no verified original Person and Ledger'' using errcode=''23514'';end if;
    return new;
  end if;

  if v_kind=''person_connection_receiver_uptake'' then';
if length(v_source)-length(replace(v_source,v_old,''))<>length(v_old) then
 raise exception 'Guard source branch location changed';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.validate_active_work_allocation_membership_v1()'::regprocedure);
v_old:='(''person_connection_receiver_uptake'',''delegated_under_standing_scope'')';v_new:='(''person_connection_receiver_uptake'',''delegated_under_standing_scope'',''ledger_connection_direct_assignment'')';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.validate_active_work_allocation_membership_v1()';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.validate_work_execution_plan_v1()'::regprocedure);
v_old:='''delegated_under_standing_scope'',''person_connection_receiver_uptake''';v_new:='''delegated_under_standing_scope'',''person_connection_receiver_uptake'',''ledger_connection_direct_assignment''';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.validate_work_execution_plan_v1()';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.connected_person_company_work_today_self_api_v1(integer)'::regprocedure);
v_old:='''person_connection_receiver_uptake'',''delegated_under_standing_scope''';v_new:='''person_connection_receiver_uptake'',''delegated_under_standing_scope'',''ledger_connection_direct_assignment''';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.connected_person_company_work_today_self_api_v1(integer)';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.connected_person_company_work_day_self_api_v1(date)'::regprocedure);
v_old:='''person_connection_receiver_uptake'',''delegated_under_standing_scope''';v_new:='''person_connection_receiver_uptake'',''delegated_under_standing_scope'',''ledger_connection_direct_assignment''';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.connected_person_company_work_day_self_api_v1(date)';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.report_connected_person_company_work_internal_v1(uuid,text,text,jsonb,text,uuid,text)'::regprocedure);
v_old:='''person_connection_receiver_uptake'',''delegated_under_standing_scope''';v_new:='''person_connection_receiver_uptake'',''delegated_under_standing_scope'',''ledger_connection_direct_assignment''';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.report_connected_person_company_work_internal_v1(uuid,text,text,jsonb,text,uuid,text)';end if;
execute replace(v_source,v_old,v_new);
v_source:=pg_get_functiondef('atlas.connected_person_place_work_self_api_v1(uuid,date,text)'::regprocedure);
v_old:='''person_connection_receiver_uptake'',''delegated_under_standing_scope''';v_new:='''person_connection_receiver_uptake'',''delegated_under_standing_scope'',''ledger_connection_direct_assignment''';
if (length(v_source)-length(replace(v_source,v_old,'')))<>length(v_old)*1 then
  raise exception 'Canonical Person-native source mismatch: atlas.connected_person_place_work_self_api_v1(uuid,date,text)';end if;
execute replace(v_source,v_old,v_new);
end$patched$;

create or replace function atlas.connected_ledger_direct_assign_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_sentence text,
 p_execution_date date,p_source_action_id text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_sender uuid;v_org uuid;v_count integer;v_work atlas.work_items%rowtype;
 v_allocation atlas.work_allocations%rowtype;v_plan atlas.work_execution_plans%rowtype;
 v_title text:=nullif(btrim(coalesce(p_sentence,'')),'');
 v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
 v_key text;v_new boolean:=false;v_window jsonb;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 v_sender:=atlas.current_person_id_v1();
 if p_ledger_id is null or p_recipient_person_id is null
  or v_sender=p_recipient_person_id or p_execution_date is null
  or v_title is null or length(v_title)>500
  or v_action is null or length(v_action)>128 then
    raise exception 'One actual Person, recipient, Ledger, work sentence and date required' using errcode='22023';end if;
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 select count(*),(array_agg(x.organization_id))[1] into v_count,v_org
 from atlas.ledger_organization_participations x
 join atlas.ledgers l on l.id=x.ledger_id and l.status='active'
 join ledger.ledgers nl on nl.id=x.ledger_id and nl.ledger_state='active' and nl.retired_at is null
 where x.ledger_id=p_ledger_id and x.status='active' and x.ended_at is null
   and x.participation_kind in ('governing','operating');
 if v_count<>1
  or not atlas.person_has_native_ledger_connection_v1(v_org,p_ledger_id,v_sender)
  or not atlas.person_has_native_ledger_connection_v1(v_org,p_ledger_id,p_recipient_person_id) then
  raise exception 'Both Persons must actively share this exact operating Ledger' using errcode='42501';end if;
 if not exists(select 1 from atlas.work_result_contract_policies policy
 where policy.contract_key='ordinary_company_work_worker_attestation_v1'
  and policy.active and policy.source_domain='organization'
  and policy.acceptance_mode='worker_attestation') then
    raise exception 'Ordinary Company Work result contract unavailable' using errcode='23514';end if;
 v_key:='ledger-direct:'||auth.uid()::text||':'||md5(v_action);
 perform pg_advisory_xact_lock(hashtextextended('atlas.ledger.direct:'||v_org::text||':'||v_key,0));
 select * into v_work from atlas.work_items
 where organization_id=v_org and stable_key=v_key for update;
 if v_work.id is null then
   insert into atlas.work_items(organization_id,title,work_state,source_object_type,
    created_by_user_id,stable_key,metadata,result_contract_key)
   values(v_org,v_title,'open','ledger_connected_direct_task',auth.uid(),v_key,
    jsonb_build_object('sourceContract','ledger_connected_direct_assignment_v1',
      'sourceSurface','personal_notebook_daily_log','sourceActionId',v_action,
      'createdByPersonId',v_sender,'recipientPersonId',p_recipient_person_id,
      'nativeLedgerId',p_ledger_id,'requestedExecutionDate',p_execution_date,
      'custody','institutional','noAcceptanceNeeded',true),
    'ordinary_company_work_worker_attestation_v1')
   returning * into v_work;
   v_new:=true;
   insert into atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id)
   values(v_org,v_work.id,p_ledger_id,'participant_attested',
    'atlas.work_items:'||v_work.id::text,
    'Authentic shared Ledger connection directly issued ordinary work to another connected Person.',
    v_sender);
   insert into atlas.company_work_result_contract_bindings_v1(
    organization_id,ledger_id,work_item_id,actor_person_id,actor_membership_id,
    contract_key,reason)
   values(v_org,p_ledger_id,v_work.id,v_sender,null,
    'ordinary_company_work_worker_attestation_v1',
    'Authentic connected Person directly assigned ordinary Work under shared Ledger connections.');
   insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assignee_canonical_person_id,
    assigned_by_membership_id,allocation_role,state,allocated_at,establishment_basis_kind,
    establishment_basis,metadata)
   values(v_org,v_work.id,null,p_recipient_person_id,null,'responsible','active',now(),
    'ledger_connection_direct_assignment',
    jsonb_build_object('contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','ledger_connection_direct_assignment',
      'organizationId',v_org,'workItemId',v_work.id,'nativeLedgerId',p_ledger_id,
      'senderPersonId',v_sender,'assigneePersonId',p_recipient_person_id,
      'authorizationBasis','active_mutual_native_ledger_connections','establishedAt',now()),
    jsonb_build_object('source','ledger_connected_direct_assignment_v1',
      'senderPersonId',v_sender,'employeeSeatRequired',false,
      'workerReadProven',false,'recipientMayReschedule',true))
   returning * into v_allocation;
   v_window:=atlas.company_work_execution_plan_window_check_v1(v_work.id,p_execution_date);
   if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'Requested work day conflicts with Work source window' using errcode='23514';end if;
   insert into atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,plan_state,
    first_planned_service_date,planned_service_date,exposure_service_date,
    plan_reason,metadata)
   values(v_org,v_work.id,v_allocation.id,null,null,'active',
    p_execution_date,p_execution_date,p_execution_date,
    'Original connected Person assigned dated Ledger Work under a shared active connection.',
    jsonb_build_object('source','ledger_connected_direct_assignment_v1',
      'senderPersonId',v_sender,'nativeLedgerId',p_ledger_id,
      'personNative',true))
   returning * into v_plan;
   insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,actor_membership_id,reason,metadata)
   values(v_org,v_work.id,v_plan.id,'planned',p_execution_date,p_execution_date,null,
    'Exact sender established an immediate work-on date in the recipient Person notebook.',
    jsonb_build_object('source','ledger_connected_direct_assignment_v1','actorPersonId',v_sender));
 else
   if v_work.title is distinct from v_title
     or v_work.metadata->>'sourceActionId' is distinct from v_action
     or v_work.metadata->>'sourceContract' is distinct from 'ledger_connected_direct_assignment_v1'
     or v_work.metadata->>'createdByPersonId' is distinct from v_sender::text
     or v_work.metadata->>'recipientPersonId' is distinct from p_recipient_person_id::text
     or v_work.metadata->>'nativeLedgerId' is distinct from p_ledger_id::text
     or v_work.metadata->>'requestedExecutionDate' is distinct from p_execution_date::text
   then raise exception 'Reused source action refers to a different exact Work' using errcode='23505';end if;
   select * into v_allocation from atlas.work_allocations
    where work_item_id=v_work.id and establishment_basis_kind='ledger_connection_direct_assignment'
      and assignee_canonical_person_id=p_recipient_person_id
    order by allocated_at desc limit 1;
   select * into v_plan from atlas.work_execution_plans
    where work_item_id=v_work.id and responsible_allocation_id=v_allocation.id
    order by created_at limit 1;
   if v_allocation.id is null or v_plan.id is null then
     raise exception 'Original responsibility and day cannot be verified' using errcode='23514';end if;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','ledger_connected_direct_assignment_v1',
  'state','assigned','workItemId',v_work.id,'allocationId',v_allocation.id,'planId',v_plan.id,
  'ledgerId',p_ledger_id,'responsiblePersonId',p_recipient_person_id,
  'executionDate',p_execution_date,'createdNow',v_new,
  'personDayPlacementEstablished',true,'acceptanceRequired',false,
  'employeeSeatRequired',false,'workerReadProven',false,
  'newPersonalTaskCreated',false);
end$fn$;
create or replace function public.connected_ledger_direct_assign_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_sentence text,
 p_execution_date date,p_source_action_id text)
returns jsonb language sql security invoker set search_path='pg_catalog' as $fn$
 select atlas.connected_ledger_direct_assign_self_api_v1($1,$2,$3,$4,$5);
$fn$;
revoke all on function atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text) from public,anon;
revoke all on function public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text) from public,anon;
grant execute on function atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text) to authenticated;
grant execute on function public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text) to authenticated;
notify pgrst,'reload schema';
commit;
