begin;

-- Atlas effective Person↔Organization responsibility read v1
--
-- This tranche is intentionally read-only. It establishes one canonical current
-- responsibility read over existing canonical Person + Organization Membership +
-- Position Appointment + Position→Responsibility + Responsibility Scope source
-- facts. Employee seats/credentials, Farm Memberships, and exact Company Work
-- allocations remain separate access, delivery, and exact-work substrates.
--
-- Historical position-definition reconstruction is deliberately not claimed here:
-- organization_position_responsibilities and organization_responsibility_scopes
-- do not yet carry append-only lifecycle history. This function therefore answers
-- only the current-position question.

create or replace function atlas.effective_person_organization_responsibilities_current_v1(
  p_person_id uuid,
  p_organization_id uuid default null
)
returns table(
  person_id uuid,
  person_display_name text,
  organization_id uuid,
  organization_key text,
  organization_name text,
  organization_membership_id uuid,
  identity_subject_id uuid,
  appointment_id uuid,
  appointment_kind text,
  position_id uuid,
  position_key text,
  position_title text,
  position_kind text,
  organization_unit_id uuid,
  organization_unit_key text,
  organization_unit_name text,
  organization_unit_kind text,
  responsibility_id uuid,
  responsibility_key text,
  responsibility_name text,
  responsibility_kind text,
  position_responsibility_kind text,
  scope_link_id uuid,
  scope_kind text,
  scope_id text,
  scope_relation_kind text,
  resolution_state text,
  evidence jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select
    pe.id as person_id,
    pe.display_name as person_display_name,
    o.id as organization_id,
    o.stable_key as organization_key,
    o.name as organization_name,
    m.id as organization_membership_id,
    m.identity_subject_id,
    a.id as appointment_id,
    a.appointment_kind,
    p.id as position_id,
    p.stable_key as position_key,
    p.display_title as position_title,
    p.position_kind,
    u.id as organization_unit_id,
    u.stable_key as organization_unit_key,
    u.name as organization_unit_name,
    u.unit_kind as organization_unit_kind,
    r.id as responsibility_id,
    r.stable_key as responsibility_key,
    r.name as responsibility_name,
    r.responsibility_kind,
    pr.relationship_kind as position_responsibility_kind,
    rs.id as scope_link_id,
    rs.scope_kind,
    rs.scope_id,
    rs.relation_kind as scope_relation_kind,
    case
      when rs.scope_kind='organization_unit' and su.id is not null then 'established_current'::text
      else 'indeterminate'::text
    end as resolution_state,
    jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','effective_person_organization_responsibilities_current_v1',
      'personId',pe.id,
      'organizationMembershipId',m.id,
      'identitySubjectId',m.identity_subject_id,
      'appointmentId',a.id,
      'positionId',p.id,
      'responsibilityId',r.id,
      'scopeLinkId',rs.id,
      'scopeResolution',case
        when rs.scope_kind<>'organization_unit' then 'unsupported_scope_kind'
        when su.id is null then 'organization_unit_unresolved'
        else 'resolved'
      end,
      'resolvedScopeOrganizationUnitId',su.id,
      'currentOnly',true,
      'historicalDefinitionReconstruction','not_yet_available'
    )) as evidence
  from atlas.people pe
  join atlas.organization_memberships m
    on m.person_id=pe.id
   and m.active=true
  join atlas.organizations o
    on o.id=m.organization_id
   and o.status='active'
  join atlas.organization_position_appointments a
    on a.organization_id=m.organization_id
   and a.organization_membership_id=m.id
   and a.identity_subject_id=m.identity_subject_id
   and a.status='active'
   and a.begins_at<=now()
   and (a.ends_at is null or a.ends_at>now())
  join atlas.organization_positions p
    on p.id=a.position_id
   and p.organization_id=m.organization_id
   and p.status='active'
  join atlas.organization_units u
    on u.id=p.organization_unit_id
   and u.organization_id=p.organization_id
   and u.status='active'
  join atlas.organization_position_responsibilities pr
    on pr.position_id=p.id
  join atlas.organization_responsibilities r
    on r.id=pr.responsibility_id
   and r.organization_id=m.organization_id
   and r.status='active'
  join atlas.organization_responsibility_scopes rs
    on rs.organization_id=m.organization_id
   and rs.responsibility_id=r.id
  left join atlas.organization_units su
    on rs.scope_kind='organization_unit'
   and su.id=case
     when rs.scope_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       then rs.scope_id::uuid
     else null
   end
   and su.organization_id=rs.organization_id
   and su.status='active'
  where pe.id=p_person_id
    and pe.status='active'
    and (p_organization_id is null or m.organization_id=p_organization_id)
    and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
    and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date)
  order by o.stable_key,u.stable_key,p.stable_key,r.stable_key,rs.scope_kind,rs.scope_id,rs.id;
$function$;

comment on function atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid) is
  'Canonical current effective Person↔Organization durable-responsibility read. Derives responsibility from canonical Person, active Organization Membership, active Position Appointment, current Position→Responsibility definition, and current Responsibility Scope. Scope rows that cannot resolve to a supported active governed target are emitted as indeterminate rather than promoted into responsibility truth. Current-only: mutable definition history is not yet reconstructable. Seat/credential, Farm Membership, visibility, action authority, custody, and exact Company Work allocation are intentionally not inferred here.';

revoke all on function atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)
  from public, anon, authenticated;
grant execute on function atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)
  to postgres, service_role;

create or replace function atlas.resolve_person_organization_responsibility_current_v1(
  p_person_id uuid,
  p_organization_id uuid,
  p_responsibility_id uuid,
  p_scope_kind text default null,
  p_scope_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_person atlas.people%rowtype;
  v_org atlas.organizations%rowtype;
  v_responsibility atlas.organization_responsibilities%rowtype;
  v_membership_count integer:=0;
  v_missing_subject boolean:=false;
  v_appointment_count integer:=0;
  v_linked_count integer:=0;
  v_scope_count integer:=0;
  v_resolved_scope_count integer:=0;
  v_indeterminate_scope_count integer:=0;
  v_requested_scope_resolves boolean:=false;
  v_items jsonb;
begin
  if p_person_id is null or p_organization_id is null or p_responsibility_id is null then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','required_identity_missing',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  if (p_scope_kind is null) <> (p_scope_id is null) then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','scope_identity_incomplete',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'scopeKind',p_scope_kind,
      'scopeId',p_scope_id
    );
  end if;

  select * into v_person
  from atlas.people pe
  where pe.id=p_person_id;

  if v_person.id is null or v_person.status<>'active' then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','person_not_active',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select * into v_org
  from atlas.organizations o
  where o.id=p_organization_id;

  if v_org.id is null or v_org.status<>'active' then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','organization_not_active',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select * into v_responsibility
  from atlas.organization_responsibilities r
  where r.id=p_responsibility_id
    and r.organization_id=p_organization_id;

  if v_responsibility.id is null or v_responsibility.status<>'active' then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','responsibility_not_active_in_organization',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  if p_scope_kind is not null and p_scope_kind<>'organization_unit' then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','requested_scope_kind_not_supported',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'scopeKind',p_scope_kind,
      'scopeId',p_scope_id
    );
  end if;

  if p_scope_kind='organization_unit' then
    if p_scope_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object(
        'state','indeterminate',
        'reason','requested_scope_unresolved',
        'personId',p_person_id,
        'organizationId',p_organization_id,
        'responsibilityId',p_responsibility_id,
        'scopeKind',p_scope_kind,
        'scopeId',p_scope_id
      );
    end if;

    select exists(
      select 1
      from atlas.organization_units su
      where su.id=p_scope_id::uuid
        and su.organization_id=p_organization_id
        and su.status='active'
    ) into v_requested_scope_resolves;

    if not v_requested_scope_resolves then
      return jsonb_build_object(
        'state','indeterminate',
        'reason','requested_scope_unresolved',
        'personId',p_person_id,
        'organizationId',p_organization_id,
        'responsibilityId',p_responsibility_id,
        'scopeKind',p_scope_kind,
        'scopeId',p_scope_id
      );
    end if;
  end if;

  select count(*)::integer,
         coalesce(bool_or(m.identity_subject_id is null),false)
    into v_membership_count,v_missing_subject
  from atlas.organization_memberships m
  where m.person_id=p_person_id
    and m.organization_id=p_organization_id
    and m.active=true
    and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
    and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date);

  if v_membership_count=0 then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','no_current_person_organization_membership',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  if v_membership_count>1 then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','multiple_current_person_organization_memberships',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'membershipCount',v_membership_count
    );
  end if;

  if v_missing_subject then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','institutional_identity_subject_missing',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select count(*)::integer into v_appointment_count
  from atlas.organization_memberships m
  join atlas.organization_position_appointments a
    on a.organization_id=m.organization_id
   and a.organization_membership_id=m.id
   and a.identity_subject_id=m.identity_subject_id
   and a.status='active'
   and a.begins_at<=now()
   and (a.ends_at is null or a.ends_at>now())
  join atlas.organization_positions p
    on p.id=a.position_id
   and p.organization_id=m.organization_id
   and p.status='active'
  join atlas.organization_units u
    on u.id=p.organization_unit_id
   and u.organization_id=p.organization_id
   and u.status='active'
  where m.person_id=p_person_id
    and m.organization_id=p_organization_id
    and m.active=true
    and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
    and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date);

  if v_appointment_count=0 then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','no_current_position_appointment',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select count(*)::integer into v_linked_count
  from atlas.organization_memberships m
  join atlas.organization_position_appointments a
    on a.organization_id=m.organization_id
   and a.organization_membership_id=m.id
   and a.identity_subject_id=m.identity_subject_id
   and a.status='active'
   and a.begins_at<=now()
   and (a.ends_at is null or a.ends_at>now())
  join atlas.organization_positions p
    on p.id=a.position_id
   and p.organization_id=m.organization_id
   and p.status='active'
  join atlas.organization_position_responsibilities pr
    on pr.position_id=p.id
   and pr.responsibility_id=p_responsibility_id
  where m.person_id=p_person_id
    and m.organization_id=p_organization_id
    and m.active=true
    and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
    and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date);

  if v_linked_count=0 then
    return jsonb_build_object(
      'state','established_not_current',
      'reason','responsibility_not_in_current_appointed_position',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select count(*)::integer into v_scope_count
  from atlas.organization_responsibility_scopes rs
  where rs.organization_id=p_organization_id
    and rs.responsibility_id=p_responsibility_id;

  if v_scope_count=0 then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','current_responsibility_scope_missing',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id
    );
  end if;

  select
    count(*) filter (where x.resolution_state='established_current')::integer,
    count(*) filter (where x.resolution_state='indeterminate')::integer
    into v_resolved_scope_count,v_indeterminate_scope_count
  from atlas.effective_person_organization_responsibilities_current_v1(p_person_id,p_organization_id) x
  where x.responsibility_id=p_responsibility_id;

  if v_resolved_scope_count=0 then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','current_responsibility_scope_unresolved',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'scopeRowCount',v_scope_count,
      'indeterminateScopeCount',v_indeterminate_scope_count
    );
  end if;

  if p_scope_kind is null and v_indeterminate_scope_count>0 then
    return jsonb_build_object(
      'state','indeterminate',
      'reason','current_responsibility_scope_partially_unresolved',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'resolvedScopeCount',v_resolved_scope_count,
      'indeterminateScopeCount',v_indeterminate_scope_count
    );
  end if;

  select jsonb_agg(to_jsonb(x) order by x.position_key,x.responsibility_key,x.scope_kind,x.scope_id,x.scope_link_id)
    into v_items
  from atlas.effective_person_organization_responsibilities_current_v1(p_person_id,p_organization_id) x
  where x.responsibility_id=p_responsibility_id
    and x.resolution_state='established_current'
    and (p_scope_kind is null or (x.scope_kind=p_scope_kind and x.scope_id=p_scope_id));

  if v_items is not null then
    return jsonb_build_object(
      'state','established_current',
      'reason','current_institutional_responsibility_established',
      'personId',p_person_id,
      'organizationId',p_organization_id,
      'responsibilityId',p_responsibility_id,
      'scopeKind',p_scope_kind,
      'scopeId',p_scope_id,
      'items',v_items,
      'currentOnly',true,
      'historicalDefinitionReconstruction','not_yet_available'
    );
  end if;

  return jsonb_build_object(
    'state','established_not_current',
    'reason',case when p_scope_kind is null then 'responsibility_not_current' else 'responsibility_not_current_for_requested_scope' end,
    'personId',p_person_id,
    'organizationId',p_organization_id,
    'responsibilityId',p_responsibility_id,
    'scopeKind',p_scope_kind,
    'scopeId',p_scope_id
  );
end;
$function$;

comment on function atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text) is
  'Exact current durable-responsibility resolver. Returns established_current, established_not_current, or indeterminate. Unsupported, dangling, or otherwise unresolved bounded Scope evidence fails closed to indeterminate. It delegates established-current evidence to effective_person_organization_responsibilities_current_v1 and does not infer responsibility from employee seat, credential, Farm Membership, visibility, authority, custody, or Company Work allocation.';

revoke all on function atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)
  to postgres, service_role;

insert into atlas.architecture_truth_authorities(
  authority_key,
  domain_key,
  truth_question,
  authority_owner,
  authority_status,
  canonical_relations,
  canonical_functions,
  supporting_relations,
  consumer_surfaces,
  known_competitors,
  source_custody,
  rationale
) values (
  'person_organization_current_durable_responsibility',
  'institutional_responsibility',
  'What bounded Organization responsibility does this canonical Person currently carry through current institutional placement?',
  'atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)',
  'canonical',
  array[
    'atlas.people',
    'atlas.organization_memberships',
    'atlas.organization_position_appointments',
    'atlas.organization_positions',
    'atlas.organization_position_responsibilities',
    'atlas.organization_responsibilities',
    'atlas.organization_responsibility_scopes',
    'atlas.organization_units'
  ],
  array[
    'atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)',
    'atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)'
  ],
  array[
    'atlas.organizations',
    'atlas.identity_subjects',
    'atlas.organization_employee_seats',
    'atlas.organization_member_credentials',
    'atlas.farm_memberships',
    'atlas.work_allocations'
  ],
  array[
    'future Person-specific Ledger projection',
    'future /anna durable-responsibility projection',
    'future governed effect-uptake relationship evidence'
  ],
  array[
    'organization_employee_seats treated as responsibility evidence',
    'organization_memberships.role treated as durable responsibility',
    'farm_memberships.role treated as Organization responsibility',
    'organization_positions.display_title treated as sufficient responsibility evidence',
    'work_allocations treated as standing institutional responsibility',
    'unresolved or unsupported responsibility Scope rows treated as established responsibility',
    'current Position→Responsibility or Scope rows projected backward as historical truth'
  ],
  'optical-lift/noel-core-db:supabase/migrations',
  'Current durable responsibility is derived from canonical Person identity, current Organization affiliation, current Position Appointment, the current Position responsibility definition, and bounded Responsibility Scope. Unsupported or unresolved Scope evidence fails closed. Seats/credentials are access-commercial mechanics, Farm Membership is a domain execution adapter, and work_allocations carry exact Company Work responsibility. This authority is intentionally current-only until append-only position/responsibility/scope definition history exists.'
)
on conflict (authority_key)
do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

-- Browser clients must not gain direct execution in this tranche.
do $verification$
begin
  if has_function_privilege('anon','atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)','EXECUTE') then
    raise exception 'effective durable-responsibility read must remain internal';
  end if;

  if has_function_privilege('anon','atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)','EXECUTE') then
    raise exception 'effective durable-responsibility resolver must remain internal';
  end if;
end;
$verification$;

commit;
