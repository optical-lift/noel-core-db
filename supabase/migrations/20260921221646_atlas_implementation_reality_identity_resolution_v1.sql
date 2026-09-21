begin;

-- Atlas Implementation Reality Identity Resolution v1
--
-- Governing boundary:
--   typed label != canonical identity.
--
-- An assigned practitioner may search only canonical identities already
-- reachable through an Organization bound to the current Implementation Case.
-- This membrane does not create, merge, rename, establish, or mutate identity.
-- It never searches across unbound Organizations.

create or replace function atlas.implementation_reality_identity_options_self_api_v1(
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
    'organization_position',
    'organization_responsibility'
  ) then
    raise exception 'Unsupported Reality identity kind.'
      using errcode='22023';
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
      'contractVersion','implementation_reality_identity_resolution_v1',
      'implementationCaseId',p_implementation_case_id,
      'kind',p_kind,
      'query',coalesce(p_query,''),
      'scopeState','unbound',
      'scopeOrganizationCount',0,
      'items','[]'::jsonb
    );
  end if;

  if p_kind='organization' then
    select coalesce(jsonb_agg(item order by match_rank,label,canonical_id),'[]'::jsonb)
    into v_items
    from (
      select
        o.id as canonical_id,
        o.name as label,
        case
          when v_query<>'' and lower(o.name)=v_query then 0
          when v_query<>'' and strpos(lower(o.name),v_query)=1 then 1
          else 2
        end as match_rank,
        jsonb_build_object(
          'kind','organization',
          'canonicalId',o.id,
          'label',o.name,
          'organizationId',o.id,
          'organizationLabel',o.name,
          'matchBasis','case_bound_organization'
        ) as item
      from (
        select distinct o.id,o.name
        from atlas.ledger_entitlement_bindings b
        join atlas.organizations o
          on o.id=b.organization_id
         and o.status='active'
        where b.implementation_case_id=p_implementation_case_id
          and b.organization_id is not null
          and b.ended_at is null
          and b.state in ('bound','activated')
      ) o
      where v_query='' or strpos(lower(o.name),v_query)>0
      order by match_rank,o.name,o.id
      limit v_limit
    ) matches;

  elsif p_kind='person' then
    -- Institutional Person Record is the canonical Organization-scoped Person
    -- reachability contract once that migration is live. The compatibility
    -- membership path keeps this resolver independently clone-validatable
    -- against the current production schema and is intentionally narrower.
    if to_regclass('atlas.institutional_person_records') is not null then
      execute $sql$
        select coalesce(jsonb_agg(item order by match_rank,label,canonical_id),'[]'::jsonb)
        from (
          select
            p.id as canonical_id,
            p.display_name as label,
            case
              when $2<>'' and lower(p.display_name)=$2 then 0
              when $2<>'' and strpos(lower(p.display_name),$2)=1 then 1
              else 2
            end as match_rank,
            jsonb_build_object(
              'kind','person',
              'canonicalId',p.id,
              'label',p.display_name,
              'organizationId',o.id,
              'organizationLabel',o.name,
              'matchBasis','institutional_person_record'
            ) as item
          from (
            select distinct b.organization_id
            from atlas.ledger_entitlement_bindings b
            join atlas.organizations bo
              on bo.id=b.organization_id
             and bo.status='active'
            where b.implementation_case_id=$1
              and b.organization_id is not null
              and b.ended_at is null
              and b.state in ('bound','activated')
          ) scope_orgs
          join atlas.organizations o on o.id=scope_orgs.organization_id
          join atlas.institutional_person_records ipr
            on ipr.organization_id=o.id
           and ipr.status='active'
          join atlas.people p
            on p.id=ipr.person_id
           and p.status='active'
          where $2='' or strpos(lower(p.display_name),$2)>0
          order by match_rank,p.display_name,p.id
          limit $3
        ) matches
      $sql$
      into v_items
      using p_implementation_case_id,v_query,v_limit;
    else
      select coalesce(jsonb_agg(item order by match_rank,label,canonical_id),'[]'::jsonb)
      into v_items
      from (
        select *
        from (
          select distinct on (p.id,o.id)
            p.id as canonical_id,
            p.display_name as label,
            case
              when v_query<>'' and lower(p.display_name)=v_query then 0
              when v_query<>'' and strpos(lower(p.display_name),v_query)=1 then 1
              else 2
            end as match_rank,
            jsonb_build_object(
              'kind','person',
              'canonicalId',p.id,
              'label',p.display_name,
              'organizationId',o.id,
              'organizationLabel',o.name,
              'matchBasis','organization_membership_compatibility'
            ) as item
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
          join atlas.organizations o on o.id=scope_orgs.organization_id
          join atlas.organization_memberships m
            on m.organization_id=o.id
           and m.active
           and m.person_id is not null
          join atlas.people p
            on p.id=m.person_id
           and p.status='active'
          where v_query='' or strpos(lower(p.display_name),v_query)>0
          order by p.id,o.id,match_rank,p.display_name
        ) deduped
        order by match_rank,label,canonical_id
        limit v_limit
      ) matches;
    end if;

  elsif p_kind='organization_position' then
    select coalesce(jsonb_agg(item order by match_rank,label,canonical_id),'[]'::jsonb)
    into v_items
    from (
      select
        p.id as canonical_id,
        p.display_title as label,
        case
          when v_query<>'' and lower(p.display_title)=v_query then 0
          when v_query<>'' and strpos(lower(p.display_title),v_query)=1 then 1
          else 2
        end as match_rank,
        jsonb_strip_nulls(jsonb_build_object(
          'kind','organization_position',
          'canonicalId',p.id,
          'label',p.display_title,
          'organizationId',o.id,
          'organizationLabel',o.name,
          'organizationUnitId',u.id,
          'organizationUnitLabel',u.name,
          'matchBasis','organization_position'
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
      join atlas.organizations o on o.id=scope_orgs.organization_id
      join atlas.organization_positions p
        on p.organization_id=o.id
       and p.status='active'
      left join atlas.organization_units u
        on u.id=p.organization_unit_id
       and u.organization_id=o.id
       and u.status='active'
      where v_query='' or strpos(lower(p.display_title),v_query)>0
      order by match_rank,p.display_title,p.id
      limit v_limit
    ) matches;

  elsif p_kind='organization_responsibility' then
    select coalesce(jsonb_agg(item order by match_rank,label,canonical_id),'[]'::jsonb)
    into v_items
    from (
      select
        r.id as canonical_id,
        r.name as label,
        case
          when v_query<>'' and lower(r.name)=v_query then 0
          when v_query<>'' and strpos(lower(r.name),v_query)=1 then 1
          else 2
        end as match_rank,
        jsonb_build_object(
          'kind','organization_responsibility',
          'canonicalId',r.id,
          'label',r.name,
          'organizationId',o.id,
          'organizationLabel',o.name,
          'matchBasis','organization_responsibility'
        ) as item
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
      join atlas.organizations o on o.id=scope_orgs.organization_id
      join atlas.organization_responsibilities r
        on r.organization_id=o.id
       and r.status='active'
      where v_query='' or strpos(lower(r.name),v_query)>0
      order by match_rank,r.name,r.id
      limit v_limit
    ) matches;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_identity_resolution_v1',
    'implementationCaseId',p_implementation_case_id,
    'kind',p_kind,
    'query',coalesce(p_query,''),
    'scopeState','bound',
    'scopeOrganizationCount',v_scope_count,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.implementation_reality_identity_options_self_api_v1(
  uuid,text,text,integer
) from public,anon,authenticated,service_role;

comment on function atlas.implementation_reality_identity_options_self_api_v1(
  uuid,text,text,integer
) is
  'Assigned-practitioner, case-scoped canonical identity lookup for Reality Sentence binding. Search is restricted to Organizations already bound to the Implementation Case and never creates or mutates identity.';


create or replace function public.implementation_reality_identity_options_self_api_v1(
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
  select atlas.implementation_reality_identity_options_self_api_v1(
    p_implementation_case_id,
    p_kind,
    p_query,
    p_limit
  );
$function$;

revoke all on function public.implementation_reality_identity_options_self_api_v1(
  uuid,text,text,integer
) from public,anon,service_role;

grant execute on function public.implementation_reality_identity_options_self_api_v1(
  uuid,text,text,integer
) to authenticated;

comment on function public.implementation_reality_identity_options_self_api_v1(
  uuid,text,text,integer
) is
  'Public Data API membrane for assigned-practitioner Reality identity lookup. Returns canonical options only from Organizations already bound to the current Implementation Case.';

commit;
