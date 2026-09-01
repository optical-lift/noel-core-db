BEGIN;

-- Atlas Financial Reality Kernel v1 — executable architecture proof only.
--
-- This file is intentionally NOT a canonical Supabase migration. It proves the
-- provider-neutral schema/authority contract while the branch remains stacked on
-- the Money Collection design. A governed migration identity must be generated
-- only after this wider contract is reviewed.

create table atlas.financial_source_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_record_kind text not null check (btrim(provider_record_kind) <> ''),
  provider_record_id text not null check (btrim(provider_record_id) <> ''),
  observation_fingerprint text not null check (btrim(observation_fingerprint) <> ''),
  provider_event_id text,
  observed_at timestamptz not null default now(),
  effective_at timestamptz,
  direction text check (direction is null or direction in ('inflow','outflow','transfer','noncash')),
  gross_amount numeric(18,2) check (gross_amount is null or gross_amount >= 0),
  fee_amount numeric(18,2) check (fee_amount is null or fee_amount >= 0),
  net_amount numeric(18,2) check (net_amount is null or net_amount >= 0),
  currency text,
  counterparty_label text,
  document_number text,
  description text,
  provider_state text,
  normalized_data jsonb not null default '{}'::jsonb,
  payload_sha256 text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_source_observation_identity_uq
    unique (connected_source_id,provider_record_kind,provider_record_id,observation_fingerprint),
  check (currency is null or btrim(currency) <> ''),
  check (jsonb_typeof(normalized_data)='object'),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_source_observations is
  'Append-only normalized evidence from an organization-owned connected financial source. A source observation reports provider truth; it is not itself the canonical economic event.';

create index financial_source_observations_org_effective_idx
  on atlas.financial_source_observations(organization_id,effective_at desc,created_at desc,id);
create index financial_source_observations_provider_object_idx
  on atlas.financial_source_observations(connected_source_id,provider_record_kind,provider_record_id,created_at desc,id);
create index financial_source_observations_provider_event_idx
  on atlas.financial_source_observations(connected_source_id,provider_event_id)
  where provider_event_id is not null;

create table atlas.financial_economic_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  event_key text not null check (btrim(event_key) <> ''),
  event_kind text not null check (btrim(event_kind) <> ''),
  direction text not null check (direction in ('inflow','outflow','transfer','noncash')),
  amount numeric(18,2) not null check (amount >= 0),
  currency text not null check (btrim(currency) <> ''),
  occurred_at timestamptz not null,
  counterparty_kind text,
  counterparty_id text,
  counterparty_label text,
  source_domain text,
  source_kind text,
  source_id text,
  authority_kind text not null check (btrim(authority_kind) <> ''),
  authority_ref text not null check (btrim(authority_ref) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_economic_event_key_uq unique(organization_id,event_key),
  check (
    (source_domain is null and source_kind is null and source_id is null)
    or
    (nullif(btrim(coalesce(source_domain,'')),'') is not null
      and nullif(btrim(coalesce(source_kind,'')),'') is not null
      and nullif(btrim(coalesce(source_id,'')),'') is not null)
  ),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_economic_events is
  'Provider-neutral canonical economic occurrences. Provider observations may establish/corroborate an event, but provider object identity never becomes the universal financial model.';

create index financial_economic_events_org_occurred_idx
  on atlas.financial_economic_events(organization_id,occurred_at desc,id);
create index financial_economic_events_source_idx
  on atlas.financial_economic_events(organization_id,source_domain,source_kind,source_id)
  where source_id is not null;

create table atlas.financial_event_evidence_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  observation_id uuid not null references atlas.financial_source_observations(id) on delete restrict,
  evidence_role text not null check (evidence_role in (
    'establishes','corroborates','documents','classifies','settles','contradicts'
  )),
  admission_kind text not null check (btrim(admission_kind) <> ''),
  admission_ref text not null check (btrim(admission_ref) <> ''),
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_event_evidence_link_uq unique(
    economic_event_id,observation_id,evidence_role,admission_kind,admission_ref
  ),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_event_evidence_links is
  'Accepted provenance connecting source observations to canonical economic events. A contradiction is preserved as evidence rather than silently resolved.';

create index financial_event_evidence_observation_idx
  on atlas.financial_event_evidence_links(observation_id,economic_event_id);

create table atlas.financial_event_relations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  from_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  to_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  relation_kind text not null check (btrim(relation_kind) <> ''),
  admission_kind text not null check (btrim(admission_kind) <> ''),
  admission_ref text not null check (btrim(admission_ref) <> ''),
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_event_relation_not_self check (from_event_id <> to_event_id),
  constraint financial_event_relation_uq unique(
    from_event_id,to_event_id,relation_kind,admission_kind,admission_ref
  ),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_event_relations is
  'Accepted relationships between canonical economic events, such as fee_on, refund_of, settles, contains, bank_settlement_of, or transfer_counterpart. Relations prevent settlement layers from becoming duplicate revenue.';

create index financial_event_relations_to_idx
  on atlas.financial_event_relations(to_event_id,relation_kind,from_event_id);

create table atlas.financial_classification_assertions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  taxonomy_key text not null check (btrim(taxonomy_key) <> ''),
  classification_key text not null check (btrim(classification_key) <> ''),
  classification_label text,
  source_kind text not null check (source_kind in (
    'accounting_system','human','organization_rule','provider_hint','model_suggestion'
  )),
  source_ref text not null check (btrim(source_ref) <> ''),
  authority_rank integer not null check (authority_rank >= 0),
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  supersedes_assertion_id uuid references atlas.financial_classification_assertions(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_classification_assertion_uq unique(
    economic_event_id,taxonomy_key,classification_key,source_kind,source_ref
  ),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_classification_assertions is
  'Append-only classification evidence. Event existence is independent from bookkeeping/tax classification; model/provider hints cannot silently overwrite stronger accounting/human evidence.';

create index financial_classification_event_taxonomy_idx
  on atlas.financial_classification_assertions(economic_event_id,taxonomy_key,authority_rank desc,created_at desc,id desc);

create or replace function atlas.reject_financial_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Atlas financial source/reconciliation history is append-only.' using errcode='55000';
end;
$function$;

revoke all on function atlas.reject_financial_history_mutation_v1() from public,anon,authenticated,service_role;

create trigger financial_source_observations_append_only_v1
before update or delete on atlas.financial_source_observations
for each row execute function atlas.reject_financial_history_mutation_v1();
create trigger financial_economic_events_append_only_v1
before update or delete on atlas.financial_economic_events
for each row execute function atlas.reject_financial_history_mutation_v1();
create trigger financial_event_evidence_links_append_only_v1
before update or delete on atlas.financial_event_evidence_links
for each row execute function atlas.reject_financial_history_mutation_v1();
create trigger financial_event_relations_append_only_v1
before update or delete on atlas.financial_event_relations
for each row execute function atlas.reject_financial_history_mutation_v1();
create trigger financial_classification_assertions_append_only_v1
before update or delete on atlas.financial_classification_assertions
for each row execute function atlas.reject_financial_history_mutation_v1();

create or replace function atlas.guard_financial_source_observation_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
begin
  select * into v_source
  from atlas.connected_sources s
  where s.id=new.connected_source_id;

  if v_source.id is null then
    raise exception 'Connected financial source not found.' using errcode='23503';
  end if;
  if v_source.custodian_organization_id is null
     or v_source.custodian_organization_id is distinct from new.organization_id then
    raise exception 'Financial source observation is outside organization source custody.' using errcode='42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_source_observation_custody_v1() from public,anon,authenticated,service_role;

create trigger financial_source_observation_custody_guard_v1
before insert on atlas.financial_source_observations
for each row execute function atlas.guard_financial_source_observation_custody_v1();

create or replace function atlas.guard_financial_event_evidence_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event_org uuid;
  v_observation_org uuid;
begin
  select organization_id into v_event_org
  from atlas.financial_economic_events where id=new.economic_event_id;
  select organization_id into v_observation_org
  from atlas.financial_source_observations where id=new.observation_id;
  if v_event_org is null or v_observation_org is null then
    raise exception 'Financial event/evidence reference not found.' using errcode='23503';
  end if;
  if v_event_org is distinct from new.organization_id
     or v_observation_org is distinct from new.organization_id then
    raise exception 'Financial evidence link crosses organization custody.' using errcode='42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_event_evidence_custody_v1() from public,anon,authenticated,service_role;

create trigger financial_event_evidence_custody_guard_v1
before insert on atlas.financial_event_evidence_links
for each row execute function atlas.guard_financial_event_evidence_custody_v1();

create or replace function atlas.guard_financial_event_relation_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_from_org uuid;
  v_to_org uuid;
begin
  select organization_id into v_from_org from atlas.financial_economic_events where id=new.from_event_id;
  select organization_id into v_to_org from atlas.financial_economic_events where id=new.to_event_id;
  if v_from_org is null or v_to_org is null then
    raise exception 'Financial relation event not found.' using errcode='23503';
  end if;
  if v_from_org is distinct from new.organization_id
     or v_to_org is distinct from new.organization_id then
    raise exception 'Financial event relation crosses organization custody.' using errcode='42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_event_relation_custody_v1() from public,anon,authenticated,service_role;

create trigger financial_event_relation_custody_guard_v1
before insert on atlas.financial_event_relations
for each row execute function atlas.guard_financial_event_relation_custody_v1();

create or replace function atlas.guard_financial_classification_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event_org uuid;
  v_superseded atlas.financial_classification_assertions%rowtype;
begin
  select organization_id into v_event_org
  from atlas.financial_economic_events where id=new.economic_event_id;
  if v_event_org is null or v_event_org is distinct from new.organization_id then
    raise exception 'Financial classification crosses organization custody.' using errcode='42501';
  end if;
  if new.supersedes_assertion_id is not null then
    select * into v_superseded
    from atlas.financial_classification_assertions
    where id=new.supersedes_assertion_id;
    if v_superseded.id is null
       or v_superseded.organization_id is distinct from new.organization_id
       or v_superseded.economic_event_id is distinct from new.economic_event_id
       or v_superseded.taxonomy_key is distinct from new.taxonomy_key then
      raise exception 'Financial classification supersession does not match event/taxonomy custody.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_classification_custody_v1() from public,anon,authenticated,service_role;

create trigger financial_classification_custody_guard_v1
before insert on atlas.financial_classification_assertions
for each row execute function atlas.guard_financial_classification_custody_v1();

create or replace function atlas.record_financial_source_observation_core_v1(
  p_organization_id uuid,
  p_connected_source_id uuid,
  p_provider_record_kind text,
  p_provider_record_id text,
  p_observation_fingerprint text,
  p_provider_event_id text,
  p_observed_at timestamptz,
  p_effective_at timestamptz,
  p_direction text,
  p_gross_amount numeric,
  p_fee_amount numeric,
  p_net_amount numeric,
  p_currency text,
  p_counterparty_label text,
  p_document_number text,
  p_description text,
  p_provider_state text,
  p_normalized_data jsonb,
  p_payload_sha256 text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.financial_source_observations%rowtype;
  v_row atlas.financial_source_observations%rowtype;
begin
  if p_organization_id is null or p_connected_source_id is null
     or nullif(btrim(coalesce(p_provider_record_kind,'')),'') is null
     or nullif(btrim(coalesce(p_provider_record_id,'')),'') is null
     or nullif(btrim(coalesce(p_observation_fingerprint,'')),'') is null then
    raise exception 'Financial source observation requires organization, source, provider record identity, and fingerprint.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.financial_source_observations o
  where o.connected_source_id=p_connected_source_id
    and o.provider_record_kind=btrim(p_provider_record_kind)
    and o.provider_record_id=btrim(p_provider_record_id)
    and o.observation_fingerprint=btrim(p_observation_fingerprint);

  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','record_financial_source_observation_core_v1',
      'state','unchanged','observationId',v_existing.id,'deduplicated',true
    );
  end if;

  insert into atlas.financial_source_observations(
    organization_id,connected_source_id,provider_record_kind,provider_record_id,
    observation_fingerprint,provider_event_id,observed_at,effective_at,direction,
    gross_amount,fee_amount,net_amount,currency,counterparty_label,document_number,
    description,provider_state,normalized_data,payload_sha256,metadata
  ) values (
    p_organization_id,p_connected_source_id,btrim(p_provider_record_kind),btrim(p_provider_record_id),
    btrim(p_observation_fingerprint),nullif(btrim(coalesce(p_provider_event_id,'')),''),
    coalesce(p_observed_at,now()),p_effective_at,p_direction,
    case when p_gross_amount is null then null else round(p_gross_amount,2) end,
    case when p_fee_amount is null then null else round(p_fee_amount,2) end,
    case when p_net_amount is null then null else round(p_net_amount,2) end,
    nullif(lower(btrim(coalesce(p_currency,''))),''),nullif(btrim(coalesce(p_counterparty_label,'')),''),
    nullif(btrim(coalesce(p_document_number,'')),''),nullif(btrim(coalesce(p_description,'')),''),
    nullif(btrim(coalesce(p_provider_state,'')),''),coalesce(p_normalized_data,'{}'::jsonb),
    nullif(btrim(coalesce(p_payload_sha256,'')),''),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','record_financial_source_observation_core_v1',
    'state','recorded','observationId',v_row.id,'deduplicated',false
  );
end;
$function$;

create or replace function atlas.ensure_financial_economic_event_core_v1(
  p_organization_id uuid,
  p_event_key text,
  p_event_kind text,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_occurred_at timestamptz,
  p_counterparty_kind text,
  p_counterparty_id text,
  p_counterparty_label text,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_authority_kind text,
  p_authority_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.financial_economic_events%rowtype;
  v_row atlas.financial_economic_events%rowtype;
begin
  if p_organization_id is null
     or nullif(btrim(coalesce(p_event_key,'')),'') is null
     or nullif(btrim(coalesce(p_event_kind,'')),'') is null
     or p_direction not in ('inflow','outflow','transfer','noncash')
     or p_amount is null or p_amount<0
     or nullif(btrim(coalesce(p_currency,'')),'') is null
     or p_occurred_at is null
     or nullif(btrim(coalesce(p_authority_kind,'')),'') is null
     or nullif(btrim(coalesce(p_authority_ref,'')),'') is null then
    raise exception 'Financial economic event requires organization, stable key, kind, direction, non-negative amount, currency, occurredAt, and authority.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.financial_economic_events e
  where e.organization_id=p_organization_id and e.event_key=btrim(p_event_key);

  if v_existing.id is not null then
    if v_existing.event_kind is distinct from btrim(p_event_kind)
       or v_existing.direction is distinct from p_direction
       or v_existing.amount is distinct from round(p_amount,2)
       or v_existing.currency is distinct from lower(btrim(p_currency))
       or v_existing.occurred_at is distinct from p_occurred_at
       or v_existing.source_domain is distinct from nullif(btrim(coalesce(p_source_domain,'')),'')
       or v_existing.source_kind is distinct from nullif(btrim(coalesce(p_source_kind,'')),'')
       or v_existing.source_id is distinct from nullif(btrim(coalesce(p_source_id,'')),'')
       or v_existing.authority_kind is distinct from btrim(p_authority_kind)
       or v_existing.authority_ref is distinct from btrim(p_authority_ref) then
      raise exception 'Existing financial event key cannot be silently rewritten.' using errcode='55000';
    end if;
    return jsonb_build_object(
      'contractVersion','ensure_financial_economic_event_core_v1',
      'state','unchanged','economicEventId',v_existing.id,'deduplicated',true
    );
  end if;

  insert into atlas.financial_economic_events(
    organization_id,event_key,event_kind,direction,amount,currency,occurred_at,
    counterparty_kind,counterparty_id,counterparty_label,
    source_domain,source_kind,source_id,authority_kind,authority_ref,metadata
  ) values (
    p_organization_id,btrim(p_event_key),btrim(p_event_kind),p_direction,round(p_amount,2),lower(btrim(p_currency)),p_occurred_at,
    nullif(btrim(coalesce(p_counterparty_kind,'')),''),nullif(btrim(coalesce(p_counterparty_id,'')),''),
    nullif(btrim(coalesce(p_counterparty_label,'')),''),nullif(btrim(coalesce(p_source_domain,'')),''),
    nullif(btrim(coalesce(p_source_kind,'')),''),nullif(btrim(coalesce(p_source_id,'')),''),
    btrim(p_authority_kind),btrim(p_authority_ref),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','ensure_financial_economic_event_core_v1',
    'state','recorded','economicEventId',v_row.id,'deduplicated',false
  );
end;
$function$;

create or replace function atlas.link_financial_observation_to_event_core_v1(
  p_organization_id uuid,
  p_economic_event_id uuid,
  p_observation_id uuid,
  p_evidence_role text,
  p_admission_kind text,
  p_admission_ref text,
  p_confidence numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_event_evidence_links%rowtype;
begin
  if p_evidence_role not in ('establishes','corroborates','documents','classifies','settles','contradicts')
     or nullif(btrim(coalesce(p_admission_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_ref,'')),'') is null then
    raise exception 'Financial evidence link requires a supported role and explicit admission basis.' using errcode='22023';
  end if;
  insert into atlas.financial_event_evidence_links(
    organization_id,economic_event_id,observation_id,evidence_role,admission_kind,admission_ref,confidence,metadata
  ) values (
    p_organization_id,p_economic_event_id,p_observation_id,p_evidence_role,
    btrim(p_admission_kind),btrim(p_admission_ref),p_confidence,coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (economic_event_id,observation_id,evidence_role,admission_kind,admission_ref)
    do update set economic_event_id=excluded.economic_event_id
  returning * into v_row;
  return jsonb_build_object(
    'contractVersion','link_financial_observation_to_event_core_v1',
    'evidenceLinkId',v_row.id
  );
end;
$function$;

create or replace function atlas.relate_financial_economic_events_core_v1(
  p_organization_id uuid,
  p_from_event_id uuid,
  p_to_event_id uuid,
  p_relation_kind text,
  p_admission_kind text,
  p_admission_ref text,
  p_confidence numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_event_relations%rowtype;
begin
  if nullif(btrim(coalesce(p_relation_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_ref,'')),'') is null then
    raise exception 'Financial event relation requires relation kind and explicit admission basis.' using errcode='22023';
  end if;
  insert into atlas.financial_event_relations(
    organization_id,from_event_id,to_event_id,relation_kind,admission_kind,admission_ref,confidence,metadata
  ) values (
    p_organization_id,p_from_event_id,p_to_event_id,btrim(p_relation_kind),
    btrim(p_admission_kind),btrim(p_admission_ref),p_confidence,coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (from_event_id,to_event_id,relation_kind,admission_kind,admission_ref)
    do update set from_event_id=excluded.from_event_id
  returning * into v_row;
  return jsonb_build_object(
    'contractVersion','relate_financial_economic_events_core_v1',
    'relationId',v_row.id
  );
end;
$function$;

create or replace function atlas.assert_financial_classification_core_v1(
  p_organization_id uuid,
  p_economic_event_id uuid,
  p_taxonomy_key text,
  p_classification_key text,
  p_classification_label text,
  p_source_kind text,
  p_source_ref text,
  p_authority_rank integer,
  p_confidence numeric,
  p_supersedes_assertion_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_classification_assertions%rowtype;
begin
  if nullif(btrim(coalesce(p_taxonomy_key,'')),'') is null
     or nullif(btrim(coalesce(p_classification_key,'')),'') is null
     or p_source_kind not in ('accounting_system','human','organization_rule','provider_hint','model_suggestion')
     or nullif(btrim(coalesce(p_source_ref,'')),'') is null
     or p_authority_rank is null or p_authority_rank<0 then
    raise exception 'Financial classification requires taxonomy, classification, source, and non-negative authority rank.' using errcode='22023';
  end if;
  insert into atlas.financial_classification_assertions(
    organization_id,economic_event_id,taxonomy_key,classification_key,classification_label,
    source_kind,source_ref,authority_rank,confidence,supersedes_assertion_id,metadata
  ) values (
    p_organization_id,p_economic_event_id,btrim(p_taxonomy_key),btrim(p_classification_key),
    nullif(btrim(coalesce(p_classification_label,'')),''),p_source_kind,btrim(p_source_ref),
    p_authority_rank,p_confidence,p_supersedes_assertion_id,coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (economic_event_id,taxonomy_key,classification_key,source_kind,source_ref)
    do update set economic_event_id=excluded.economic_event_id
  returning * into v_row;
  return jsonb_build_object(
    'contractVersion','assert_financial_classification_core_v1',
    'classificationAssertionId',v_row.id
  );
end;
$function$;

-- Provider-neutral read position. This deliberately reports ambiguity instead of
-- selecting a category when multiple unsuperseded top-authority assertions disagree.
create or replace view atlas.financial_classification_position_v1 as
with current_assertions as (
  select a.*
  from atlas.financial_classification_assertions a
  where not exists (
    select 1 from atlas.financial_classification_assertions newer
    where newer.supersedes_assertion_id=a.id
  )
), ranked as (
  select a.*,
         max(a.authority_rank) over(partition by a.economic_event_id,a.taxonomy_key) as top_rank
  from current_assertions a
), top_set as (
  select * from ranked where authority_rank=top_rank
)
select
  e.organization_id,
  e.id as economic_event_id,
  t.taxonomy_key,
  count(distinct t.classification_key)::integer as top_classification_count,
  case when count(distinct t.classification_key)=1 then min(t.classification_key) else null end as effective_classification_key,
  case when count(distinct t.classification_key)=1 then min(t.classification_label) else null end as effective_classification_label,
  case
    when count(distinct t.classification_key)=0 then 'missing'
    when count(distinct t.classification_key)=1 then 'resolved'
    else 'conflict'
  end as classification_state,
  max(t.top_rank) as authority_rank
from atlas.financial_economic_events e
join top_set t on t.economic_event_id=e.id
Group by e.organization_id,e.id,t.taxonomy_key;

-- Minimal reconciliation position: external observations without an accepted
-- evidence link remain unresolved; explicit contradiction evidence remains visible.
create or replace view atlas.financial_observation_reconciliation_position_v1 as
select
  o.organization_id,
  o.id as observation_id,
  o.connected_source_id,
  o.provider_record_kind,
  o.provider_record_id,
  o.observation_fingerprint,
  count(l.id)::integer as accepted_link_count,
  count(l.id) filter(where l.evidence_role='contradicts')::integer as contradiction_count,
  case
    when count(l.id)=0 then 'unreconciled'
    when count(l.id) filter(where l.evidence_role='contradicts')>0 then 'contradictory'
    else 'linked'
  end as reconciliation_state
from atlas.financial_source_observations o
left join atlas.financial_event_evidence_links l on l.observation_id=o.id
Group by o.organization_id,o.id,o.connected_source_id,o.provider_record_kind,o.provider_record_id,o.observation_fingerprint;

alter table atlas.financial_source_observations enable row level security;
alter table atlas.financial_economic_events enable row level security;
alter table atlas.financial_event_evidence_links enable row level security;
alter table atlas.financial_event_relations enable row level security;
alter table atlas.financial_classification_assertions enable row level security;

revoke all on atlas.financial_source_observations from public,anon,authenticated,service_role;
revoke all on atlas.financial_economic_events from public,anon,authenticated,service_role;
revoke all on atlas.financial_event_evidence_links from public,anon,authenticated,service_role;
revoke all on atlas.financial_event_relations from public,anon,authenticated,service_role;
revoke all on atlas.financial_classification_assertions from public,anon,authenticated,service_role;
revoke all on atlas.financial_classification_position_v1 from public,anon,authenticated,service_role;
revoke all on atlas.financial_observation_reconciliation_position_v1 from public,anon,authenticated,service_role;

grant select,insert on atlas.financial_source_observations to service_role;
grant select,insert on atlas.financial_economic_events to service_role;
grant select,insert on atlas.financial_event_evidence_links to service_role;
grant select,insert on atlas.financial_event_relations to service_role;
grant select,insert on atlas.financial_classification_assertions to service_role;
grant select on atlas.financial_classification_position_v1 to service_role;
grant select on atlas.financial_observation_reconciliation_position_v1 to service_role;

revoke all on function atlas.record_financial_source_observation_core_v1(
  uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,numeric,numeric,numeric,text,text,text,text,text,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_observation_core_v1(
  uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,numeric,numeric,numeric,text,text,text,text,text,jsonb,text,jsonb
) to service_role;

revoke all on function atlas.ensure_financial_economic_event_core_v1(
  uuid,text,text,text,numeric,text,timestamptz,text,text,text,text,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ensure_financial_economic_event_core_v1(
  uuid,text,text,text,numeric,text,timestamptz,text,text,text,text,text,text,text,text,jsonb
) to service_role;

revoke all on function atlas.link_financial_observation_to_event_core_v1(
  uuid,uuid,uuid,text,text,text,numeric,jsonb
) from public,anon,authenticated;
grant execute on function atlas.link_financial_observation_to_event_core_v1(
  uuid,uuid,uuid,text,text,text,numeric,jsonb
) to service_role;

revoke all on function atlas.relate_financial_economic_events_core_v1(
  uuid,uuid,uuid,text,text,text,numeric,jsonb
) from public,anon,authenticated;
grant execute on function atlas.relate_financial_economic_events_core_v1(
  uuid,uuid,uuid,text,text,text,numeric,jsonb
) to service_role;

revoke all on function atlas.assert_financial_classification_core_v1(
  uuid,uuid,text,text,text,text,text,integer,numeric,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.assert_financial_classification_core_v1(
  uuid,uuid,text,text,text,text,text,integer,numeric,uuid,jsonb
) to service_role;

-- Structural proofs.
do $proof$
declare
  v_missing integer;
begin
  if not exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='financial_source_observations'
      and t.tgname='financial_source_observation_custody_guard_v1' and not t.tgisinternal
  ) then
    raise exception 'Financial Reality proof failed: connected-source organization custody guard missing.';
  end if;

  if has_table_privilege('authenticated','atlas.financial_source_observations','SELECT')
     or has_table_privilege('authenticated','atlas.financial_economic_events','SELECT') then
    raise exception 'Financial Reality proof failed: raw financial tables leaked to authenticated role.';
  end if;

  select count(*) into v_missing
  from (values
    ('record_financial_source_observation_core_v1'),
    ('ensure_financial_economic_event_core_v1'),
    ('link_financial_observation_to_event_core_v1'),
    ('relate_financial_economic_events_core_v1'),
    ('assert_financial_classification_core_v1')
  ) required(name)
  where not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.proname=required.name
  );
  if v_missing<>0 then
    raise exception 'Financial Reality proof failed: % core functions missing.',v_missing;
  end if;
end;
$proof$;

-- Architecture proof only.
ROLLBACK;
