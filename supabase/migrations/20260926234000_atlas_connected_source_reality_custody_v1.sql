-- Canonical Reality custody for connected sources.
--
-- The legacy connected_sources custodian_user_id / custodian_organization_id
-- columns are retained as access/routing carriers. They must not be treated as
-- canonical ownership once Reality custody is present.

alter table atlas.connected_sources
  add column custodian_entity_id uuid references reality.entities(id) on delete restrict,
  add column custody_state text not null default 'legacy_unresolved'
    check (custody_state in ('canonical','claimed_unresolved','legacy_unresolved')),
  add column custody_claim_label text;

alter table atlas.connected_sources
  add constraint connected_sources_canonical_custody_check
  check (custody_state<>'canonical' or custodian_entity_id is not null),
  add constraint connected_sources_claimed_custody_check
  check (
    custody_state<>'claimed_unresolved'
    or (custodian_entity_id is null and custody_claim_label is not null and btrim(custody_claim_label)<>'')
  ),
  add constraint connected_sources_custody_claim_label_check
  check (custody_claim_label is null or btrim(custody_claim_label)<>'');

create index connected_sources_custodian_entity_idx
  on atlas.connected_sources(custodian_entity_id)
  where custodian_entity_id is not null;

-- Backfill Auth-user carriers to their canonical Reality Person where one active
-- direct binding exists.
update atlas.connected_sources source
set custodian_entity_id=(
      select b.person_entity_id
      from reality.auth_person_bindings b
      join reality.entities e on e.id=b.person_entity_id
      where b.auth_user_id=source.custodian_user_id
        and b.binding_state='active'
        and b.retired_at is null
        and e.entity_kind='person'
        and e.identity_state='canonical'
      order by b.bound_at desc,b.id
      limit 1
    ),
    custody_state=case when exists(
      select 1
      from reality.auth_person_bindings b
      join reality.entities e on e.id=b.person_entity_id
      where b.auth_user_id=source.custodian_user_id
        and b.binding_state='active'
        and b.retired_at is null
        and e.entity_kind='person'
        and e.identity_state='canonical'
    ) then 'canonical' else 'legacy_unresolved' end
where source.custodian_user_id is not null;

-- Backfill legacy Organization carriers through the explicit compatibility map.
update atlas.connected_sources source
set custodian_entity_id=(
      select binding.new_id
      from compatibility.legacy_bindings binding
      join reality.entities e on e.id=binding.new_id
      where binding.legacy_schema='atlas'
        and binding.legacy_table='organizations'
        and binding.legacy_key=source.custodian_organization_id::text
        and binding.disposition='maps_to'
        and binding.new_schema='reality'
        and binding.new_table='entities'
        and e.identity_state='canonical'
      order by binding.created_at,binding.id
      limit 1
    ),
    custody_state=case when exists(
      select 1
      from compatibility.legacy_bindings binding
      join reality.entities e on e.id=binding.new_id
      where binding.legacy_schema='atlas'
        and binding.legacy_table='organizations'
        and binding.legacy_key=source.custodian_organization_id::text
        and binding.disposition='maps_to'
        and binding.new_schema='reality'
        and binding.new_table='entities'
        and e.identity_state='canonical'
    ) then 'canonical' else 'legacy_unresolved' end
where source.custodian_organization_id is not null;

create or replace function atlas.financial_sources_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  return jsonb_build_object(
    'contractVersion','financial_sources_self_v1',
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'sourceId',visible.source_id,
        'accessCarrierKind',visible.custody_kind,
        'legacyCustodianOrganizationId',visible.custodian_organization_id,
        'providerKey',visible.provider_key,
        'providerAccountKey',visible.provider_account_key,
        'displayLabel',visible.display_label,
        'accountHint',visible.account_hint,
        'authorizationState',visible.authorization_state,
        'grantedScopes',visible.granted_scopes,
        'capabilities',visible.capabilities,
        'lastSyncAt',visible.last_sync_at,
        'custodyState',source.custody_state,
        'claimedOwnerLabel',source.custody_claim_label,
        'custodianEntity',case when entity.id is null then null else jsonb_build_object(
          'id',entity.id,
          'stableKey',entity.stable_key,
          'kind',entity.entity_kind,
          'displayName',entity.display_name,
          'identityState',entity.identity_state
        ) end,
        'createdAt',visible.created_at,
        'updatedAt',visible.updated_at
      ) order by visible.created_at,visible.source_id)
      from atlas.connected_sources_self_api_v1() visible
      join atlas.connected_sources source on source.id=visible.source_id
      left join reality.entities entity on entity.id=source.custodian_entity_id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'accessCarrierIsNotCustody',true,
      'canonicalCustodyUsesRealityEntity',true,
      'claimedUnresolvedCustodyMayAdmitEvidenceWithoutInventingOwnerIdentity',true
    )
  );
end;
$function$;

create or replace function atlas.register_person_connected_source_self_api_v1(
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_authorization_state text default 'connected',
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_person uuid:=atlas.current_person_id_v1();
  v_provider_key text:=btrim(coalesce(p_provider_key,''));
  v_provider_account_key text:=btrim(coalesce(p_provider_account_key,''));
  v_state text:=btrim(coalesce(p_authorization_state,''));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
begin
  if v_uid is null or v_person is null then raise exception 'Signed-in Reality Person required.' using errcode='42501'; end if;
  if v_provider_key='' or v_provider_account_key='' then raise exception 'Provider identity is required.' using errcode='22023'; end if;
  if v_state not in ('pending','connected') then raise exception 'A source may only be registered as pending or connected.' using errcode='22023'; end if;
  if jsonb_typeof(v_metadata)<>'object' then raise exception 'Source metadata must be an object.' using errcode='22023'; end if;
  if p_capabilities is not null and jsonb_typeof(p_capabilities)<>'object' then raise exception 'Source capabilities must be an object.' using errcode='22023'; end if;
  if lower(v_metadata::text) ~ '\"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)\"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023';
  end if;

  select source.* into v_source
  from atlas.connected_sources source
  where source.custodian_user_id=v_uid
    and source.provider_key=v_provider_key
    and source.provider_account_key=v_provider_account_key
  for update;

  if found then
    if v_source.authorization_state='revoked' then raise exception 'A revoked provider source cannot be silently rebound.' using errcode='55000'; end if;
    if v_source.custody_state='canonical' and v_source.custodian_entity_id is distinct from v_person then
      raise exception 'This provider source is already bound to a different canonical custodian.' using errcode='23514';
    end if;
    update atlas.connected_sources source
    set display_label=coalesce(nullif(btrim(p_display_label),''),source.display_label),
        account_hint=coalesce(nullif(btrim(p_account_hint),''),source.account_hint),
        authorization_state=v_state,
        granted_scopes=coalesce(p_granted_scopes,source.granted_scopes),
        capabilities=coalesce(p_capabilities,source.capabilities),
        custodian_entity_id=v_person,
        custody_state='canonical',
        custody_claim_label=null,
        revoked_at=null,
        metadata=source.metadata||v_metadata,
        updated_at=now()
    where source.id=v_source.id
    returning source.* into v_source;
  else
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,custodian_entity_id,custody_state,
      provider_key,provider_account_key,display_label,account_hint,authorization_state,
      granted_scopes,capabilities,metadata
    ) values(
      v_uid,null,v_person,'canonical',
      v_provider_key,v_provider_account_key,
      nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),v_state,
      coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),v_metadata
    ) returning * into v_source;
  end if;

  return jsonb_build_object(
    'sourceId',v_source.id,
    'accessCarrierKind','human',
    'custodyState',v_source.custody_state,
    'custodianEntityId',v_source.custodian_entity_id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'capabilities',v_source.capabilities,
    'truthBoundary',jsonb_build_object(
      'accessCarrierIsNotCustody',true,
      'custodyIsCanonicalRealityPerson',true,
      'sourceCustodyDoesNotEstablishOperationalPurpose',true,
      'sourceCustodyDoesNotEstablishTaxTreatment',true
    )
  );
end;
$function$;

create or replace function atlas.register_claimed_financial_source_self_api_v1(
  p_provider_key text,
  p_provider_account_key text,
  p_claimed_owner_label text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_person uuid:=atlas.current_person_id_v1();
  v_provider_key text:=btrim(coalesce(p_provider_key,''));
  v_provider_account_key text:=btrim(coalesce(p_provider_account_key,''));
  v_owner text:=btrim(coalesce(p_claimed_owner_label,''));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
begin
  if v_uid is null or v_person is null then raise exception 'Signed-in Reality Person required.' using errcode='42501'; end if;
  if v_provider_key='' or v_provider_account_key='' or v_owner='' then raise exception 'Provider identity and claimed source owner are required.' using errcode='22023'; end if;
  if jsonb_typeof(v_metadata)<>'object' then raise exception 'Source metadata must be an object.' using errcode='22023'; end if;
  if p_capabilities is not null and jsonb_typeof(p_capabilities)<>'object' then raise exception 'Source capabilities must be an object.' using errcode='22023'; end if;
  if lower(v_metadata::text) ~ '\"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)\"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023';
  end if;

  select source.* into v_source
  from atlas.connected_sources source
  where source.custodian_user_id=v_uid
    and source.provider_key=v_provider_key
    and source.provider_account_key=v_provider_account_key
  for update;

  if found then
    if v_source.authorization_state='revoked' then raise exception 'A revoked provider source cannot be silently rebound.' using errcode='55000'; end if;
    if v_source.custody_state='canonical' then raise exception 'A canonical source custodian cannot be replaced by an unresolved owner claim.' using errcode='23514'; end if;
    update atlas.connected_sources source
    set display_label=coalesce(nullif(btrim(p_display_label),''),source.display_label),
        account_hint=coalesce(nullif(btrim(p_account_hint),''),source.account_hint),
        authorization_state='connected',
        granted_scopes=coalesce(p_granted_scopes,source.granted_scopes),
        capabilities=coalesce(p_capabilities,source.capabilities),
        custodian_entity_id=null,
        custody_state='claimed_unresolved',
        custody_claim_label=v_owner,
        revoked_at=null,
        metadata=source.metadata||v_metadata,
        updated_at=now()
    where source.id=v_source.id
    returning source.* into v_source;
  else
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,custodian_entity_id,custody_state,custody_claim_label,
      provider_key,provider_account_key,display_label,account_hint,authorization_state,
      granted_scopes,capabilities,metadata
    ) values(
      v_uid,null,null,'claimed_unresolved',v_owner,
      v_provider_key,v_provider_account_key,
      nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),'connected',
      coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),v_metadata
    ) returning * into v_source;
  end if;

  return jsonb_build_object(
    'sourceId',v_source.id,
    'accessCarrierKind','human',
    'custodyState','claimed_unresolved',
    'claimedOwnerLabel',v_owner,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'truthBoundary',jsonb_build_object(
      'accessCarrierIsNotClaimedOwner',true,
      'custodianEntityNotYetEstablished',true,
      'sourceEvidenceMayBeAdmittedWithoutInventingOwnerIdentity',true,
      'operationalPurposeNotInferred',true,
      'taxTreatmentNotInferred',true
    )
  );
end;
$function$;

create or replace function atlas.bind_connected_source_custodian_entity_self_api_v1(
  p_connected_source_id uuid,
  p_custodian_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person uuid:=atlas.current_person_id_v1();
  v_source atlas.connected_sources%rowtype;
  v_entity reality.entities%rowtype;
  v_responsibility uuid;
begin
  if auth.uid() is null or v_person is null then raise exception 'Signed-in Reality Person required.' using errcode='42501'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Custody binding metadata must be an object.' using errcode='22023'; end if;
  if not atlas.financial_source_authorized_self_v1(p_connected_source_id) then raise exception 'Financial source access required.' using errcode='42501'; end if;

  select * into v_source from atlas.connected_sources where id=p_connected_source_id for update;
  select * into v_entity from reality.entities where id=p_custodian_entity_id and identity_state='canonical';
  if v_entity.id is null then raise exception 'Canonical Reality custodian required.' using errcode='P0002'; end if;

  if v_entity.id<>v_person then
    v_responsibility:=reality.resolve_responsibility_relation_v1(
      v_person,
      'financial_source_custody',
      'financial_source.custody_bind',
      'entity',
      v_entity.id,
      null,
      '{}'::jsonb
    );
    if v_responsibility is null then raise exception 'Explicit financial-source custody responsibility is required for that entity.' using errcode='42501'; end if;
  end if;

  update atlas.connected_sources source
  set custodian_entity_id=v_entity.id,
      custody_state='canonical',
      custody_claim_label=coalesce(source.custody_claim_label,v_entity.display_name),
      metadata=source.metadata||jsonb_build_object('custodyBoundByPersonEntityId',v_person)||p_metadata,
      updated_at=now()
  where source.id=v_source.id
  returning source.* into v_source;

  return jsonb_build_object(
    'sourceId',v_source.id,
    'custodyState','canonical',
    'custodianEntity',jsonb_build_object('id',v_entity.id,'kind',v_entity.entity_kind,'displayName',v_entity.display_name),
    'truthBoundary',jsonb_build_object(
      'sourceObservationsPreserved',true,
      'accessCarrierUnchanged',true,
      'custodyBindingDoesNotClassifyTransactions',true
    )
  );
end;
$function$;

revoke all on function atlas.financial_sources_self_api_v1() from public,anon,service_role;
revoke all on function atlas.register_claimed_financial_source_self_api_v1(text,text,text,text,text,text[],jsonb,jsonb) from public,anon,service_role;
revoke all on function atlas.bind_connected_source_custodian_entity_self_api_v1(uuid,uuid,jsonb) from public,anon,service_role;

grant execute on function atlas.financial_sources_self_api_v1() to authenticated;
grant execute on function atlas.register_claimed_financial_source_self_api_v1(text,text,text,text,text,text[],jsonb,jsonb) to authenticated;
grant execute on function atlas.bind_connected_source_custodian_entity_self_api_v1(uuid,uuid,jsonb) to authenticated;

comment on column atlas.connected_sources.custodian_entity_id is
  'Canonical Reality entity that owns/custodies the external source when established. Legacy user/organization columns remain access/routing carriers.';
comment on column atlas.connected_sources.custody_state is
  'Whether source custody is canonical, explicitly claimed but unresolved, or only represented by the legacy carrier.';
comment on function atlas.register_claimed_financial_source_self_api_v1(text,text,text,text,text,text[],jsonb,jsonb) is
  'Admits a financial source under the signed-in Person access carrier while preserving a named but unresolved source-owner claim. It does not assert that the Person owns the source.';
comment on function atlas.bind_connected_source_custodian_entity_self_api_v1(uuid,uuid,jsonb) is
  'Binds an existing connected source to canonical Reality custody. Non-self entity custody requires an explicit financial_source_custody responsibility relation.';