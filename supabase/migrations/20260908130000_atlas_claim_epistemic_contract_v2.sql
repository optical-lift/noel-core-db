-- Atlas Claim epistemic contract v2
--
-- Evolves the existing universal claim_records / claim_evidence_links envelope.
-- This is deliberately additive: legacy claims remain readable exactly as they
-- were recorded, while new claim-v2 rows must carry explicit predicate,
-- modality, adjudication, and typed value semantics.

begin;

alter table atlas.claim_records
  add column semantic_contract_version text,
  add column predicate_key text,
  add column modality text,
  add column adjudication_state text,
  add column value_kind text,
  add column value_unit text;

comment on column atlas.claim_records.semantic_contract_version is
  'Null identifies legacy claim-envelope rows. claim-v2 rows must satisfy the explicit epistemic and typed-value contract.';
comment on column atlas.claim_records.predicate_key is
  'Machine-readable semantic predicate/dimension. Presentation prose must not be stored here.';
comment on column atlas.claim_records.modality is
  'How the claim is epistemically held: observed, authoritative_assertion, derived, planned, forecast, estimated, or unknown.';
comment on column atlas.claim_records.adjudication_state is
  'Independent adjudication state for the claim: current, accepted, disputed, rejected, superseded, or expired.';
comment on column atlas.claim_records.value_kind is
  'Canonical type of claim_records.value for claim-v2 rows.';
comment on column atlas.claim_records.value_unit is
  'Optional governed semantic unit for numeric claim-v2 values.';

alter table atlas.claim_records
  add constraint claim_records_semantic_contract_version_check
  check (semantic_contract_version is null or semantic_contract_version = 'claim-v2'),
  add constraint claim_records_predicate_key_check
  check (
    semantic_contract_version is distinct from 'claim-v2'
    or predicate_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  add constraint claim_records_modality_check
  check (
    semantic_contract_version is distinct from 'claim-v2'
    or modality in (
      'observed',
      'authoritative_assertion',
      'derived',
      'planned',
      'forecast',
      'estimated',
      'unknown'
    )
  ),
  add constraint claim_records_adjudication_state_check
  check (
    semantic_contract_version is distinct from 'claim-v2'
    or adjudication_state in (
      'current',
      'accepted',
      'disputed',
      'rejected',
      'superseded',
      'expired'
    )
  ),
  add constraint claim_records_value_kind_check
  check (
    semantic_contract_version is distinct from 'claim-v2'
    or value_kind in ('number','boolean','code','date','datetime','reference')
  ),
  add constraint claim_records_numeric_unit_check
  check (
    value_unit is null
    or (
      semantic_contract_version = 'claim-v2'
      and value_kind = 'number'
      and value_unit ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
    )
  );

create or replace function atlas.claim_value_matches_kind_v2(
  p_value_kind text,
  p_value jsonb
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_value_kind
    when 'number' then jsonb_typeof(p_value) = 'number'
    when 'boolean' then jsonb_typeof(p_value) = 'boolean'
    when 'code' then
      jsonb_typeof(p_value) = 'string'
      and trim(both '"' from p_value::text) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
    when 'date' then
      jsonb_typeof(p_value) = 'string'
      and trim(both '"' from p_value::text) ~ '^\d{4}-\d{2}-\d{2}$'
    when 'datetime' then
      jsonb_typeof(p_value) = 'string'
      and trim(both '"' from p_value::text) ~ '^\d{4}-\d{2}-\d{2}T'
    when 'reference' then
      jsonb_typeof(p_value) = 'object'
      and jsonb_typeof(p_value->'kind') = 'string'
      and jsonb_typeof(p_value->'id') = 'string'
      and btrim(coalesce(p_value->>'kind','')) <> ''
      and btrim(coalesce(p_value->>'id','')) <> ''
    else false
  end;
$$;

comment on function atlas.claim_value_matches_kind_v2(text,jsonb) is
  'Pure validator for the claim-v2 typed value contract. Reference values are canonical identity objects {kind,id}; prose is not a supported canonical claim value kind.';

revoke all on function atlas.claim_value_matches_kind_v2(text,jsonb) from public, anon, authenticated;
grant execute on function atlas.claim_value_matches_kind_v2(text,jsonb) to service_role;

alter table atlas.claim_records
  add constraint claim_records_typed_value_check
  check (
    semantic_contract_version is distinct from 'claim-v2'
    or atlas.claim_value_matches_kind_v2(value_kind, value)
  );

create index claim_records_semantic_subject_idx
  on atlas.claim_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    predicate_key,
    adjudication_state,
    recorded_at desc,
    id
  )
  where semantic_contract_version = 'claim-v2';

create table atlas.claim_adjudication_relations (
  id uuid primary key default gen_random_uuid(),
  from_claim_id uuid not null references atlas.claim_records(id) on delete cascade,
  to_claim_id uuid not null references atlas.claim_records(id) on delete restrict,
  relation_kind text not null check (relation_kind in ('contradicts','corrects','supersedes')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  check (from_claim_id <> to_claim_id),
  unique (from_claim_id, to_claim_id, relation_kind)
);

comment on table atlas.claim_adjudication_relations is
  'Claim-to-claim epistemic relations. Direction is from the newer/asserting claim to the claim it contradicts, corrects, or supersedes. Evidence support remains in claim_evidence_links.';

create index claim_adjudication_relations_to_idx
  on atlas.claim_adjudication_relations(to_claim_id, relation_kind, from_claim_id);

create or replace function atlas.guard_claim_adjudication_relation_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_from_scope_kind text;
  v_from_scope_id uuid;
  v_from_subject_domain text;
  v_from_subject_kind text;
  v_from_subject_id text;
  v_to_scope_kind text;
  v_to_scope_id uuid;
  v_to_subject_domain text;
  v_to_subject_kind text;
  v_to_subject_id text;
begin
  select c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id
  into v_from_scope_kind,v_from_scope_id,v_from_subject_domain,v_from_subject_kind,v_from_subject_id
  from atlas.claim_records c where c.id = new.from_claim_id;

  select c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id
  into v_to_scope_kind,v_to_scope_id,v_to_subject_domain,v_to_subject_kind,v_to_subject_id
  from atlas.claim_records c where c.id = new.to_claim_id;

  if v_from_scope_kind is null or v_to_scope_kind is null
     or v_from_scope_kind is distinct from v_to_scope_kind
     or v_from_scope_id is distinct from v_to_scope_id
     or v_from_subject_domain is distinct from v_to_subject_domain
     or v_from_subject_kind is distinct from v_to_subject_kind
     or v_from_subject_id is distinct from v_to_subject_id then
    raise exception 'Claim adjudication relations cannot cross custody scope or subject.' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_claim_adjudication_relation_scope_v1() from public, anon, authenticated;
grant execute on function atlas.guard_claim_adjudication_relation_scope_v1() to service_role;

create trigger claim_adjudication_relations_scope_guard_v1
before insert or update on atlas.claim_adjudication_relations
for each row execute function atlas.guard_claim_adjudication_relation_scope_v1();

alter table atlas.claim_adjudication_relations enable row level security;

create policy claim_adjudication_relations_person_self_read
on atlas.claim_adjudication_relations for select to authenticated
using (
  exists (
    select 1
    from atlas.claim_records c
    where c.id = from_claim_id
      and c.scope_kind = 'person'
      and c.scope_id = auth.uid()
  )
);

grant select on atlas.claim_adjudication_relations to authenticated;
grant select,insert,update,delete on atlas.claim_adjudication_relations to service_role;

-- Preserve the legacy self-supersession column as a compatibility index into
-- the new explicit relation graph. Existing rows are untouched; future claim-v2
-- writers should establish both lifecycle/adjudication state and the relation.
insert into atlas.claim_adjudication_relations(from_claim_id,to_claim_id,relation_kind,metadata)
select c.id, c.supersedes_claim_id, 'supersedes', jsonb_build_object('source','legacy_supersedes_claim_id')
from atlas.claim_records c
where c.supersedes_claim_id is not null
on conflict (from_claim_id,to_claim_id,relation_kind) do nothing;

comment on table atlas.claim_records is
  'Universal claims separated from supporting evidence. Legacy rows retain lifecycle_state/value as recorded. claim-v2 rows additionally require explicit predicate, epistemic modality, independent adjudication state, and typed canonical value semantics.';

commit;
