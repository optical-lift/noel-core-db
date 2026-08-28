-- Atlas flower prospect route external custody v2
-- Prospect-route custody may belong to one Atlas member OR one external person.
-- It remains actual custody before sale truth.

alter table atlas.flower_prospect_routes add column if not exists custodian_label text;
alter table atlas.flower_prospect_routes alter column assigned_membership_id drop not null;
alter table atlas.flower_prospect_routes drop constraint if exists flower_prospect_routes_custodian_identity_check;
alter table atlas.flower_prospect_routes add constraint flower_prospect_routes_custodian_identity_check
check ((assigned_membership_id is not null) <> (nullif(btrim(coalesce(custodian_label,'')),'') is not null));

create or replace function atlas.validate_flower_prospect_route_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_assignee_farm uuid; v_recorder_farm uuid;
begin
  select farm_id into v_recorder_farm from atlas.farm_memberships where id=new.recorded_by_membership_id and active=true;
  if v_recorder_farm is null or v_recorder_farm is distinct from new.farm_id then
    raise exception 'Prospect route recorder must be active on this farm.' using errcode='22023';
  end if;
  if new.assigned_membership_id is not null then
    select farm_id into v_assignee_farm from atlas.farm_memberships where id=new.assigned_membership_id and active=true;
    if v_assignee_farm is null or v_assignee_farm is distinct from new.farm_id then
      raise exception 'Prospect route assignee must be active on this farm.' using errcode='22023';
    end if;
  elsif nullif(btrim(coalesce(new.custodian_label,'')),'') is null then
    raise exception 'Prospect route requires an internal assignee or external custodian.' using errcode='22023';
  end if;
  return new;
end $function$;

create or replace function atlas.record_flower_prospect_route_core_v2(
  p_farm_id uuid,p_effective_membership_id uuid,p_effective_role text,
  p_assigned_membership_id uuid,p_custodian_label text,p_route_date date,p_route_label text,
  p_lines jsonb,p_note text,p_idempotency_key text,p_operator_mode boolean default false
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_member atlas.farm_memberships%rowtype; v_assignee atlas.farm_memberships%rowtype;
  v_existing atlas.flower_prospect_routes%rowtype; v_route atlas.flower_prospect_routes%rowtype;
  v_external text:=nullif(btrim(coalesce(p_custodian_label,'')),'');
  v_line jsonb; v_ready atlas.flower_ready_inventory_lots%rowtype; v_ready_id uuid; v_buyer uuid;
  v_quantity numeric; v_available numeric; v_dest text; v_rows jsonb:='[]'::jsonb;
  v_inserted atlas.flower_prospect_route_lines%rowtype;
begin
  if v_key is null then raise exception 'Prospect-route idempotency key is required.' using errcode='22023'; end if;
  if lower(btrim(coalesce(p_effective_role,''))) not in ('owner','manager') then
    raise exception 'Owner or Manager authority is required to put Ready inventory on a prospect route.' using errcode='42501';
  end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from p_farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if (p_assigned_membership_id is null)=(v_external is null) then
    raise exception 'Choose exactly one route custodian: an Atlas member or an external person.' using errcode='22023';
  end if;
  if p_assigned_membership_id is not null then
    select * into v_assignee from atlas.farm_memberships where id=p_assigned_membership_id;
    if v_assignee.id is null or not v_assignee.active or v_assignee.farm_id is distinct from p_farm_id then
      raise exception 'Prospect-route assignee must be active on this farm.' using errcode='22023';
    end if;
  end if;
  if p_route_date is null or p_route_date>v_today then
    raise exception 'ON_PROSPECT_ROUTE is an actual custody state and cannot be recorded for a future date.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_route_label,'')),'') is null then raise exception 'Prospect route requires a label.' using errcode='22023'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>48 then
    raise exception 'Prospect route requires between 1 and 48 Ready inventory lines.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':flower-prospect:'||v_key,0));
  select * into v_existing from atlas.flower_prospect_routes where farm_id=p_farm_id and idempotency_key=v_key;
  if v_existing.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'readyLotId',l.ready_lot_id,'quantity',l.quantity,'buyerRelationshipId',l.buyer_relationship_id,'destinationLabel',l.destination_label) order by l.created_at),'[]'::jsonb)
    into v_rows from atlas.flower_prospect_route_lines l where l.prospect_route_id=v_existing.id;
    return jsonb_build_object('prospectRouteId',v_existing.id,'assignedMembershipId',v_existing.assigned_membership_id,'custodianLabel',v_existing.custodian_label,'lines',v_rows,'deduplicated',true);
  end if;

  insert into atlas.flower_prospect_routes(
    farm_id,route_date,route_label,assigned_membership_id,custodian_label,recorded_by_membership_id,note,idempotency_key,created_by_user_id,metadata
  ) values (
    p_farm_id,p_route_date,btrim(p_route_label),p_assigned_membership_id,v_external,p_effective_membership_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,auth.uid(),jsonb_build_object(
      'operatorMode',p_operator_mode,'truthBoundary','actual_prospect_custody','saleTruth',false,'workerTimeScheduled',false,
      'custodianKind',case when p_assigned_membership_id is null then 'external_person' else 'farm_member' end
    )
  ) returning * into v_route;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    begin v_ready_id:=nullif(v_line->>'readyLotId','')::uuid; exception when others then raise exception 'Invalid readyLotId in prospect route.' using errcode='22023'; end;
    begin v_buyer:=nullif(v_line->>'buyerRelationshipId','')::uuid; exception when others then raise exception 'Invalid buyerRelationshipId in prospect route.' using errcode='22023'; end;
    begin v_quantity:=(v_line->>'quantity')::numeric; exception when others then raise exception 'Invalid quantity in prospect route.' using errcode='22023'; end;
    v_dest:=nullif(btrim(coalesce(v_line->>'destinationLabel','')),'');
    select * into v_ready from atlas.flower_ready_inventory_lots where id=v_ready_id for update;
    if v_ready.id is null or v_ready.farm_id is distinct from p_farm_id then raise exception 'Prospect Ready lot is outside this farm.' using errcode='22023'; end if;
    if v_quantity is null or v_quantity<=0 then raise exception 'Prospect quantity must be positive.' using errcode='22023'; end if;
    if v_ready.unit='bucket_equivalent' then
      if mod(v_quantity*4,1)<>0 then raise exception 'Prospect bucket quantity must use quarter-bucket increments.' using errcode='22023'; end if;
    elsif mod(v_quantity,1)<>0 then raise exception 'Prospect counted units must be whole numbers.' using errcode='22023'; end if;
    if v_buyer is not null and not exists(select 1 from atlas.buyer_relationship_reconstruction b where b.id=v_buyer and b.farm_id=p_farm_id) then
      raise exception 'Prospect buyer is outside this farm.' using errcode='22023';
    end if;
    v_available:=atlas.flower_ready_available_quantity_v1(v_ready.id);
    if v_quantity>coalesce(v_available,0) then raise exception 'Prospect route would exceed Ready quantity still Available.' using errcode='22023'; end if;
    insert into atlas.flower_prospect_route_lines(farm_id,prospect_route_id,ready_lot_id,buyer_relationship_id,destination_label,quantity,metadata)
    values(p_farm_id,v_route.id,v_ready.id,v_buyer,v_dest,v_quantity,jsonb_build_object('truthBoundary','on_prospect_route','saleTruth',false)) returning * into v_inserted;
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('id',v_inserted.id,'readyLotId',v_inserted.ready_lot_id,'quantity',v_inserted.quantity,'buyerRelationshipId',v_inserted.buyer_relationship_id,'destinationLabel',v_inserted.destination_label));
  end loop;
  return jsonb_build_object('prospectRouteId',v_route.id,'routeDate',v_route.route_date,'assignedMembershipId',v_route.assigned_membership_id,'custodianLabel',v_route.custodian_label,'lines',v_rows,'deduplicated',false);
end $function$;

create or replace function atlas.record_flower_prospect_route_for_member_v2(
  p_farm_id uuid,p_assigned_membership_id uuid,p_custodian_label text,p_route_date date,p_route_label text,
  p_lines jsonb,p_note text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id); v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.record_flower_prospect_route_core_v2(p_farm_id,v_membership,v_role,p_assigned_membership_id,p_custodian_label,p_route_date,p_route_label,p_lines,p_note,p_idempotency_key,false);
end $function$;

create or replace function atlas.owner_operator_record_flower_prospect_route_v2(
  p_effective_membership_id uuid,p_assigned_membership_id uuid,p_custodian_label text,p_route_date date,p_route_label text,
  p_lines jsonb,p_note text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_context jsonb; v_farm uuid;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id); v_farm:=nullif(v_context->>'farmId','')::uuid;
  return atlas.record_flower_prospect_route_core_v2(v_farm,(v_context#>>'{effective,membershipId}')::uuid,v_context#>>'{effective,role}',p_assigned_membership_id,p_custodian_label,p_route_date,p_route_label,p_lines,p_note,p_idempotency_key,true);
end $function$;

revoke all on function atlas.record_flower_prospect_route_core_v2(uuid,uuid,text,uuid,text,date,text,jsonb,text,text,boolean) from public,anon,authenticated;
grant execute on function atlas.record_flower_prospect_route_core_v2(uuid,uuid,text,uuid,text,date,text,jsonb,text,text,boolean) to service_role;
revoke all on function atlas.record_flower_prospect_route_for_member_v2(uuid,uuid,text,date,text,jsonb,text,text) from public,anon;
grant execute on function atlas.record_flower_prospect_route_for_member_v2(uuid,uuid,text,date,text,jsonb,text,text) to authenticated,service_role;
revoke all on function atlas.owner_operator_record_flower_prospect_route_v2(uuid,uuid,text,date,text,jsonb,text,text) from public,anon;
grant execute on function atlas.owner_operator_record_flower_prospect_route_v2(uuid,uuid,text,date,text,jsonb,text,text) to authenticated,service_role;

with target as (
  select p.oid,format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) signature,
    case when p.proname like 'owner_operator_%' then 'owner_admin_endpoint' else 'app_endpoint' end classification,
    p.prosecdef security_definer,has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') anonymous_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute,
    (select count(*)::integer from pg_proc caller join pg_namespace cn on cn.oid=caller.pronamespace and cn.nspname='atlas' where caller.oid<>p.oid and caller.prokind='f' and (position(lower(p.proname)||'(' in lower(pg_get_functiondef(caller.oid)))>0 or position(lower(p.proname)||' (' in lower(pg_get_functiondef(caller.oid)))>0)) caller_count,
    (select count(*)::integer from pg_policies policy where position(lower(p.proname)||'(' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0 or position(lower(p.proname)||' (' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0) policy_reference_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname in ('record_flower_prospect_route_for_member_v2','owner_operator_record_flower_prospect_route_v2')
)
insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,registered_at,reviewed_at)
select signature,classification,'verified','active',authenticated_execute,anonymous_execute,security_definer,service_execute,caller_count,policy_reference_count,
  jsonb_build_object('source','atlas_flower_prospect_external_custody_v2','reason','allow_truthful_external_prospect_route_custodian','functionOid',oid,'classificationRuleVersion',3,'truthBoundary','Prospect route is actual custody before sale. Exactly one internal member or external custodian is named.'),now(),now()
from target
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,
  evidence=coalesce(atlas.authenticated_rpc_registry.evidence,'{}'::jsonb)||excluded.evidence,reviewed_at=now();

do $verification$
declare v_bad integer;
begin
  select count(*) into v_bad
  from atlas.authenticated_rpc_registry_drift_v1()
  where signature like 'atlas.record_flower_prospect_route_for_member_v2(%'
     or signature like 'atlas.owner_operator_record_flower_prospect_route_v2(%';
  if v_bad<>0 then raise exception 'External prospect-route v2 endpoints ended with % custody drift rows.',v_bad; end if;
end $verification$;
