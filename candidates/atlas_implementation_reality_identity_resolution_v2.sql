begin;

-- Atlas Implementation Reality Identity Resolution v2
--
-- Additive current-contract resolver membrane.
--
-- v1 remains the owning resolver for:
--   organization
--   person
--   organization_position
--   organization_responsibility
--
-- v2 adds:
--   organization_unit
--
-- Governing boundary:
--   typed label != canonical identity.
--
-- An assigned practitioner may resolve only canonical identities already
-- reachable through Organizations bound to the current Implementation Case.
-- This membrane never creates, merges, renames, establishes, or mutates truth.

do $prerequisites$
begin
  if to_regprocedure(
    'atlas.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)'
  ) is null then
    raise exception 'Implementation Reality identity resolver v1 must be live before v2.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)'
  ) is null then
    raise exception 'Implementation practitioner case authority is unavailable.'
      using errcode='0A000';
  end if;

  if to_regclass('atlas.organization_units') is null
     or to_regclass('atlas.organizations') is null
     or to_regclass('atlas.ledger_entitlement_bindings') is null then
    raise exception 'Canonical Organization Unit scope substrate is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

create or replace function atlas.implementation_reality_identity_options_self_api_v2(
  p_implementation_case_id uuid,
  p_kind text,
  p_query text default null,
  p_limit integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_query text := lower(btrim(coalesce(p_query,'')));
  v_limit integer := least(greatest(coalesce(p_limit,12),1),25);
  v_scope_count integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    p_implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  if p_kind not in (
    'organization',
    'person',
    'organization_unit',
    'organization_position',
    'organization_responsibility'
  ) then
    raise exception 'Unsupported Reality identity kind.'
      using errcode='22023';
  end if;

  if p_kind <> 'organization_unit' then
    v_result := atlas.implementation_reality_identity_options_self_api_v1(
      p_implementation_case_id,
      p_kind,
      p_query,
      p_limit
    );

    return jsonb_set(
      v_result,
      '{contractVersion}',
      to_jsonb('implementation_reality_identity_resolution_v2'::text),
      true
    );
  end if;

  select count(*)::integer
  into v_scope_count
  from (
    select distinct b.organization_id
    from atlas.ledger_entitlement_bindings b
    join atlas.organizations o
      on o.id=b.organization_id
     and o.status='active'
    where b.implementation_case_id=p_implementation_case_id
      and b.organization_id is not null
      and b.ended_at is null
      and b.state in ('bound','activated')
  ) scope_orgs;

  if v_scope_count=0 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_reality_identity_resolution_v2',
      'implementationCaseId',p_implementation_case_id,
      'kind',p_kind,
      'query',coalesce(p_query,''),
      'scopeState','unbound',
      'scopeOrganizationCount',0,
      'items','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(item order by match_rank,label,canonical_id),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      u.id as canonical_id,
      u.name as label,
      case
        when v_query<>'' and lower(u.name)=v_query then 0
        when v_query<>'' and strpos(lower(u.name),v_query)=1 then 1
        else 2
      end as match_rank,
      jsonb_strip_nulls(jsonb_build_object(
        'kind','organization_unit',
        'canonicalId',u.id,
        'label',u.name,
        'organizationId',o.id,
        'organizationLabel',o.name,
        'organizationUnitId',u.id,
        'organizationUnitLabel',u.name,
        'organizationUnitKind',u.unit_kind,
        'parentOrganizationUnitId',parent.id,
        'parentOrganizationUnitLabel',parent.name,
        'matchBasis','case_bound_organization_unit'
      )) as item
    from (
      select distinct b.organization_id
      from atlas.ledger_entitlement_bindings b
      join atlas.organizations bo
        on bo.id=b.organization_id
       and bo.status='active'
      where b.implementation_case_id=p_implementation_case_id
        and b.organization_id is not null
        and b.ended_at is null
        and b.state in ('bound','activated')
    ) scope_orgs
    join atlas.organizations o
      on o.id=scope_orgs.organization_id
     and o.status='active'
    join atlas.organization_units u
      on u.organization_id=o.id
     and u.status='active'
    left join atlas.organization_units parent
      on parent.id=u.parent_unit_id
     and parent.organization_id=o.id
     and parent.status='active'
    where v_query=''
       or strpos(lower(u.name),v_query)>0
    order by match_rank,u.name,u.id
    limit v_limit
  ) matches;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_identity_resolution_v2',
    'implementationCaseId',p_implementation_case_id,
    'kind',p_kind,
    'query',coalesce(p_query,''),
    'scopeState','bound',
    'scopeOrganizationCount',v_scope_count,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.implementation_reality_identity_options_self_api_v2(
  uuid,text,text,integer
) from public,anon,authenticated,service_role;

comment on function atlas.implementation_reality_identity_options_self_api_v2(
  uuid,text,text,integer
) is
  'Assigned-practitioner, case-scoped canonical identity lookup v2. Adds Organization Unit resolution while preserving v1 semantics for Organization, Person, Position, and Responsibility. It never creates or mutates identity.';

create or replace function public.implementation_reality_identity_options_self_api_v2(
  p_implementation_case_id uuid,
  p_kind text,
  p_query text default null,
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_reality_identity_options_self_api_v2(
    p_implementation_case_id,
    p_kind,
    p_query,
    p_limit
  );
$function$;

revoke all on function public.implementation_reality_identity_options_self_api_v2(
  uuid,text,text,integer
) from public,anon,service_role;

grant execute on function public.implementation_reality_identity_options_self_api_v2(
  uuid,text,text,integer
) to authenticated;

comment on function public.implementation_reality_identity_options_self_api_v2(
  uuid,text,text,integer
) is
  'Public Data API membrane for assigned-practitioner Reality identity lookup v2. Adds canonical Organization Unit options only from Organizations already bound to the current Implementation Case.';

commit;
