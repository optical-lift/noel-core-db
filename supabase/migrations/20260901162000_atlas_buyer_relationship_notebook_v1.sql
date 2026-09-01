BEGIN;

-- Relationship Notebook v1
--
-- This is deliberately not a CRM authority. Relationship memory remains on the
-- existing buyer reconstruction; Demand, Sale, Task/Company Work, and payment
-- retain their own authorities. This slice only:
--   1. projects those exact linked facts into one read-only relationship timeline;
--   2. turns one explicit buyer follow-up into a canonical assigned Task, which
--      the existing Task -> Company Work convergence adopts as responsibility.

create unique index if not exists tasks_one_active_buyer_next_action_v1
on atlas.tasks (farm_id, ((metadata ->> 'buyer_relationship_id')))
where (metadata ->> 'relationship_action_kind') = 'buyer_follow_up'
  and status in ('open','blocked')
  and nullif(metadata ->> 'buyer_relationship_id','') is not null;

create index if not exists tasks_buyer_relationship_history_v1
on atlas.tasks (farm_id, ((metadata ->> 'buyer_relationship_id')), created_at desc)
where (metadata ->> 'relationship_action_kind') = 'buyer_follow_up';

create or replace view atlas.buyer_relationship_position_v1
with (security_invoker=true)
as
select
  r.id as buyer_relationship_id,
  r.farm_id,
  r.stable_key,
  r.business_name,
  r.business_type,
  r.primary_contact_name,
  r.relationship_status,
  r.relationship_status_reason,
  r.last_contacted_at,
  r.next_action as remembered_next_action,
  r.source,
  r.source_detail,
  r.linked_sales_count,
  r.identity_version,
  r.metadata as relationship_metadata,
  r.created_at,
  r.updated_at,
  action_task.id as current_next_action_task_id,
  action_task.note as current_next_action,
  action_task.due_date as current_next_action_due_on,
  action_task.status as current_next_action_status,
  action_task.assigned_membership_id as current_next_action_assigned_membership_id,
  company_work.work_item_id as current_next_action_work_item_id,
  company_work.work_state as current_next_action_work_state,
  (nullif(btrim(coalesce(r.next_action,'')),'') is not null and action_task.id is null) as needs_next_action_scheduling
from atlas.buyer_relationship_reconstruction r
left join lateral (
  select t.*
  from atlas.tasks t
  where t.farm_id=r.farm_id
    and t.metadata ->> 'relationship_action_kind'='buyer_follow_up'
    and t.metadata ->> 'buyer_relationship_id'=r.id::text
    and t.status in ('open','blocked')
  order by t.due_date nulls last,t.created_at,t.id
  limit 1
) action_task on true
left join lateral (
  select p.work_item_id,p.work_state
  from atlas.company_work_position_v2 p
  where action_task.id is not null
    and p.source_object_type='legacy_task'
    and p.source_object_id=action_task.id
  order by p.updated_at desc,p.work_item_id
  limit 1
) company_work on true;

revoke all on atlas.buyer_relationship_position_v1 from public,anon;
grant select on atlas.buyer_relationship_position_v1 to authenticated,service_role;

create or replace view atlas.buyer_relationship_timeline_v1
with (security_invoker=true)
as
select
  r.farm_id,
  r.id as buyer_relationship_id,
  r.created_at as occurred_at,
  'relationship_created'::text as event_kind,
  'buyer_relationship_reconstruction'::text as source_object_type,
  r.id as source_object_id,
  'Relationship added'::text as title,
  coalesce(nullif(r.business_name,''),r.stable_key) as detail,
  r.relationship_status as state,
  jsonb_strip_nulls(jsonb_build_object(
    'businessName',r.business_name,
    'businessType',r.business_type,
    'source',r.source,
    'sourceDetail',r.source_detail
  )) as metadata
from atlas.buyer_relationship_reconstruction r

union all

select
  e.farm_id,
  e.buyer_relationship_id,
  e.created_at,
  'contact'::text,
  'buyer_contact_event'::text,
  e.id,
  concat('Contact · ',replace(coalesce(e.contact_method,'recorded'),'_',' '))::text,
  coalesce(nullif(e.notes,''),nullif(e.contact_details,''),nullif(e.follow_up,''),nullif(e.outcome,''),'Contact recorded')::text,
  e.outcome,
  jsonb_strip_nulls(jsonb_build_object(
    'contactMethod',e.contact_method,
    'contactName',e.contact_name,
    'outcome',e.outcome,
    'followUp',e.follow_up,
    'salesChannel',e.sales_channel,
    'offerKey',e.offer_key,
    'quantity',e.quantity,
    'quotedWeeklyPrice',e.quoted_weekly_price,
    'agreedStartDate',e.agreed_start_date,
    'sourceTaskId',e.source_task_id
  ))
from atlas.buyer_contact_events e
where e.buyer_relationship_id is not null

union all

select
  d.farm_id,
  d.buyer_relationship_id,
  d.created_at,
  'flower_demand'::text,
  'flower_demand_order'::text,
  d.id,
  'Flower demand recorded'::text,
  coalesce(nullif(d.customer_label,''),'Flower customer') || ' · needed ' || d.requested_for_date::text,
  case
    when d.demand_strength='committed'
      or exists(select 1 from atlas.flower_demand_commitment_events c where c.demand_order_id=d.id and c.to_strength='committed')
    then 'committed'
    else d.demand_strength
  end,
  jsonb_strip_nulls(jsonb_build_object(
    'customerLabel',d.customer_label,
    'recordedDemandStrength',d.demand_strength,
    'salesChannel',d.sales_channel,
    'requestedForDate',d.requested_for_date,
    'fulfillmentMode',d.fulfillment_mode,
    'note',d.note
  ))
from atlas.flower_demand_orders d
where d.buyer_relationship_id is not null

union all

select
  s.farm_id,
  s.buyer_relationship_id,
  s.created_at,
  'flower_sale'::text,
  'flower_sale_order'::text,
  s.id,
  'Flower Sale recorded'::text,
  coalesce(nullif(s.customer_label,''),'Flower customer') || ' · ' || trim(to_char(s.total_amount,'FM999999990.00')),
  case when exists(select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=s.id) then 'cancelled' else 'recorded' end,
  jsonb_strip_nulls(jsonb_build_object(
    'customerLabel',s.customer_label,
    'salesChannel',s.sales_channel,
    'totalAmount',s.total_amount,
    'note',s.note,
    'paymentTruthIncluded',false
  ))
from atlas.flower_sale_orders s
where s.buyer_relationship_id is not null

union all

select
  t.farm_id,
  (t.metadata ->> 'buyer_relationship_id')::uuid,
  t.created_at,
  'next_action'::text,
  'task'::text,
  t.id,
  t.title,
  coalesce(nullif(t.note,''),'Buyer follow-up'),
  t.status,
  jsonb_strip_nulls(jsonb_build_object(
    'dueOn',t.due_date,
    'assignedMembershipId',t.assigned_membership_id,
    'workItemId',work.work_item_id,
    'workState',work.work_state,
    'idempotencyKey',t.metadata ->> 'relationship_next_action_idempotency_key'
  ))
from atlas.tasks t
left join lateral (
  select p.work_item_id,p.work_state
  from atlas.company_work_position_v2 p
  where p.source_object_type='legacy_task' and p.source_object_id=t.id
  order by p.updated_at desc,p.work_item_id
  limit 1
) work on true
where t.metadata ->> 'relationship_action_kind'='buyer_follow_up'
  and t.metadata ->> 'buyer_relationship_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

revoke all on atlas.buyer_relationship_timeline_v1 from public,anon;
grant select on atlas.buyer_relationship_timeline_v1 to authenticated,service_role;

create or replace function atlas.create_buyer_relationship_next_action_core_v1(
  p_buyer_relationship_id uuid,
  p_action text,
  p_due_on date,
  p_assigned_membership_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_relationship atlas.buyer_relationship_reconstruction%rowtype;
  v_effective atlas.farm_memberships%rowtype;
  v_assignee atlas.farm_memberships%rowtype;
  v_action text:=nullif(btrim(coalesce(p_action,'')),'');
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_task atlas.tasks%rowtype;
  v_existing atlas.tasks%rowtype;
  v_work_item_id uuid;
  v_work_state text;
begin
  if v_action is null then raise exception 'Buyer next action is required.' using errcode='22023'; end if;
  if v_key is null then raise exception 'Buyer next-action idempotency key is required.' using errcode='22023'; end if;
  if p_effective_role not in ('owner','manager') then raise exception 'Owner or Manager authority is required to schedule buyer follow-up.' using errcode='42501'; end if;

  select * into v_relationship
  from atlas.buyer_relationship_reconstruction
  where id=p_buyer_relationship_id
  for update;
  if v_relationship.id is null then raise exception 'Buyer relationship not found.' using errcode='P0002'; end if;

  select * into v_effective from atlas.farm_memberships where id=p_effective_membership_id;
  if v_effective.id is null or not v_effective.active or v_effective.farm_id is distinct from v_relationship.farm_id then
    raise exception 'Active same-farm membership required.' using errcode='42501';
  end if;

  select * into v_assignee
  from atlas.farm_memberships
  where id=coalesce(p_assigned_membership_id,p_effective_membership_id);
  if v_assignee.id is null or not v_assignee.active or v_assignee.farm_id is distinct from v_relationship.farm_id then
    raise exception 'Buyer next action must be assigned to an active membership on the same farm.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.tasks t
  where t.farm_id=v_relationship.farm_id
    and t.metadata ->> 'relationship_next_action_idempotency_key'=v_key
  order by t.created_at
  limit 1;
  if v_existing.id is not null then
    if v_existing.metadata ->> 'buyer_relationship_id' is distinct from v_relationship.id::text then
      raise exception 'Buyer next-action idempotency key is already used by another relationship.' using errcode='22023';
    end if;
    select p.work_item_id,p.work_state into v_work_item_id,v_work_state
    from atlas.company_work_position_v2 p
    where p.source_object_type='legacy_task' and p.source_object_id=v_existing.id
    order by p.updated_at desc,p.work_item_id limit 1;
    return jsonb_build_object(
      'buyerRelationshipId',v_relationship.id,'taskId',v_existing.id,
      'workItemId',v_work_item_id,'workState',v_work_state,
      'deduplicated',true,'relationshipMemoryCopied',false,'paymentTruth',false
    );
  end if;

  if exists(
    select 1 from atlas.tasks t
    where t.farm_id=v_relationship.farm_id
      and t.metadata ->> 'relationship_action_kind'='buyer_follow_up'
      and t.metadata ->> 'buyer_relationship_id'=v_relationship.id::text
      and t.status in ('open','blocked')
  ) then
    raise exception 'This buyer relationship already has an active next action. Complete, archive, or reschedule that responsibility first.' using errcode='23505';
  end if;

  insert into atlas.tasks(
    farm_id,title,task_type,status,priority,due_date,note,metadata,
    action_key,work_class,visibility_scope,assigned_membership_id,task_scope
  ) values (
    v_relationship.farm_id,
    'Follow up — ' || coalesce(nullif(btrim(v_relationship.business_name),''),v_relationship.stable_key),
    'relationship_follow_up','open','normal',p_due_on,v_action,
    jsonb_strip_nulls(jsonb_build_object(
      'relationship_action_kind','buyer_follow_up',
      'buyer_relationship_id',v_relationship.id,
      'buyer_relationship_stable_key',v_relationship.stable_key,
      'buyer_business_name',v_relationship.business_name,
      'relationship_next_action_idempotency_key',v_key,
      'relationship_notebook_version','v1',
      'operatorMode',p_operator_mode,
      'commercialTruthAuthority',false,
      'paymentTruth',false,
      'display_action','Follow up',
      'display_subject',coalesce(nullif(btrim(v_relationship.business_name),''),v_relationship.stable_key)
    )),
    'follow_up','communication','assigned_worker',v_assignee.id,'farm_operation'
  ) returning * into v_task;

  -- A remembered follow-up is only relationship memory. Scheduling it converts
  -- the human suggestion into real Task/Company Work responsibility, so clear
  -- the memory instead of leaving a stale duplicate that could reappear later.
  update atlas.buyer_relationship_reconstruction
  set next_action=null,
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'last_scheduled_next_action',v_action,
        'last_scheduled_next_action_task_id',v_task.id,
        'last_scheduled_next_action_at',now(),
        'relationship_next_action_authority','task_company_work'
      ),
      updated_at=now()
  where id=v_relationship.id;

  select p.work_item_id,p.work_state into v_work_item_id,v_work_state
  from atlas.company_work_position_v2 p
  where p.source_object_type='legacy_task' and p.source_object_id=v_task.id
  order by p.updated_at desc,p.work_item_id limit 1;

  if v_work_item_id is null then
    raise exception 'Buyer follow-up Task did not converge to Company Work responsibility.' using errcode='P0001';
  end if;

  return jsonb_build_object(
    'buyerRelationshipId',v_relationship.id,'taskId',v_task.id,
    'workItemId',v_work_item_id,'workState',v_work_state,
    'assignedMembershipId',v_assignee.id,'dueOn',v_task.due_date,
    'deduplicated',false,'relationshipMemoryCopied',false,'paymentTruth',false
  );
end;
$function$;

revoke all on function atlas.create_buyer_relationship_next_action_core_v1(uuid,text,date,uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function atlas.create_buyer_relationship_next_action_core_v1(uuid,text,date,uuid,uuid,text,text,boolean) to service_role;

create or replace function atlas.create_buyer_relationship_next_action_for_member_v1(
  p_farm_id uuid,
  p_buyer_relationship_id uuid,
  p_action text,
  p_due_on date,
  p_assigned_membership_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.create_buyer_relationship_next_action_core_v1(
    p_buyer_relationship_id,p_action,p_due_on,p_assigned_membership_id,
    v_membership,v_role,p_idempotency_key,false
  );
end;
$function$;

revoke all on function atlas.create_buyer_relationship_next_action_for_member_v1(uuid,uuid,text,date,uuid,text) from public,anon;
grant execute on function atlas.create_buyer_relationship_next_action_for_member_v1(uuid,uuid,text,date,uuid,text) to authenticated,service_role;

create or replace function atlas.owner_operator_create_buyer_relationship_next_action_v1(
  p_effective_membership_id uuid,
  p_buyer_relationship_id uuid,
  p_action text,
  p_due_on date,
  p_assigned_membership_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_context jsonb;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  return atlas.create_buyer_relationship_next_action_core_v1(
    p_buyer_relationship_id,p_action,p_due_on,p_assigned_membership_id,
    (v_context#>>'{effective,membershipId}')::uuid,
    v_context#>>'{effective,role}',p_idempotency_key,true
  );
end;
$function$;

revoke all on function atlas.owner_operator_create_buyer_relationship_next_action_v1(uuid,uuid,text,date,uuid,text) from public,anon;
grant execute on function atlas.owner_operator_create_buyer_relationship_next_action_v1(uuid,uuid,text,date,uuid,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,
  security_definer_expected,service_execute_expected,caller_count,policy_reference_count,
  evidence,reviewed_at,anonymous_execute_expected
)
values
(
  'atlas.create_buyer_relationship_next_action_for_member_v1(uuid, uuid, text, date, uuid, text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Schedule one explicit buyer follow-up as canonical assigned Task and Company Work responsibility.',
    'boundary','Buyer relationship memory is not responsibility authority; Owner or Manager explicitly schedules work.',
    'truthReuse','Task remains execution carrier; Company Work remains durable responsibility authority.',
    'commercialTruth','Creates no Demand, Sale, fulfillment, inventory, or payment truth.',
    'caller','Reserved for farm-atlas Relationship Notebook.'
  ),now(),false
),
(
  'atlas.owner_operator_create_buyer_relationship_next_action_v1(uuid, uuid, text, date, uuid, text)',
  'owner_admin_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Schedule the same buyer follow-up through Owner operator context.',
    'boundary','owner_operator_context_v1 resolves effective membership; effective role must be Owner or Manager.',
    'truthReuse','Task -> Company Work convergence is reused; no CRM task queue is created.',
    'commercialTruth','Creates no Demand, Sale, fulfillment, inventory, or payment truth.',
    'caller','Reserved for farm-atlas Relationship Notebook.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

COMMIT;
