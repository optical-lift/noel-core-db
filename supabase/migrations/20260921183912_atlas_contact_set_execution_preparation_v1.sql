begin;

create table if not exists atlas.contact_set_execution_runs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references atlas.contact_set_intent_requests(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null,
  execution_state text not null,
  required_fields text[] not null default '{}'::text[],
  desired_count integer null,
  selected_count integer not null default 0,
  directory_snapshot jsonb not null default '{}'::jsonb,
  gap_snapshot jsonb not null default '{}'::jsonb,
  ledger_effect_snapshot jsonb not null default '{}'::jsonb,
  prepared_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contact_set_execution_runs_state_check check (
    execution_state in ('prepared','needs_acquisition','ready','partial','closed','cancelled')
  ),
  constraint contact_set_execution_runs_required_fields_check check (
    cardinality(required_fields)>0
  ),
  constraint contact_set_execution_runs_desired_count_check check (
    desired_count is null or desired_count>0
  ),
  constraint contact_set_execution_runs_selected_count_check check (selected_count>=0),
  constraint contact_set_execution_runs_directory_object check (jsonb_typeof(directory_snapshot)='object'),
  constraint contact_set_execution_runs_gap_object check (jsonb_typeof(gap_snapshot)='object'),
  constraint contact_set_execution_runs_ledger_object check (jsonb_typeof(ledger_effect_snapshot)='object'),
  constraint contact_set_execution_runs_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict
);

create index if not exists contact_set_execution_runs_org_state_idx
  on atlas.contact_set_execution_runs(organization_id,execution_state,prepared_at desc);

alter table atlas.contact_set_execution_runs enable row level security;
revoke all on table atlas.contact_set_execution_runs from public,anon,authenticated,service_role;

comment on table atlas.contact_set_execution_runs is
'Organization-private durable Atlas Intelligence execution snapshot for build_target_contact_set. Stores existing-reality results, exact acquisition gaps and private Ledger effects; owns no Shared Intelligence truth.';

create or replace function atlas.shared_directory_target_search_service_v1(
  p_organization_id uuid,
  p_target jsonb,
  p_geography jsonb default null,
  p_required_fields text[] default '{}'::text[],
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_org_kinds text[]:='{}'::text[];
  v_named_orgs text[]:='{}'::text[];
  v_person_functions text[]:='{}'::text[];
  v_titles text[]:='{}'::text[];
  v_places text[]:='{}'::text[];
  v_required text[]:='{}'::text[];
  v_person_requested boolean:=false;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),200));
  v_items jsonb:='[]'::jsonb;
  v_research jsonb:='[]'::jsonb;
  v_candidate_count integer:=0;
  v_ready_count integer:=0;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;
  if p_target is null or jsonb_typeof(p_target)<>'object' then
    raise exception 'Target must be a JSON object.' using errcode='22023';
  end if;
  if p_geography is not null and jsonb_typeof(p_geography)<>'object' then
    raise exception 'Geography must be a JSON object or null.' using errcode='22023';
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_org_kinds
  from jsonb_array_elements_text(coalesce(p_target->'organizationKinds','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_named_orgs
  from jsonb_array_elements_text(coalesce(p_target->'namedOrganizations','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_person_functions
  from jsonb_array_elements_text(coalesce(p_target->'personFunctions','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_titles
  from jsonb_array_elements_text(coalesce(p_target->'titles','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_places
  from jsonb_array_elements_text(coalesce(p_geography->'placeLabels','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_required
  from unnest(coalesce(p_required_fields,'{}'::text[])) x;

  if cardinality(v_required)=0 then
    raise exception 'At least one required field is required.' using errcode='22023';
  end if;

  v_person_requested:=cardinality(v_person_functions)>0 or cardinality(v_titles)>0;

  with organization_candidates as (
    select
      e.id,
      e.name,
      e.entity_type,
      e.description,
      e.website_url,
      e.phone,
      e.email,
      e.address_line1,
      e.city,
      e.state,
      e.postal_code,
      e.metadata,
      e.verification_state,
      e.last_verified_at,
      (
        exists(
          select 1 from unnest(v_named_orgs) q
          where lower(e.name) like '%'||q||'%'
        )
      )::int*10
      + (
        exists(
          select 1 from unnest(v_org_kinds) q
          where lower(concat_ws(' ',
            e.name,coalesce(e.description,''),coalesce(e.metadata::text,''),
            coalesce(oip.legal_name,''),coalesce(oip.local_unit_name,''),
            coalesce(oip.metadata::text,'')
          )) like '%'||replace(q,'_',' ')||'%'
          or lower(concat_ws(' ',
            e.name,coalesce(e.description,''),coalesce(e.metadata::text,'')
          )) like '%'||q||'%'
        )
      )::int*5
      + (
        exists(
          select 1 from unnest(v_places) q
          where lower(coalesce(e.city,''))=q
             or lower(coalesce(e.city,'')) like '%'||q||'%'
             or lower(coalesce(e.address_line1,'')) like '%'||q||'%'
        )
      )::int*3 as target_score
    from local_intel.entities e
    left join local_intel.organization_identity_profiles oip on oip.entity_id=e.id
    where e.status='active'
      and e.entity_type<>'person'
      and (
        cardinality(v_named_orgs)=0
        or exists(select 1 from unnest(v_named_orgs) q where lower(e.name) like '%'||q||'%')
      )
      and (
        cardinality(v_org_kinds)=0
        or exists(
          select 1 from unnest(v_org_kinds) q
          where lower(concat_ws(' ',
            e.name,coalesce(e.description,''),coalesce(e.metadata::text,''),
            coalesce(oip.legal_name,''),coalesce(oip.local_unit_name,''),
            coalesce(oip.metadata::text,'')
          )) like '%'||replace(q,'_',' ')||'%'
          or lower(concat_ws(' ',
            e.name,coalesce(e.description,''),coalesce(e.metadata::text,'')
          )) like '%'||q||'%'
        )
      )
      and (
        cardinality(v_places)=0
        or exists(
          select 1 from unnest(v_places) q
          where lower(coalesce(e.city,''))=q
             or lower(coalesce(e.city,'')) like '%'||q||'%'
             or lower(coalesce(e.address_line1,'')) like '%'||q||'%'
        )
      )
  ),
  people as (
    select distinct on (p.id,o.id)
      p.id as subject_entity_id,
      p.name as subject_name,
      p.entity_type as subject_type,
      p.website_url as subject_website_url,
      p.email as subject_email,
      p.phone as subject_phone,
      p.verification_state as subject_verification_state,
      p.last_verified_at as subject_last_verified_at,
      o.id as organization_entity_id,
      o.name as organization_name,
      o.website_url as organization_website_url,
      o.city as organization_city,
      o.state as organization_state,
      r.role_title,
      r.role_function,
      o.target_score
    from organization_candidates o
    join local_intel.entity_relationships r
      on r.object_entity_id=o.id
     and r.relationship_kind in ('holds_role_at','works_for','primary_contact_for','owns','founded')
     and r.is_current
     and r.truth_state in ('observed','accepted_current')
     and r.conflict_state='none'
    join local_intel.entities p
      on p.id=r.subject_entity_id
     and p.entity_type='person'
     and p.status='active'
    where v_person_requested
      and (
        cardinality(v_person_functions)=0
        or 'decision_adjacent'=any(v_person_functions)
        or exists(
          select 1 from unnest(v_person_functions) q
          where lower(coalesce(r.role_function,'')) like '%'||replace(q,'_',' ')||'%'
             or lower(coalesce(r.role_function,'')) like '%'||q||'%'
             or lower(coalesce(r.role_title,'')) like '%'||replace(q,'_',' ')||'%'
             or lower(coalesce(r.role_title,'')) like '%'||q||'%'
        )
      )
      and (
        cardinality(v_titles)=0
        or exists(
          select 1 from unnest(v_titles) q
          where lower(coalesce(r.role_title,'')) like '%'||replace(q,'_',' ')||'%'
             or lower(coalesce(r.role_title,'')) like '%'||q||'%'
        )
      )
    order by p.id,o.id,r.current_confidence desc nulls last,r.last_seen_current_at desc nulls last,r.updated_at desc
  ),
  raw_candidates as (
    select
      p.subject_entity_id,p.subject_name,p.subject_type,p.subject_website_url,p.subject_email,p.subject_phone,
      p.subject_verification_state,p.subject_last_verified_at,
      p.organization_entity_id,p.organization_name,p.organization_website_url,p.organization_city,p.organization_state,
      p.role_title,p.role_function,p.target_score
    from people p
    union all
    select
      o.id,o.name,o.entity_type,o.website_url,o.email,o.phone,o.verification_state,o.last_verified_at,
      null::uuid,null::text,null::text,o.city,o.state,
      null::text,null::text,o.target_score
    from organization_candidates o
    where not v_person_requested
  ),
  bounded as (
    select *
    from raw_candidates
    order by target_score desc,organization_name nulls last,subject_name,subject_entity_id
    limit v_limit
  ),
  detailed as (
    select
      c.*,
      coalesce((
        select array_agg(f order by f)
        from unnest(v_required) f
        where case f
          when 'email' then
            nullif(btrim(coalesce(c.subject_email,'')),'') is null
            and not exists(
              select 1 from local_intel.v_best_entity_contact_route_v1 cr
              where cr.entity_id=c.subject_entity_id
                and cr.contact_type='email'
                and coalesce(cr.effective_contactability,'')<>'blocked'
            )
          when 'phone' then
            nullif(btrim(coalesce(c.subject_phone,'')),'') is null
            and not exists(
              select 1 from local_intel.v_best_entity_contact_route_v1 cr
              where cr.entity_id=c.subject_entity_id
                and cr.contact_type='phone'
                and coalesce(cr.effective_contactability,'')<>'blocked'
            )
          when 'name' then nullif(btrim(coalesce(c.subject_name,'')),'') is null
          when 'title' then nullif(btrim(coalesce(c.role_title,'')),'') is null
          when 'organization' then c.organization_entity_id is null and v_person_requested
          when 'website' then
            nullif(btrim(coalesce(c.subject_website_url,c.organization_website_url,'')),'') is null
          else true
        end
      ),'{}'::text[]) as missing_fields,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'contactType',cr.contact_type,
          'contactValue',cr.contact_value,
          'routeEntityId',cr.route_entity_id,
          'routeEntityName',cr.route_entity_name,
          'routeKind',cr.route_kind,
          'contactScope',cr.contact_scope,
          'verificationState',cr.verification_state,
          'deliverabilityState',cr.deliverability_state,
          'contactability',cr.effective_contactability,
          'lastCheckedAt',cr.last_checked_at
        ) order by cr.contact_type,cr.hierarchy_hops,cr.route_entity_name)
        from local_intel.v_best_entity_contact_route_v1 cr
        where cr.entity_id=c.subject_entity_id
      ),'[]'::jsonb) as contact_routes
    from bounded c
  ),
  item_payloads as (
    select
      d.subject_entity_id,
      d.organization_entity_id,
      d.missing_fields,
      jsonb_build_object(
        'entityId',d.subject_entity_id,
        'name',d.subject_name,
        'entityType',d.subject_type,
        'organizationEntityId',d.organization_entity_id,
        'organizationName',d.organization_name,
        'roleTitle',d.role_title,
        'roleFunction',d.role_function,
        'geography',jsonb_strip_nulls(jsonb_build_object(
          'city',d.organization_city,
          'state',d.organization_state
        )),
        'websiteUrl',coalesce(d.subject_website_url,d.organization_website_url),
        'verificationState',d.subject_verification_state,
        'lastVerifiedAt',d.subject_last_verified_at,
        'bestContactRoutes',d.contact_routes,
        'requiredFields',to_jsonb(v_required),
        'missingFields',to_jsonb(d.missing_fields),
        'fieldCoverageState',case when cardinality(d.missing_fields)=0 then 'complete' else 'gap' end,
        'overlay',atlas.shared_directory_entity_overlay_service_v1(p_organization_id,d.subject_entity_id)
      ) as payload
    from detailed d
  ),
  organization_person_gaps as (
    select jsonb_build_object(
      'gapKind','organization_person_gap',
      'organizationEntityId',o.id,
      'organizationName',o.name,
      'geography',jsonb_strip_nulls(jsonb_build_object('city',o.city,'state',o.state)),
      'missingFields',to_jsonb(array_prepend('person',v_required)),
      'reason','Qualifying canonical organization exists but no qualifying current person is known.'
    ) as payload
    from organization_candidates o
    where v_person_requested
      and not exists(select 1 from people p where p.organization_entity_id=o.id)
  ),
  entity_field_gaps as (
    select jsonb_build_object(
      'gapKind','entity_field_gap',
      'entityId',i.subject_entity_id,
      'organizationEntityId',i.organization_entity_id,
      'missingFields',to_jsonb(i.missing_fields),
      'reason','Canonical subject exists but one or more required fields are missing.'
    ) as payload
    from item_payloads i
    where cardinality(i.missing_fields)>0
  ),
  all_gaps as (
    select payload from entity_field_gaps
    union all
    select payload from organization_person_gaps
  )
  select
    coalesce((select jsonb_agg(i.payload order by i.payload->>'organizationName',i.payload->>'name') from item_payloads i),'[]'::jsonb),
    coalesce((select jsonb_agg(g.payload) from all_gaps g),'[]'::jsonb),
    (select count(*)::integer from item_payloads),
    (select count(*)::integer from item_payloads where cardinality(missing_fields)=0)
  into v_items,v_research,v_candidate_count,v_ready_count;

  return jsonb_build_object(
    'contractVersion','shared_directory_target_search_v1',
    'organizationId',p_organization_id,
    'target',p_target,
    'geography',p_geography,
    'requiredFields',to_jsonb(v_required),
    'personTarget',v_person_requested,
    'candidateCount',v_candidate_count,
    'completeCandidateCount',v_ready_count,
    'items',v_items,
    'researchTargets',v_research,
    'retrievalPolicy','typed_shared_directory_first'
  );
end;
$function$;

revoke all on function atlas.shared_directory_target_search_service_v1(uuid,jsonb,jsonb,text[],integer)
  from public,anon,authenticated;
grant execute on function atlas.shared_directory_target_search_service_v1(uuid,jsonb,jsonb,text[],integer)
  to service_role;

create or replace function atlas.prepare_contact_set_execution_service_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  r atlas.contact_set_intent_requests%rowtype;
  v_existing atlas.contact_set_execution_runs%rowtype;
  v_required text[];
  v_desired integer;
  v_limit integer;
  v_directory jsonb;
  v_gaps jsonb;
  v_selected integer;
  v_population_gap boolean;
  v_state text;
  v_attach boolean;
  v_role_key text;
  v_ledger_results jsonb:='[]'::jsonb;
  v_item jsonb;
  v_attach_result jsonb;
  v_run atlas.contact_set_execution_runs%rowtype;
begin
  select * into r
  from atlas.contact_set_intent_requests x
  where x.id=p_request_id;

  if r.id is null then
    raise exception 'Contact-set intent request not found.' using errcode='P0002';
  end if;
  if r.request_state<>'ready' or r.interpretation is null then
    raise exception 'Contact-set request must be ready before execution preparation.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.contact_set_execution_runs e
  where e.request_id=r.id;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,
      'changed',false,
      'contractVersion','contact_set_execution_preparation_v1',
      'runId',v_existing.id,
      'requestId',v_existing.request_id,
      'executionState',v_existing.execution_state,
      'directory',v_existing.directory_snapshot,
      'gaps',v_existing.gap_snapshot,
      'ledgerEffects',v_existing.ledger_effect_snapshot
    );
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
    into v_required
  from jsonb_array_elements_text(coalesce(r.interpretation#>'{fields,required}','[]'::jsonb)) x;

  if cardinality(v_required)=0 then
    raise exception 'Ready contact-set request has no required fields.' using errcode='23514';
  end if;

  begin
    v_desired:=nullif(r.interpretation#>>'{population,desiredCount}','')::integer;
  exception when invalid_text_representation then
    raise exception 'Contact-set desired count is invalid.' using errcode='23514';
  end;

  v_limit:=least(200,greatest(50,coalesce(v_desired,20)*5));

  v_directory:=atlas.shared_directory_target_search_service_v1(
    r.organization_id,
    r.interpretation->'target',
    r.interpretation->'geography',
    v_required,
    v_limit
  );

  v_selected:=coalesce((v_directory->>'candidateCount')::integer,0);
  v_population_gap:=v_desired is not null and v_selected<v_desired;
  v_gaps:=coalesce(v_directory->'researchTargets','[]'::jsonb);

  if v_population_gap then
    v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object(
      'gapKind','population_gap',
      'desiredCount',v_desired,
      'supportedCount',v_selected,
      'missingCount',v_desired-v_selected,
      'reason','The existing canonical directory does not yet support the requested population size.'
    ));
  end if;

  v_attach:=lower(coalesce(r.interpretation#>>'{ledgerEffect,attachToLedger}','false')) in ('true','1','yes');
  v_role_key:=coalesce(nullif(lower(btrim(r.interpretation#>>'{ledgerEffect,roleKey}')),''),'contact');
  if v_role_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Interpreted Ledger role key is invalid.' using errcode='23514';
  end if;

  if v_attach then
    for v_item in select value from jsonb_array_elements(coalesce(v_directory->'items','[]'::jsonb))
    loop
      v_attach_result:=atlas.attach_shared_directory_entity_service_v1(
        r.organization_id,
        (v_item->>'entityId')::uuid,
        v_role_key,
        r.organization_unit_id
      );
      v_ledger_results:=v_ledger_results||jsonb_build_array(
        jsonb_build_object(
          'entityId',v_item->>'entityId',
          'roleKey',v_role_key,
          'result',v_attach_result
        )
      );
    end loop;
  end if;

  v_state:=case when jsonb_array_length(v_gaps)>0 then 'needs_acquisition' else 'ready' end;

  insert into atlas.contact_set_execution_runs(
    request_id,organization_id,organization_unit_id,execution_state,
    required_fields,desired_count,selected_count,
    directory_snapshot,gap_snapshot,ledger_effect_snapshot
  ) values (
    r.id,r.organization_id,r.organization_unit_id,v_state,
    v_required,v_desired,v_selected,
    v_directory,
    jsonb_build_object(
      'contractVersion','contact_set_gap_snapshot_v1',
      'researchTargets',v_gaps,
      'gapCount',jsonb_array_length(v_gaps),
      'populationGap',v_population_gap
    ),
    jsonb_build_object(
      'attachToLedger',v_attach,
      'roleKey',case when v_attach then v_role_key else null end,
      'results',v_ledger_results,
      'communicationAuthorized',false
    )
  )
  returning * into v_run;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','contact_set_execution_preparation_v1',
    'runId',v_run.id,
    'requestId',v_run.request_id,
    'executionState',v_run.execution_state,
    'directory',v_run.directory_snapshot,
    'gaps',v_run.gap_snapshot,
    'ledgerEffects',v_run.ledger_effect_snapshot,
    'truthBoundary',jsonb_build_object(
      'sharedIntelligenceMutation',false,
      'externalResearchExecuted',false,
      'communicationAuthorized',false,
      'privateLedgerAttachmentOnly',v_attach
    )
  );
end;
$function$;

revoke all on function atlas.prepare_contact_set_execution_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.prepare_contact_set_execution_service_v1(uuid)
  to service_role;

create or replace function atlas.contact_set_execution_run_self_api_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  r atlas.contact_set_execution_runs%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into r
  from atlas.contact_set_execution_runs x
  where x.request_id=p_request_id;

  if r.id is null then
    raise exception 'Contact-set execution run not found.' using errcode='P0002';
  end if;
  if atlas.current_effective_organization_membership_v1(r.organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','contact_set_execution_run_v1',
    'runId',r.id,
    'requestId',r.request_id,
    'organizationId',r.organization_id,
    'organizationUnitId',r.organization_unit_id,
    'executionState',r.execution_state,
    'requiredFields',to_jsonb(r.required_fields),
    'desiredCount',r.desired_count,
    'selectedCount',r.selected_count,
    'directory',r.directory_snapshot,
    'gaps',r.gap_snapshot,
    'ledgerEffects',r.ledger_effect_snapshot,
    'preparedAt',r.prepared_at,
    'updatedAt',r.updated_at
  );
end;
$function$;

revoke all on function atlas.contact_set_execution_run_self_api_v1(uuid) from public,anon;
grant execute on function atlas.contact_set_execution_run_self_api_v1(uuid) to authenticated;

comment on function atlas.shared_directory_target_search_service_v1(uuid,jsonb,jsonb,text[],integer) is
'Typed Shared Directory retrieval for build_target_contact_set. Searches canonical organizations/people and public role graph before acquisition, then composes only the requesting Organization overlay and reports exact required-field/person gaps.';
comment on function atlas.prepare_contact_set_execution_service_v1(uuid) is
'Creates one durable existing-reality contact-set execution snapshot. May attach canonical entities to the requesting Ledger when explicitly interpreted, but performs no Shared Intelligence mutation, external research or communication.';

commit;
