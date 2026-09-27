-- Atlas financial source party resolution v1
--
-- Purpose:
--   let immutable source-party text be linked to a canonical Reality entity
--   after review without rewriting the bank/provider evidence.
--
-- Truth boundary:
--   matching text is not identity;
--   this relation does not create or merge Reality entities;
--   changing a source-party resolution requires an explicit supersession flow.

create table atlas.financial_source_transaction_party_resolutions (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  party_role text not null default 'counterparty' check (party_role='counterparty'),
  literal_label text not null check (btrim(literal_label)<>''),
  entity_id uuid not null references reality.entities(id) on delete restrict,
  resolution_state text not null default 'active' check (resolution_state in ('active','superseded')),
  establishment_kind text not null default 'human_confirmed' check (establishment_kind='human_confirmed'),
  resolved_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  client_event_key text not null check (btrim(client_event_key)<>''),
  resolution_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  unique(resolved_by_principal_id,client_event_key),
  check ((resolution_state='superseded')=(superseded_at is not null))
);

create unique index financial_source_transaction_party_active_idx
  on atlas.financial_source_transaction_party_resolutions(transaction_id,party_role)
  where resolution_state='active';

create index financial_source_transaction_party_entity_idx
  on atlas.financial_source_transaction_party_resolutions(entity_id,resolution_state);

alter table atlas.financial_source_transaction_party_resolutions enable row level security;
revoke all on table atlas.financial_source_transaction_party_resolutions from public,anon,authenticated;

create or replace function atlas.financial_source_transaction_party_resolution_v1(
  p_transaction_id uuid,
  p_party_role text default 'counterparty'
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'transactionId',p_transaction_id,
    'partyRole',p_party_role,
    'resolution',(
      select jsonb_build_object(
        'resolutionId',r.id,
        'literalLabel',r.literal_label,
        'entityId',r.entity_id,
        'entityKind',e.entity_kind,
        'entityDisplayName',e.display_name,
        'resolutionState',r.resolution_state,
        'establishmentKind',r.establishment_kind,
        'resolutionBasis',r.resolution_basis,
        'createdAt',r.created_at
      )
      from atlas.financial_source_transaction_party_resolutions r
      join reality.entities e on e.id=r.entity_id
      where r.transaction_id=p_transaction_id
        and r.party_role=p_party_role
        and r.resolution_state='active'
      order by r.created_at,r.id
      limit 1
    ),
    'truthBoundary',jsonb_build_object(
      'sourceLabelRemainsEvidence',true,
      'entityIdentityNotMutated',true,
      'automaticEntityMerge',false
    )
  ));
$function$;

revoke all on function atlas.financial_source_transaction_party_resolution_v1(uuid,text)
  from public,anon,authenticated;

create or replace function atlas.resolve_financial_source_transaction_party_self_api_v1(
  p_transaction_id uuid,
  p_entity_id uuid,
  p_client_event_key text,
  p_resolution_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','reality','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_tx atlas.financial_source_transactions%rowtype;
  v_existing atlas.financial_source_transaction_party_resolutions%rowtype;
  v_event atlas.financial_source_transaction_party_resolutions%rowtype;
  v_entity reality.entities%rowtype;
begin
  if auth.uid() is null or v_principal is null then
    raise exception 'Signed-in Principal required.' using errcode='42501';
  end if;
  if v_key='' then
    raise exception 'Client event key required.' using errcode='22023';
  end if;
  if p_resolution_basis is null or jsonb_typeof(p_resolution_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Resolution basis and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_event
  from atlas.financial_source_transaction_party_resolutions r
  where r.resolved_by_principal_id=v_principal
    and r.client_event_key=v_key;

  if v_event.id is not null then
    if v_event.transaction_id is distinct from p_transaction_id
       or v_event.entity_id is distinct from p_entity_id
       or v_event.party_role<>'counterparty' then
      raise exception 'Client event key already belongs to a different source-party resolution.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'contractVersion','resolve_financial_source_transaction_party_self_api_v1',
      'state','unchanged',
      'resolutionId',v_event.id,
      'transactionId',v_event.transaction_id,
      'entityId',v_event.entity_id,
      'literalLabel',v_event.literal_label
    );
  end if;

  select * into v_tx
  from atlas.financial_source_transactions t
  where t.id=p_transaction_id
  for update;

  if v_tx.id is null then
    raise exception 'Financial source transaction required.' using errcode='P0002';
  end if;
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then
    raise exception 'Connected source custody required.' using errcode='42501';
  end if;
  if v_tx.counterparty_label is null or btrim(v_tx.counterparty_label)='' then
    raise exception 'This source transaction has no counterparty label to resolve.' using errcode='23514';
  end if;

  select * into v_entity
  from reality.entities e
  where e.id=p_entity_id
    and e.identity_state='canonical';

  if v_entity.id is null then
    raise exception 'Canonical Reality entity required.' using errcode='23503';
  end if;

  select * into v_existing
  from atlas.financial_source_transaction_party_resolutions r
  where r.transaction_id=v_tx.id
    and r.party_role='counterparty'
    and r.resolution_state='active'
  for update;

  if v_existing.id is not null then
    if v_existing.entity_id is distinct from v_entity.id then
      raise exception 'Source counterparty already resolves to another canonical entity; use an explicit supersession flow.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'contractVersion','resolve_financial_source_transaction_party_self_api_v1',
      'state','already_resolved',
      'resolutionId',v_existing.id,
      'transactionId',v_existing.transaction_id,
      'entityId',v_existing.entity_id,
      'literalLabel',v_existing.literal_label
    );
  end if;

  insert into atlas.financial_source_transaction_party_resolutions(
    transaction_id,party_role,literal_label,entity_id,resolution_state,
    establishment_kind,resolved_by_principal_id,client_event_key,resolution_basis,metadata
  ) values(
    v_tx.id,'counterparty',v_tx.counterparty_label,v_entity.id,'active',
    'human_confirmed',v_principal,v_key,p_resolution_basis,p_metadata
  ) returning * into v_event;

  return jsonb_build_object(
    'contractVersion','resolve_financial_source_transaction_party_self_api_v1',
    'state','resolved',
    'resolutionId',v_event.id,
    'transactionId',v_event.transaction_id,
    'literalLabel',v_event.literal_label,
    'entityId',v_event.entity_id,
    'entityKind',v_entity.entity_kind,
    'entityDisplayName',v_entity.display_name,
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceMutated',false,
      'sourceLabelPreserved',true,
      'entityIdentityMutated',false,
      'automaticEntityMerge',false,
      'taxTreatmentEstablished',false,
      'operationalPurposeEstablished',false
    )
  );
end;
$function$;

revoke all on function atlas.resolve_financial_source_transaction_party_self_api_v1(uuid,uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.resolve_financial_source_transaction_party_self_api_v1(uuid,uuid,text,jsonb,jsonb)
  to authenticated;

comment on table atlas.financial_source_transaction_party_resolutions is
  'Human-confirmed links from immutable source-party labels to canonical Reality entities. The link never rewrites source evidence or merges identities.';
