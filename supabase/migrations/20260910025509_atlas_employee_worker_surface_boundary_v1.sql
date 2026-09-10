begin;

create or replace function atlas.organization_employee_worker_context_self_v1(
  p_farm_id uuid,
  p_delivery_membership_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_farm atlas.farms%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_seat atlas.organization_employee_seats%rowtype;
  v_position atlas.organization_positions%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
  v_timezone text:='America/Chicago';
  v_today date;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','authentication_required'); end if;
  if p_farm_id is null or p_delivery_membership_id is null then return jsonb_build_object('ok',false,'reason','worker_context_required'); end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id;
  if v_farm.id is null or v_farm.organization_id is null or v_farm.organization_unit_id is null then
    return jsonb_build_object('ok',false,'reason','institutional_farm_context_required');
  end if;

  v_timezone:=coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='America/Chicago'; end if;
  v_today:=(now() at time zone v_timezone)::date;

  select * into v_farm_member
  from atlas.farm_memberships fm
  where fm.id=p_delivery_membership_id and fm.farm_id=p_farm_id and fm.user_id=v_uid
    and fm.active=true and fm.role='farm_hand' and fm.identity_subject_id is not null;
  if v_farm_member.id is null then return jsonb_build_object('ok',false,'reason','active_worker_membership_required'); end if;
  if not atlas.farm_membership_eligible_on_date_v1(v_farm_member.id,p_farm_id,v_today) then
    return jsonb_build_object('ok',false,'reason','worker_membership_not_eligible');
  end if;

  select * into v_org_member
  from atlas.organization_memberships m
  where m.organization_id=v_farm.organization_id and m.user_id=v_uid
    and m.identity_subject_id=v_farm_member.identity_subject_id and m.active=true and m.role='member'
  order by m.created_at limit 1;
  if v_org_member.id is null then return jsonb_build_object('ok',false,'reason','employee_organization_membership_required'); end if;
  if not atlas.organization_membership_eligible_on_date_v1(v_org_member.id,v_farm.organization_id,v_today) then
    return jsonb_build_object('ok',false,'reason','employee_organization_membership_not_eligible');
  end if;

  select * into v_seat
  from atlas.organization_employee_seats s
  where s.organization_id=v_farm.organization_id and s.organization_membership_id=v_org_member.id
    and s.identity_subject_id=v_org_member.identity_subject_id and s.seat_class='employee'
    and s.status='active' and s.billing_state in ('active','waived') limit 1;
  if v_seat.id is null then return jsonb_build_object('ok',false,'reason','active_employee_seat_required'); end if;

  if not exists(
    select 1 from atlas.organization_member_credentials c
    where c.organization_id=v_farm.organization_id and c.organization_membership_id=v_org_member.id
      and c.employee_seat_id=v_seat.id and c.identity_subject_id=v_org_member.identity_subject_id
      and c.credential_kind='auth_user' and c.auth_user_id=v_uid and c.status='active'
      and (c.expires_at is null or c.expires_at>now())
  ) then return jsonb_build_object('ok',false,'reason','active_employee_credential_required'); end if;

  select a into v_appointment
  from atlas.organization_position_appointments a
  join atlas.organization_positions p on p.id=a.position_id and p.organization_id=a.organization_id and p.status='active'
  where a.organization_id=v_farm.organization_id and a.organization_membership_id=v_org_member.id
    and a.identity_subject_id=v_org_member.identity_subject_id and a.status='active'
    and a.begins_at<=now() and (a.ends_at is null or a.ends_at>now())
    and p.organization_unit_id=v_farm.organization_unit_id
  order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id limit 1;
  if v_appointment.id is null then return jsonb_build_object('ok',false,'reason','active_worker_appointment_required'); end if;

  select * into v_position from atlas.organization_positions p
  where p.id=v_appointment.position_id and p.organization_id=v_farm.organization_id
    and p.organization_unit_id=v_farm.organization_unit_id and p.status='active';
  if v_position.id is null then return jsonb_build_object('ok',false,'reason','active_worker_position_required'); end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','organization_employee_worker_context_v1',
    'organizationId',v_farm.organization_id,'organizationUnitId',v_farm.organization_unit_id,
    'organizationMembershipId',v_org_member.id,'deliveryMembershipId',v_farm_member.id,
    'identitySubjectId',v_org_member.identity_subject_id,'employeeSeatId',v_seat.id,
    'appointmentId',v_appointment.id,'positionId',v_position.id,'positionKey',v_position.stable_key,
    'positionTitle',v_position.display_title,'serviceDate',v_today
  );
end;
$function$;

revoke all on function atlas.organization_employee_worker_context_self_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.organization_employee_worker_context_self_v1(uuid,uuid) to service_role;

create or replace function atlas.worker_delivery_pilot_session_status_v1(p_session_token_hash text)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select coalesce((
    select jsonb_build_object('ok',true,'sessionId',s.id,'membershipId',c.delivery_membership_id,
      'organizationMembershipId',c.organization_membership_id,'employeeSeatId',seat.id,'expiresAt',s.expires_at)
    from atlas.worker_delivery_pilot_sessions s
    join atlas.worker_delivery_pilot_capabilities c on c.id=s.capability_id
    join atlas.organization_memberships om on om.id=c.organization_membership_id and om.active=true and om.role='member'
    join atlas.farm_memberships fm on fm.id=c.delivery_membership_id and fm.active=true and fm.role='farm_hand'
      and fm.user_id=om.user_id and fm.identity_subject_id=om.identity_subject_id
    join atlas.farms f on f.id=fm.farm_id and f.organization_id=om.organization_id and f.organization_unit_id is not null
    join atlas.organization_employee_seats seat on seat.organization_id=om.organization_id
      and seat.organization_membership_id=om.id and seat.identity_subject_id=om.identity_subject_id
      and seat.seat_class='employee' and seat.status='active' and seat.billing_state in ('active','waived')
    join atlas.organization_position_appointments appt on appt.organization_id=om.organization_id
      and appt.organization_membership_id=om.id and appt.identity_subject_id=om.identity_subject_id
      and appt.status='active' and appt.begins_at<=clock_timestamp() and (appt.ends_at is null or appt.ends_at>clock_timestamp())
    join atlas.organization_positions pos on pos.id=appt.position_id and pos.organization_id=om.organization_id
      and pos.organization_unit_id=f.organization_unit_id and pos.status='active'
    where s.session_token_hash=p_session_token_hash and s.revoked_at is null and s.expires_at>clock_timestamp()
      and c.revoked_at is null and c.expires_at>clock_timestamp() and c.scope='anna_worker_day_pilot'
      and atlas.organization_membership_eligible_on_date_v1(om.id,om.organization_id,(clock_timestamp() at time zone 'America/Chicago')::date)
      and atlas.farm_membership_eligible_on_date_v1(fm.id,fm.farm_id,(clock_timestamp() at time zone 'America/Chicago')::date)
    limit 1
  ),jsonb_build_object('ok',false,'code','invalid_or_expired_session'));
$function$;

alter table atlas.worker_delivery_pilot_events add column if not exists actor_user_id uuid references auth.users(id) on delete restrict;
alter table atlas.worker_delivery_pilot_events alter column session_id drop not null;
alter table atlas.worker_delivery_pilot_events drop constraint if exists worker_delivery_pilot_events_actor_check;
alter table atlas.worker_delivery_pilot_events add constraint worker_delivery_pilot_events_actor_check check (num_nonnulls(session_id,actor_user_id)=1);
create index if not exists worker_delivery_pilot_events_actor_user_idx on atlas.worker_delivery_pilot_events(actor_user_id,event_seq);

create or replace function atlas.worker_delivery_employee_transition_self_api_v1(
  p_delivery_membership_id uuid,
  p_action text,
  p_projection_id uuid default null,
  p_effective_at timestamptz default null,
  p_reported_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid(); v_farm_id uuid; v_context jsonb; v_organization_id uuid; v_organization_membership_id uuid;
  v_title text; v_active atlas.worker_delivery_pilot_active_attention%rowtype; v_active_title text;
  v_now timestamptz:=clock_timestamp(); v_effective timestamptz:=coalesce(p_effective_at,clock_timestamp());
  v_event_id uuid; v_latest_completion text; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if v_uid is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if v_action not in ('start','stop','done','reopen','switch_finish','switch_stop','report_unscheduled') then return jsonb_build_object('ok',false,'code','unsupported_action'); end if;
  select fm.farm_id into v_farm_id from atlas.farm_memberships fm where fm.id=p_delivery_membership_id;
  if v_farm_id is null then return jsonb_build_object('ok',false,'code','worker_context_not_found'); end if;
  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,p_delivery_membership_id);
  if not coalesce((v_context->>'ok')::boolean,false) then return jsonb_build_object('ok',false,'code','employee_access_required','reason',v_context->>'reason'); end if;
  v_organization_id:=(v_context->>'organizationId')::uuid; v_organization_membership_id:=(v_context->>'organizationMembershipId')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(p_delivery_membership_id::text,0));

  if v_action='report_unscheduled' then
    if nullif(btrim(p_reported_title),'') is null or length(btrim(p_reported_title))>240 then return jsonb_build_object('ok',false,'code','title_required'); end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,reported_title,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,null,null,v_uid,'unscheduled_work_reported',v_effective,btrim(p_reported_title),jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId')) returning id into v_event_id;
    return jsonb_build_object('ok',true,'status','unscheduled_recorded','eventId',v_event_id);
  end if;

  if p_projection_id is null then return jsonb_build_object('ok',false,'code','projection_required'); end if;
  select p.title into v_title from atlas.worker_week_projection p where p.id=p_projection_id and p.membership_id=p_delivery_membership_id and p.organization_id=v_organization_id and p.organization_membership_id=v_organization_membership_id;
  if v_title is null then return jsonb_build_object('ok',false,'code','projection_not_found'); end if;
  select e.event_kind into v_latest_completion from atlas.worker_delivery_pilot_events e where e.projection_id=p_projection_id and e.delivery_membership_id=p_delivery_membership_id and e.organization_membership_id=v_organization_membership_id and e.event_kind in ('done_reported','completion_reopened') order by e.event_seq desc limit 1;
  select * into v_active from atlas.worker_delivery_pilot_active_attention where delivery_membership_id=p_delivery_membership_id for update;

  if v_action='start' then
    if v_latest_completion='done_reported' then return jsonb_build_object('ok',false,'code','already_completed'); end if;
    if v_active.delivery_membership_id is not null then
      if v_active.projection_id=p_projection_id then return jsonb_build_object('ok',true,'status','already_active'); end if;
      select p.title into v_active_title from atlas.worker_week_projection p where p.id=v_active.projection_id and p.membership_id=p_delivery_membership_id and p.organization_id=v_organization_id and p.organization_membership_id=v_organization_membership_id;
      return jsonb_build_object('ok',false,'code','attention_conflict','activeProjectionId',v_active.projection_id,'activeTitle',coalesce(v_active_title,'Previous task'));
    end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'start',v_effective,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId')) returning id into v_event_id;
    insert into atlas.worker_delivery_pilot_active_attention(delivery_membership_id,projection_id,start_event_id,started_effective_at,updated_at) values(p_delivery_membership_id,p_projection_id,v_event_id,v_effective,v_now);
    return jsonb_build_object('ok',true,'status','started');
  elsif v_action='stop' then
    if v_active.delivery_membership_id is null or v_active.projection_id<>p_projection_id then return jsonb_build_object('ok',true,'status','not_active'); end if;
    if v_effective>v_now+interval '1 minute' or v_effective<v_active.started_effective_at then return jsonb_build_object('ok',false,'code','invalid_stop_time'); end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'stop',v_effective,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
    delete from atlas.worker_delivery_pilot_active_attention where delivery_membership_id=p_delivery_membership_id;
    return jsonb_build_object('ok',true,'status','stopped');
  elsif v_action='done' then
    if v_latest_completion='done_reported' then return jsonb_build_object('ok',true,'status','already_completed'); end if;
    if v_active.delivery_membership_id is not null and v_active.projection_id=p_projection_id then
      insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
      values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'stop',v_effective,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
      delete from atlas.worker_delivery_pilot_active_attention where delivery_membership_id=p_delivery_membership_id;
    end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'done_reported',v_effective,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
    return jsonb_build_object('ok',true,'status','done_reported');
  elsif v_action='reopen' then
    if v_latest_completion<>'done_reported' then return jsonb_build_object('ok',true,'status','already_open'); end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'completion_reopened',v_effective,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
    return jsonb_build_object('ok',true,'status','reopened');
  elsif v_action in ('switch_finish','switch_stop') then
    if v_latest_completion='done_reported' then return jsonb_build_object('ok',false,'code','already_completed'); end if;
    if v_active.delivery_membership_id is null then
      insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
      values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'start',v_now,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId')) returning id into v_event_id;
      insert into atlas.worker_delivery_pilot_active_attention(delivery_membership_id,projection_id,start_event_id,started_effective_at,updated_at) values(p_delivery_membership_id,p_projection_id,v_event_id,v_now,v_now);
      return jsonb_build_object('ok',true,'status','started');
    end if;
    if v_active.projection_id=p_projection_id then return jsonb_build_object('ok',true,'status','already_active'); end if;
    if v_action='switch_stop' and (v_effective>v_now+interval '1 minute' or v_effective<v_active.started_effective_at) then return jsonb_build_object('ok',false,'code','invalid_stop_time'); end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,v_active.projection_id,null,v_uid,'stop',case when v_action='switch_stop' then v_effective else v_now end,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
    if v_action='switch_finish' then
      insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
      values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,v_active.projection_id,null,v_uid,'done_reported',v_now,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId'));
    end if;
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_organization_id,v_organization_membership_id,p_delivery_membership_id,p_projection_id,null,v_uid,'start',v_now,jsonb_build_object('source','organization_employee_seat','employeeSeatId',v_context->>'employeeSeatId')) returning id into v_event_id;
    update atlas.worker_delivery_pilot_active_attention set projection_id=p_projection_id,start_event_id=v_event_id,started_effective_at=v_now,updated_at=v_now where delivery_membership_id=p_delivery_membership_id;
    return jsonb_build_object('ok',true,'status','switched');
  end if;
  return jsonb_build_object('ok',false,'code','unsupported_action');
end;
$function$;

revoke all on function atlas.worker_delivery_employee_transition_self_api_v1(uuid,text,uuid,timestamptz,text) from public,anon;
grant execute on function atlas.worker_delivery_employee_transition_self_api_v1(uuid,text,uuid,timestamptz,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected)
values('atlas.worker_delivery_employee_transition_self_api_v1(uuid, text, uuid, timestamp with time zone, text)','app_endpoint','verified','active',true,true,true,1,1,
jsonb_build_object('source','atlas_employee_worker_surface_boundary_v1','purpose','Record current Worker Day attention and reporting events for the signed-in organization employee.','truthBoundary','Requires the same institutional person across active farm membership, organization membership, employee seat, authenticated credential, and current position appointment. Projection assignment limits action scope; no new responsibility or authority is created.','classificationRuleVersion',3),false)
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,anonymous_execute_expected=excluded.anonymous_execute_expected,reviewed_at=now();

commit;