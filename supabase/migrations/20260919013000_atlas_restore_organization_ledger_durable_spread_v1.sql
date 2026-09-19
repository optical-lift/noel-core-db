begin;

-- Restore Organization Ledger as a durable universal-notebook spread without
-- recreating the old synthesized Index page. The durable spread may survive
-- authority changes, but retrieval is admitted only while the same Principal
-- still satisfies the canonical owner-only Ledger read membrane.

create or replace function atlas.principal_has_organization_owner_access_v1(
  p_principal_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog,atlas
as $function$
  select exists (
    select 1
    from atlas.principals p
    join atlas.organization_memberships om
      on om.person_id = p.person_id
    where p.id = p_principal_id
      and p.status = 'active'
      and p.person_id is not null
      and om.organization_id = p_organization_id
      and om.active = true
      and om.role = 'owner'
  );
$function$;

revoke all on function atlas.principal_has_organization_owner_access_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.principal_has_organization_owner_access_v1(uuid,uuid)
  to service_role;

create or replace function atlas.sync_organization_owner_ledger_spread_v1(
  p_principal_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_org atlas.organizations%rowtype;
  v_ledger_id uuid;
  v_spread_id uuid;
  v_existing atlas.notebook_spread_instances%rowtype;
  v_authorized boolean := false;
  v_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','log',
      'role','anchor',
      'order',1,
      'supportedRelationships',jsonb_build_array('evidence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Preserve Ledger occurrence order and exact entry identity.'
    )),
    'surfaceBudget',jsonb_build_object(
      'anchorCount',1,
      'supportingCount',0,
      'marginCount',0,
      'latentIsDefault',true
    ),
    'phoneLinearization',jsonb_build_array('log'),
    'stability',jsonb_build_object(
      'meaningPositionsAreStable',true,
      'recomposeOnlyForMeaningfulPhaseChange',true,
      'historyPreservedByRevision',true
    ),
    'sourceBindingPolicy',jsonb_build_object(
      'sourceTruthExternal',true,
      'missingSourceDoesNotCreateEmptyIntegrationTile',true,
      'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
    ),
    'compilerBasis',jsonb_build_object(
      'migration','organization-ledger-durable-spread-v1',
      'page','organization-ledger'
    )
  );
begin
  if p_principal_id is null or p_organization_id is null then
    raise exception 'Principal and Organization are required.' using errcode='22023';
  end if;

  select *
    into v_org
  from atlas.organizations o
  where o.id=p_organization_id;

  if v_org.id is null then
    raise exception 'Organization not found.' using errcode='P0002';
  end if;

  select *
    into v_existing
  from atlas.notebook_spread_instances s
  where s.principal_id=p_principal_id
    and s.spread_key='ledger:'||p_organization_id::text
  limit 1;

  v_authorized := atlas.principal_has_organization_owner_access_v1(
    p_principal_id,
    p_organization_id
  );

  if not v_authorized then
    if v_existing.id is not null then
      if v_existing.scope_kind <> 'organization'
         or v_existing.scope_id <> p_organization_id::text
         or v_existing.subject_domain <> 'organization'
         or v_existing.subject_kind <> 'organization_ledger'
         or v_existing.subject_id <> p_organization_id::text then
        raise exception 'Ledger spread key already belongs to a different durable identity.'
          using errcode='23505';
      end if;

      update atlas.notebook_spread_instances
      set spread_state='closed',
          closed_at=coalesce(closed_at,now()),
          updated_at=now()
      where id=v_existing.id;

      update atlas.notebook_spread_source_bindings
      set binding_state='retired',
          retired_at=coalesce(retired_at,now()),
          updated_at=now()
      where spread_instance_id=v_existing.id
        and source_domain='organization'
        and source_kind='ledger_recent_v1'
        and source_id=p_organization_id::text;
    end if;

    return jsonb_build_object(
      'ok',true,
      'authorized',false,
      'principalId',p_principal_id,
      'organizationId',p_organization_id,
      'spreadId',v_existing.id
    );
  end if;

  v_ledger_id := atlas.primary_ledger_for_organization_v1(p_organization_id);
  if v_ledger_id is null then
    raise exception 'Organization governing Ledger is unavailable.' using errcode='23514';
  end if;

  v_spread_id := atlas.set_notebook_spread_instance_v2(
    p_principal_id,
    'ledger:'||p_organization_id::text,
    'organization',
    p_organization_id::text,
    'organization',
    'organization_ledger',
    p_organization_id::text,
    'ledger-orientation',
    'rolling-30-days',
    'thread:organization-ledger:'||p_organization_id::text,
    v_org.name,
    'Organizations',
    null,
    'resolved',
    'open',
    v_contract,
    jsonb_build_object(
      'kind','organization_owner_authority',
      'organizationId',p_organization_id,
      'ledgerId',v_ledger_id,
      'readSeam','organization_ledger_owner_recent_api_v1'
    ),
    jsonb_build_object(
      'organizationId',p_organization_id,
      'ledgerId',v_ledger_id,
      'admission','owner-only'
    )
  );

  perform atlas.bind_notebook_spread_source_v1(
    v_spread_id,
    'organization',
    'ledger_recent_v1',
    p_organization_id::text,
    'evidence',
    'active',
    jsonb_build_object(
      'kind','governed_projection',
      'readSeam','organization_ledger_owner_recent_api_v1',
      'authority','organization_owner'
    ),
    jsonb_build_object('ledgerId',v_ledger_id)
  );

  return jsonb_build_object(
    'ok',true,
    'authorized',true,
    'principalId',p_principal_id,
    'organizationId',p_organization_id,
    'ledgerId',v_ledger_id,
    'spreadId',v_spread_id
  );
end;
$function$;

revoke all on function atlas.sync_organization_owner_ledger_spread_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.sync_organization_owner_ledger_spread_v1(uuid,uuid)
  to service_role;

create or replace function public.organization_ledger_owner_recent_api_v1(
  p_organization_id uuid,
  p_limit integer default 200
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_ledger_owner_recent_api_v1(
    p_organization_id,
    p_limit
  );
$function$;

revoke all on function public.organization_ledger_owner_recent_api_v1(uuid,integer)
  from public,anon;
grant execute on function public.organization_ledger_owner_recent_api_v1(uuid,integer)
  to authenticated,service_role;

comment on function public.organization_ledger_owner_recent_api_v1(uuid,integer) is
  'Authenticated browser membrane for the owner-only Organization Ledger recent projection. Authority remains in atlas.organization_ledger_owner_recent_api_v1.';

create or replace function atlas.sync_organization_owner_ledger_from_membership_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  r record;
begin
  if tg_op='UPDATE'
     and (
       old.organization_id is distinct from new.organization_id
       or old.person_id is distinct from new.person_id
       or old.role is distinct from new.role
       or old.active is distinct from new.active
     )
     and old.person_id is not null then
    for r in
      select p.id
      from atlas.principals p
      where p.person_id=old.person_id
    loop
      perform atlas.sync_organization_owner_ledger_spread_v1(
        r.id,
        old.organization_id
      );
    end loop;
  end if;

  if new.person_id is not null then
    for r in
      select p.id
      from atlas.principals p
      where p.person_id=new.person_id
    loop
      perform atlas.sync_organization_owner_ledger_spread_v1(
        r.id,
        new.organization_id
      );
    end loop;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_sync_organization_owner_ledger_spread_v1
  on atlas.organization_memberships;
create trigger trg_sync_organization_owner_ledger_spread_v1
after insert or update of organization_id,person_id,role,active
on atlas.organization_memberships
for each row execute function atlas.sync_organization_owner_ledger_from_membership_v1();

create or replace function atlas.sync_organization_owner_ledgers_from_principal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  r record;
begin
  if tg_op='UPDATE'
     and old.person_id is distinct from new.person_id
     and old.person_id is not null then
    for r in
      select distinct om.organization_id
      from atlas.organization_memberships om
      where om.person_id=old.person_id
    loop
      perform atlas.sync_organization_owner_ledger_spread_v1(
        new.id,
        r.organization_id
      );
    end loop;
  end if;

  if new.person_id is not null then
    for r in
      select distinct om.organization_id
      from atlas.organization_memberships om
      where om.person_id=new.person_id
    loop
      perform atlas.sync_organization_owner_ledger_spread_v1(
        new.id,
        r.organization_id
      );
    end loop;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_sync_organization_owner_ledgers_from_principal_v1
  on atlas.principals;
create trigger trg_sync_organization_owner_ledgers_from_principal_v1
after insert or update of status,person_id
on atlas.principals
for each row execute function atlas.sync_organization_owner_ledgers_from_principal_v1();

create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select p.id,p.active_household_id
    into v_principal_id,v_household_id
  from atlas.principals p
  where p.user_id=v_user_id
    and p.status='active'
  limit 1;

  with descriptors as (
    select 0 as section_order,0 as item_order,
      jsonb_build_object(
        'addressKind','today',
        'spreadKey','today',
        'templateKey','today',
        'title','Today',
        'section','Notebook',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','day','id',current_date::text)
      ) as item
    union all
    select 0,1,
      jsonb_build_object(
        'addressKind','index',
        'spreadKey','index',
        'templateKey','index',
        'title','Index',
        'section','Notebook',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','notebook','id',v_user_id)
      )
    union all
    select 10,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread',
        'spreadKey',s.spread_key,
        'templateKey','composed',
        'title',s.title,
        'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object(
          'domain',s.subject_domain,
          'kind',s.subject_kind,
          'id',s.subject_id
        ),
        'spreadInstanceId',s.id,
        'spreadState',s.spread_state,
        'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,
        'purposeKey',s.purpose_key,
        'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
      and (
        not (
          s.scope_kind='organization'
          and s.subject_domain='organization'
          and s.subject_kind='organization_ledger'
        )
        or exists (
          select 1
          from atlas.organizations o
          where o.id::text=s.scope_id
            and atlas.principal_has_organization_owner_access_v1(
              v_principal_id,
              o.id
            )
        )
      )
  )
  select coalesce(
    jsonb_agg(item order by section_order,item_order),
    '[]'::jsonb
  )
  into v_items
  from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,
      'indexDoesNotGrantAccess',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,
      'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,
      'closedSpreadsRemainRetrievable',true,
      'dataBearingPagesComeFromDurableSpreadRegistry',true,
      'organizationLedgerDescriptorRequiresCurrentOwnerAuthority',true
    )
  );
end;
$function$;

create or replace function atlas.notebook_spread_instance_self_api_v1(
  p_spread_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_spread atlas.notebook_spread_instances%rowtype;
  v_organization_id uuid;
  v_bindings jsonb := '[]'::jsonb;
  v_latest_revision jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if nullif(btrim(p_spread_key),'') is null then
    raise exception 'spread key is required.' using errcode='22023';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id
    and p.status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select * into v_spread
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key=btrim(p_spread_key)
  limit 1;

  if v_spread.id is null then
    raise exception 'Notebook spread not found.' using errcode='P0002';
  end if;

  if v_spread.scope_kind='organization'
     and v_spread.subject_domain='organization'
     and v_spread.subject_kind='organization_ledger' then
    select o.id
      into v_organization_id
    from atlas.organizations o
    where o.id::text=v_spread.scope_id
    limit 1;

    if v_organization_id is null
       or not atlas.principal_has_organization_owner_access_v1(
         v_principal_id,
         v_organization_id
       ) then
      raise exception 'Notebook spread not found.' using errcode='P0002';
    end if;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'bindingId',b.id,
      'sourceDomain',b.source_domain,
      'sourceKind',b.source_kind,
      'sourceId',b.source_id,
      'relationshipKind',b.relationship_kind,
      'bindingState',b.binding_state,
      'basis',b.basis,
      'metadata',b.metadata
    ) order by b.created_at,b.id
  ),'[]'::jsonb)
  into v_bindings
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_spread.id
    and b.binding_state='active'
    and b.retired_at is null;

  select jsonb_build_object(
    'revisionNo',r.revision_no,
    'compilerVersion',r.compiler_version,
    'reason',r.reason,
    'contractHash',r.contract_hash,
    'createdAt',r.created_at
  )
  into v_latest_revision
  from atlas.notebook_spread_composition_revisions r
  where r.spread_instance_id=v_spread.id
  order by r.revision_no desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_spread_instance_self_api_v1',
    'spread',jsonb_build_object(
      'spreadInstanceId',v_spread.id,
      'spreadKey',v_spread.spread_key,
      'title',v_spread.title,
      'sectionKey',v_spread.section_key,
      'scope',jsonb_build_object(
        'kind',v_spread.scope_kind,
        'id',v_spread.scope_id
      ),
      'subject',jsonb_build_object(
        'domain',v_spread.subject_domain,
        'kind',v_spread.subject_kind,
        'id',v_spread.subject_id
      ),
      'purposeKey',v_spread.purpose_key,
      'horizonKey',v_spread.horizon_key,
      'threadKey',v_spread.thread_key,
      'creationMode',v_spread.creation_mode,
      'spreadState',v_spread.spread_state,
      'compositionContract',v_spread.composition_contract,
      'openedAt',v_spread.opened_at,
      'closedAt',v_spread.closed_at
    ),
    'sourceBindings',v_bindings,
    'latestCompositionRevision',v_latest_revision,
    'truthBoundary',jsonb_build_object(
      'presentationReadOnly',true,
      'sourceBindingsAreDescriptorsNotCopiedFacts',true,
      'compositionContractOwnsPresentationOnly',true,
      'spreadReadDoesNotGrantSourceAuthority',true,
      'encounterSelectionIsSeparate',true,
      'organizationLedgerReadRequiresCurrentOwnerAuthority',true
    )
  );
end;
$function$;

-- Reconcile any historical Ledger spread carriers first, then seed every
-- current owner/Principal pairing.
do $backfill$
declare
  r record;
begin
  for r in
    select s.principal_id,o.id as organization_id
    from atlas.notebook_spread_instances s
    join atlas.organizations o
      on o.id::text=s.scope_id
    where s.scope_kind='organization'
      and s.subject_domain='organization'
      and s.subject_kind='organization_ledger'
  loop
    perform atlas.sync_organization_owner_ledger_spread_v1(
      r.principal_id,
      r.organization_id
    );
  end loop;

  for r in
    select distinct p.id as principal_id,om.organization_id
    from atlas.principals p
    join atlas.organization_memberships om
      on om.person_id=p.person_id
    where p.status='active'
      and p.person_id is not null
      and om.active=true
      and om.role='owner'
  loop
    perform atlas.sync_organization_owner_ledger_spread_v1(
      r.principal_id,
      r.organization_id
    );
  end loop;
end;
$backfill$;

commit;
