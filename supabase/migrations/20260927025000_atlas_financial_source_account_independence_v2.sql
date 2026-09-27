-- Atlas financial source account independence v2
--
-- A financial account is not the same thing as an externally authorized connector.
-- Historical statements, exports, and manual source records may establish evidence about
-- an account even when Atlas has no live provider authorization. Conversely, a future live
-- connector may attach to an already-known account without creating a second financial account.
--
-- Boundaries:
--   technical custody != financial account ownership
--   financial account ownership != operational beneficiary
--   source evidence != bookkeeping interpretation
--   connector authorization is optional evidence transport, never financial account identity

create table if not exists atlas.financial_source_accounts (
  id uuid primary key default gen_random_uuid(),
  custodian_user_id uuid not null references auth.users(id) on delete restrict,
  source_system_key text not null,
  source_account_key text not null,
  display_label text,
  account_hint text,
  account_kind text,
  default_currency text,
  registration_kind text not null,
  source_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_source_accounts_system_key_nonempty check (btrim(source_system_key)<>''),
  constraint financial_source_accounts_account_key_nonempty check (btrim(source_account_key)<>''),
  constraint financial_source_accounts_display_label_nonempty check (display_label is null or btrim(display_label)<>''),
  constraint financial_source_accounts_account_hint_nonempty check (account_hint is null or btrim(account_hint)<>''),
  constraint financial_source_accounts_account_kind_nonempty check (account_kind is null or btrim(account_kind)<>''),
  constraint financial_source_accounts_currency_check check (default_currency is null or default_currency ~ '^[A-Z]{3}$'),
  constraint financial_source_accounts_registration_kind_check check (
    registration_kind in ('document_reconstruction','imported_export','manual_record','authorized_connector')
  ),
  constraint financial_source_accounts_state_check check (source_state in ('active','retired')),
  constraint financial_source_accounts_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_accounts_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(custodian_user_id,source_system_key,source_account_key)
);

create index if not exists financial_source_accounts_custodian_idx
  on atlas.financial_source_accounts(custodian_user_id,source_state,source_system_key,id);

comment on table atlas.financial_source_accounts is
  'Canonical financial account/source identities independent of connector authorization. Technical custody controls access; Reality holder relations separately express financial ownership.';
comment on column atlas.financial_source_accounts.source_account_key is
  'Stable opaque account identity within a source system. Prefer provider IDs or a governed fingerprint; UI should use account_hint rather than expose sensitive account identifiers.';

create table if not exists atlas.financial_source_account_connector_links (
  id uuid primary key default gen_random_uuid(),
  financial_source_account_id uuid not null references atlas.financial_source_accounts(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  link_kind text not null default 'authorized_connector',
  link_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  linked_at timestamptz not null default now(),
  retired_at timestamptz,
  constraint financial_source_account_connector_link_kind_check check (link_kind in ('authorized_connector','authorized_export_source')),
  constraint financial_source_account_connector_link_state_check check (link_state in ('active','retired')),
  constraint financial_source_account_connector_link_retired_check check (
    (link_state='active' and retired_at is null) or (link_state='retired' and retired_at is not null)
  ),
  constraint financial_source_account_connector_link_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_account_connector_link_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(financial_source_account_id,connected_source_id)
);

create index if not exists financial_source_account_connector_links_source_idx
  on atlas.financial_source_account_connector_links(connected_source_id,link_state,financial_source_account_id);

comment on table atlas.financial_source_account_connector_links is
  'Optional transport links from a canonical financial source account to externally authorized connected_sources. A financial account may exist with zero connector links.';

create table if not exists atlas.financial_source_account_reality_holders (
  id uuid primary key default gen_random_uuid(),
  financial_source_account_id uuid not null references atlas.financial_source_accounts(id) on delete restrict,
  holder_entity_id uuid not null references reality.entities(id) on delete restrict,
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  established_at timestamptz not null default now(),
  constraint financial_source_account_reality_holders_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_account_reality_holders_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(financial_source_account_id,holder_entity_id)
);

create index if not exists financial_source_account_reality_holders_entity_idx
  on atlas.financial_source_account_reality_holders(holder_entity_id,financial_source_account_id);

comment on table atlas.financial_source_account_reality_holders is
  'Canonical Reality entities designated as holders of a financial source account. This is financial ownership evidence, not technical custody, operational beneficiary, or tax treatment.';

create table if not exists atlas.financial_source_evidence_observations (
  id uuid primary key default gen_random_uuid(),
  financial_source_account_id uuid not null references atlas.financial_source_accounts(id) on delete restrict,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  observation_kind text not null,
  source_kind text not null,
  source_object_key text not null,
  observation_sha256 text not null,
  connected_source_observation_id uuid references atlas.connected_source_observations(id) on delete restrict,
  observed_at timestamptz,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_source_evidence_observation_kind_check check (observation_kind in ('financial_statement','financial_transaction')),
  constraint financial_source_evidence_source_kind_nonempty check (btrim(source_kind)<>''),
  constraint financial_source_evidence_object_key_nonempty check (btrim(source_object_key)<>''),
  constraint financial_source_evidence_hash_check check (observation_sha256 ~ '^[0-9a-f]{64}$'),
  constraint financial_source_evidence_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_evidence_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(financial_source_account_id,observation_kind,source_object_key,observation_sha256),
  unique(evidence_record_id)
);

create index if not exists financial_source_evidence_observations_object_idx
  on atlas.financial_source_evidence_observations(
    financial_source_account_id,observation_kind,source_object_key,created_at,id
  );

comment on table atlas.financial_source_evidence_observations is
  'Versioned financial statement/transaction observations whose raw observed snapshot lives in atlas.evidence_records. Connector observations are optional provenance links.';

alter table atlas.financial_source_accounts enable row level security;
alter table atlas.financial_source_account_connector_links enable row level security;
alter table atlas.financial_source_account_reality_holders enable row level security;
alter table atlas.financial_source_evidence_observations enable row level security;

revoke all on table atlas.financial_source_accounts from public,anon,authenticated;
revoke all on table atlas.financial_source_account_connector_links from public,anon,authenticated;
revoke all on table atlas.financial_source_account_reality_holders from public,anon,authenticated;
revoke all on table atlas.financial_source_evidence_observations from public,anon,authenticated;

create or replace function atlas.financial_source_account_authorized_self_v2(
  p_financial_source_account_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
  select auth.uid() is not null and exists(
    select 1
    from atlas.financial_source_accounts account
    where account.id=p_financial_source_account_id
      and account.source_state='active'
      and account.custodian_user_id=auth.uid()
  );
$$;

revoke all on function atlas.financial_source_account_authorized_self_v2(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.financial_source_account_authorized_self_v2(uuid)
  to authenticated,service_role;

create or replace function atlas.register_financial_source_account_self_api_v2(
  p_source_system_key text,
  p_source_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_account_kind text default null,
  p_default_currency text default null,
  p_registration_kind text default 'manual_record',
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_system_key text:=lower(btrim(coalesce(p_source_system_key,'')));
  v_account_key text:=btrim(coalesce(p_source_account_key,''));
  v_currency text:=nullif(upper(btrim(coalesce(p_default_currency,''))), '');
  v_registration_kind text:=lower(btrim(coalesce(p_registration_kind,'')));
  v_account atlas.financial_source_accounts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  if v_system_key='' or v_account_key='' then
    raise exception 'Financial source system and stable account key are required.' using errcode='22023';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Default currency must be a three-letter code.' using errcode='22023';
  end if;
  if v_registration_kind not in ('document_reconstruction','imported_export','manual_record','authorized_connector') then
    raise exception 'Unsupported financial source account registration kind.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Financial source account provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  if lower((p_provenance||p_metadata)::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable credentials are not allowed in financial source account metadata or provenance.' using errcode='22023';
  end if;

  insert into atlas.financial_source_accounts(
    custodian_user_id,source_system_key,source_account_key,display_label,account_hint,
    account_kind,default_currency,registration_kind,provenance,metadata
  ) values (
    auth.uid(),v_system_key,v_account_key,
    nullif(btrim(coalesce(p_display_label,'')),''),
    nullif(btrim(coalesce(p_account_hint,'')),''),
    nullif(lower(btrim(coalesce(p_account_kind,''))),''),
    v_currency,v_registration_kind,
    p_provenance||jsonb_build_object(
      'authority','register_financial_source_account_self_api_v2',
      'technicalCustodyDoesNotEstablishAccountOwnership',true,
      'connectorAuthorizationRequired',false
    ),
    p_metadata
  ) on conflict(custodian_user_id,source_system_key,source_account_key)
  do update set
    display_label=coalesce(excluded.display_label,atlas.financial_source_accounts.display_label),
    account_hint=coalesce(excluded.account_hint,atlas.financial_source_accounts.account_hint),
    account_kind=coalesce(excluded.account_kind,atlas.financial_source_accounts.account_kind),
    default_currency=coalesce(excluded.default_currency,atlas.financial_source_accounts.default_currency),
    source_state='active',
    provenance=atlas.financial_source_accounts.provenance||excluded.provenance,
    metadata=atlas.financial_source_accounts.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_account;

  return jsonb_build_object(
    'contractVersion','financial_source_account_v2',
    'financialSourceAccountId',v_account.id,
    'sourceSystemKey',v_account.source_system_key,
    'displayLabel',v_account.display_label,
    'accountHint',v_account.account_hint,
    'accountKind',v_account.account_kind,
    'defaultCurrency',v_account.default_currency,
    'registrationKind',v_account.registration_kind,
    'sourceState',v_account.source_state,
    'truthBoundary',jsonb_build_object(
      'connectorAuthorizationRequired',false,
      'technicalCustodyDoesNotEstablishAccountOwnership',true,
      'accountOwnershipDoesNotEstablishOperationalBeneficiary',true
    )
  );
end;
$$;

revoke all on function atlas.register_financial_source_account_self_api_v2(
  text,text,text,text,text,text,text,jsonb,jsonb
) from public,anon;
grant execute on function atlas.register_financial_source_account_self_api_v2(
  text,text,text,text,text,text,text,jsonb,jsonb
) to authenticated;

create or replace function atlas.financial_source_accounts_self_api_v2()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
  select jsonb_build_object(
    'contractVersion','financial_source_accounts_v2',
    'accounts',coalesce(jsonb_agg(jsonb_build_object(
      'financialSourceAccountId',account.id,
      'sourceSystemKey',account.source_system_key,
      'displayLabel',account.display_label,
      'accountHint',account.account_hint,
      'accountKind',account.account_kind,
      'defaultCurrency',account.default_currency,
      'registrationKind',account.registration_kind,
      'sourceState',account.source_state
    ) order by account.display_label nulls last,account.source_system_key,account.id)
    filter(where account.id is not null),'[]'::jsonb)
  )
  from atlas.financial_source_accounts account
  where auth.uid() is not null
    and account.custodian_user_id=auth.uid()
    and account.source_state='active';
$$;

revoke all on function atlas.financial_source_accounts_self_api_v2() from public,anon;
grant execute on function atlas.financial_source_accounts_self_api_v2() to authenticated;

create or replace function atlas.link_financial_source_account_connector_self_api_v2(
  p_financial_source_account_id uuid,
  p_connected_source_id uuid,
  p_link_kind text default 'authorized_connector',
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_link atlas.financial_source_account_connector_links%rowtype;
  v_kind text:=lower(btrim(coalesce(p_link_kind,'')));
begin
  if not atlas.financial_source_account_authorized_self_v2(p_financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(p_connected_source_id) then
    raise exception 'Connected-source authority required.' using errcode='42501';
  end if;
  if v_kind not in ('authorized_connector','authorized_export_source') then
    raise exception 'Unsupported financial source connector link kind.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Connector-link provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.financial_source_account_connector_links(
    financial_source_account_id,connected_source_id,link_kind,link_state,provenance,metadata
  ) values (
    p_financial_source_account_id,p_connected_source_id,v_kind,'active',
    p_provenance||jsonb_build_object(
      'authority','link_financial_source_account_connector_self_api_v2',
      'connectorIsTransportNotAccountIdentity',true
    ),p_metadata
  ) on conflict(financial_source_account_id,connected_source_id)
  do update set
    link_kind=excluded.link_kind,
    link_state='active',
    retired_at=null,
    provenance=atlas.financial_source_account_connector_links.provenance||excluded.provenance,
    metadata=atlas.financial_source_account_connector_links.metadata||excluded.metadata
  returning * into v_link;

  return jsonb_build_object(
    'contractVersion','financial_source_account_connector_link_v2',
    'state','linked',
    'linkId',v_link.id,
    'financialSourceAccountId',v_link.financial_source_account_id,
    'connectedSourceId',v_link.connected_source_id,
    'linkKind',v_link.link_kind
  );
end;
$$;

revoke all on function atlas.link_financial_source_account_connector_self_api_v2(uuid,uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.link_financial_source_account_connector_self_api_v2(uuid,uuid,text,jsonb,jsonb)
  to authenticated;

create or replace function atlas.designate_financial_source_account_holder_self_api_v2(
  p_financial_source_account_id uuid,
  p_holder_entity_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,reality
as $$
declare
  v_principal_id uuid;
  v_holder reality.entities%rowtype;
  v_record atlas.financial_source_account_reality_holders%rowtype;
begin
  if not atlas.financial_source_account_authorized_self_v2(p_financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;
  if p_holder_entity_id is null then
    raise exception 'Canonical Reality account-holder entity is required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Account-holder provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_holder
  from reality.entities entity
  where entity.id=p_holder_entity_id
    and entity.identity_state='canonical';
  if v_holder.id is null then
    raise exception 'Canonical Reality account-holder entity required.' using errcode='23503';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();

  insert into atlas.financial_source_account_reality_holders(
    financial_source_account_id,holder_entity_id,established_by_principal_id,established_by_user_id,
    provenance,metadata
  ) values (
    p_financial_source_account_id,p_holder_entity_id,v_principal_id,auth.uid(),
    p_provenance||jsonb_build_object(
      'authority','designate_financial_source_account_holder_self_api_v2',
      'technicalCustodyDoesNotEstablishAccountOwnership',true
    ),p_metadata
  ) on conflict(financial_source_account_id,holder_entity_id) do nothing
  returning * into v_record;

  if v_record.id is null then
    select * into v_record
    from atlas.financial_source_account_reality_holders holder
    where holder.financial_source_account_id=p_financial_source_account_id
      and holder.holder_entity_id=p_holder_entity_id;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_account_holder_v2',
    'financialSourceAccountId',p_financial_source_account_id,
    'accountHolderId',v_record.id,
    'holderEntityId',v_holder.id,
    'holderDisplayName',v_holder.display_name
  );
end;
$$;

revoke all on function atlas.designate_financial_source_account_holder_self_api_v2(uuid,uuid,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.designate_financial_source_account_holder_self_api_v2(uuid,uuid,jsonb,jsonb)
  to authenticated;

create or replace function atlas.financial_source_account_holders_self_api_v2(
  p_financial_source_account_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth,reality
as $$
begin
  if not atlas.financial_source_account_authorized_self_v2(p_financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_account_holders_v2',
    'financialSourceAccountId',p_financial_source_account_id,
    'holders',coalesce((
      select jsonb_agg(jsonb_build_object(
        'accountHolderId',holder.id,
        'entityId',entity.id,
        'stableKey',entity.stable_key,
        'entityKind',entity.entity_kind,
        'displayName',entity.display_name,
        'identityState',entity.identity_state,
        'establishedAt',holder.established_at
      ) order by entity.display_name,entity.id)
      from atlas.financial_source_account_reality_holders holder
      join reality.entities entity on entity.id=holder.holder_entity_id
      where holder.financial_source_account_id=p_financial_source_account_id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'technicalCustodyDoesNotEstablishAccountOwnership',true,
      'accountOwnershipDoesNotEstablishOperationalBeneficiary',true,
      'multipleAccountHoldersPermitted',true
    )
  );
end;
$$;

revoke all on function atlas.financial_source_account_holders_self_api_v2(uuid) from public,anon;
grant execute on function atlas.financial_source_account_holders_self_api_v2(uuid) to authenticated;

create or replace function atlas.record_financial_source_evidence_service_v2(
  p_financial_source_account_id uuid,
  p_observation_kind text,
  p_source_kind text,
  p_source_object_key text,
  p_value jsonb,
  p_observed_at timestamptz default null,
  p_connected_source_observation_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $$
declare
  v_kind text:=lower(btrim(coalesce(p_observation_kind,'')));
  v_source_kind text:=lower(btrim(coalesce(p_source_kind,'')));
  v_object_key text:=btrim(coalesce(p_source_object_key,''));
  v_hash text;
  v_evidence_source_key text;
  v_evidence_id uuid;
  v_observation atlas.financial_source_evidence_observations%rowtype;
  v_connector_source_id uuid;
begin
  if not exists(
    select 1 from atlas.financial_source_accounts account
    where account.id=p_financial_source_account_id and account.source_state='active'
  ) then
    raise exception 'Active financial source account required.' using errcode='23503';
  end if;
  if v_kind not in ('financial_statement','financial_transaction') then
    raise exception 'Observation kind must be financial_statement or financial_transaction.' using errcode='22023';
  end if;
  if v_source_kind='' or v_object_key='' then
    raise exception 'Financial evidence source kind and stable source object key are required.' using errcode='22023';
  end if;
  if p_value is null or jsonb_typeof(p_value)<>'object' then
    raise exception 'Financial evidence value must be a JSON object.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Financial evidence provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  if p_connected_source_observation_id is not null then
    select observation.connected_source_id into v_connector_source_id
    from atlas.connected_source_observations observation
    where observation.id=p_connected_source_observation_id;
    if v_connector_source_id is null or not exists(
      select 1
      from atlas.financial_source_account_connector_links link
      where link.financial_source_account_id=p_financial_source_account_id
        and link.connected_source_id=v_connector_source_id
        and link.link_state='active'
        and link.retired_at is null
    ) then
      raise exception 'Connected-source observation must belong to an active connector linked to this financial account.' using errcode='23514';
    end if;
  end if;

  v_hash:=encode(digest(p_value::text,'sha256'),'hex');
  v_evidence_source_key:=v_source_kind||':'||v_kind||':'||v_object_key||':'||v_hash;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
    source_kind,source_key,actor_user_id,value,confidence,observed_at,provenance,metadata
  ) values (
    'financial_source_account',p_financial_source_account_id,
    'finance','financial_source_account',p_financial_source_account_id::text,v_kind,
    v_source_kind,v_evidence_source_key,null,p_value,1,p_observed_at,
    p_provenance||jsonb_build_object(
      'authority','record_financial_source_evidence_service_v2',
      'sourceObjectKey',v_object_key,
      'observationSha256',v_hash,
      'connectorObservationOptional',true
    ),p_metadata
  ) on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_id;

  if v_evidence_id is null then
    select evidence.id into v_evidence_id
    from atlas.evidence_records evidence
    where evidence.scope_kind='financial_source_account'
      and evidence.scope_id=p_financial_source_account_id
      and evidence.source_kind=v_source_kind
      and evidence.source_key=v_evidence_source_key;
  end if;

  insert into atlas.financial_source_evidence_observations(
    financial_source_account_id,evidence_record_id,observation_kind,source_kind,
    source_object_key,observation_sha256,connected_source_observation_id,observed_at,
    provenance,metadata
  ) values (
    p_financial_source_account_id,v_evidence_id,v_kind,v_source_kind,
    v_object_key,v_hash,p_connected_source_observation_id,p_observed_at,
    p_provenance,p_metadata
  ) on conflict(financial_source_account_id,observation_kind,source_object_key,observation_sha256)
  do nothing
  returning * into v_observation;

  if v_observation.id is null then
    select * into v_observation
    from atlas.financial_source_evidence_observations observation
    where observation.financial_source_account_id=p_financial_source_account_id
      and observation.observation_kind=v_kind
      and observation.source_object_key=v_object_key
      and observation.observation_sha256=v_hash;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_evidence_observation_v2',
    'financialSourceAccountId',p_financial_source_account_id,
    'financialEvidenceObservationId',v_observation.id,
    'evidenceRecordId',v_observation.evidence_record_id,
    'observationKind',v_observation.observation_kind,
    'sourceKind',v_observation.source_kind,
    'sourceObjectKey',v_observation.source_object_key,
    'observationSha256',v_observation.observation_sha256,
    'connectedSourceObservationId',v_observation.connected_source_observation_id,
    'truthBoundary',jsonb_build_object(
      'evidenceDoesNotCreateBookkeepingInterpretation',true,
      'connectorAuthorizationOptional',true,
      'rawObservedSnapshotLivesInEvidenceRecord',true
    )
  );
end;
$$;

revoke all on function atlas.record_financial_source_evidence_service_v2(
  uuid,text,text,text,jsonb,timestamptz,uuid,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_evidence_service_v2(
  uuid,text,text,text,jsonb,timestamptz,uuid,jsonb,jsonb
) to service_role;
