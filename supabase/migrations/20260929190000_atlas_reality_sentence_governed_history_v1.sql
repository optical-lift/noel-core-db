begin;

-- Atlas Reality Sentence governed history v1.
-- Complete bounded reads; no legacy backfill, no inferred identity, no SQL precedence.

create table if not exists atlas.responsibility_applicability_governance (
  record_id uuid primary key default gen_random_uuid(),
  contract_version text not null default 'responsibility_applicability_governance_v1',
  applicability_relation_id uuid not null references reality.entity_relationships(id) on delete restrict,
  responsibility_entity_id uuid not null references reality.entities(id) on delete restrict,
  target_entity_id uuid not null references reality.entities(id) on delete restrict,
  operation_key text not null,
  governance_state text not null,
  valid_from timestamptz not null,
  valid_until timestamptz null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint responsibility_applicability_governance_contract_v1 check (contract_version = 'responsibility_applicability_governance_v1'),
  constraint responsibility_applicability_governance_operation_v1 check (btrim(operation_key) <> ''),
  constraint responsibility_applicability_governance_state_v1 check (governance_state in ('established', 'retired')),
  constraint responsibility_applicability_governance_window_v1 check (valid_until is null or valid_until > valid_from),
  constraint responsibility_applicability_governance_provenance_v1 check (jsonb_typeof(provenance) = 'object')
);

create index if not exists responsibility_applicability_governance_exact_v1_idx
  on atlas.responsibility_applicability_governance
  (responsibility_entity_id, target_entity_id, operation_key, applicability_relation_id, valid_from, record_id);

create table if not exists atlas.execution_authority_history (
  event_id uuid primary key default gen_random_uuid(),
  authority_id uuid not null,
  contract_version text not null default 'execution_authority_history_event_v1',
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  institution_entity_id uuid not null references reality.entities(id) on delete restrict,
  responsibility_entity_id uuid not null references reality.entities(id) on delete restrict,
  target_entity_id uuid not null references reality.entities(id) on delete restrict,
  operation_key text not null,
  authority_state text not null,
  authority_valid_from timestamptz not null,
  authority_valid_until timestamptz null,
  effective_at timestamptz not null,
  carrier_kind text not null,
  carrier_id text not null,
  carrier_event_id text null,
  evidence jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint execution_authority_history_contract_v1 check (contract_version = 'execution_authority_history_event_v1'),
  constraint execution_authority_history_operation_v1 check (btrim(operation_key) <> ''),
  constraint execution_authority_history_state_v1 check (authority_state in ('leased', 'started', 'interrupted', 'completed', 'withdrawn', 'expired')),
  constraint execution_authority_history_window_v1 check (authority_valid_until is null or authority_valid_until > authority_valid_from),
  constraint execution_authority_history_carrier_v1 check (btrim(carrier_kind) <> '' and btrim(carrier_id) <> ''),
  constraint execution_authority_history_evidence_v1 check (jsonb_typeof(evidence) = 'object'),
  constraint execution_authority_history_provenance_v1 check (jsonb_typeof(provenance) = 'object')
);

create index if not exists execution_authority_history_exact_v1_idx
  on atlas.execution_authority_history
  (person_entity_id, institution_entity_id, responsibility_entity_id, target_entity_id, operation_key, authority_id, effective_at, event_id);

create table if not exists atlas.execution_participation_history (
  event_id uuid primary key default gen_random_uuid(),
  participation_id uuid not null,
  contract_version text not null default 'execution_participation_history_event_v1',
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  institution_entity_id uuid not null references reality.entities(id) on delete restrict,
  responsibility_entity_id uuid not null references reality.entities(id) on delete restrict,
  target_entity_id uuid not null references reality.entities(id) on delete restrict,
  operation_key text not null,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  participation_role_key text not null,
  participation_state text not null,
  participation_valid_from timestamptz not null,
  participation_valid_until timestamptz null,
  basis_authority_id uuid not null,
  basis_authority_event_id uuid not null references atlas.execution_authority_history(event_id) on delete restrict,
  effective_at timestamptz not null,
  carrier_kind text not null,
  carrier_id text not null,
  carrier_event_id text null,
  evidence jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint execution_participation_history_contract_v1 check (contract_version = 'execution_participation_history_event_v1'),
  constraint execution_participation_history_operation_v1 check (btrim(operation_key) <> ''),
  constraint execution_participation_history_role_v1 check (btrim(participation_role_key) <> ''),
  constraint execution_participation_history_state_v1 check (participation_state in ('participating', 'ended', 'withdrawn')),
  constraint execution_participation_history_window_v1 check (participation_valid_until is null or participation_valid_until > participation_valid_from),
  constraint execution_participation_history_carrier_v1 check (btrim(carrier_kind) <> '' and btrim(carrier_id) <> ''),
  constraint execution_participation_history_evidence_v1 check (jsonb_typeof(evidence) = 'object'),
  constraint execution_participation_history_provenance_v1 check (jsonb_typeof(provenance) = 'object')
);

create index if not exists execution_participation_history_exact_v1_idx
  on atlas.execution_participation_history
  (person_entity_id, institution_entity_id, responsibility_entity_id, target_entity_id, operation_key, work_item_id, participation_role_key, participation_id, effective_at, event_id);

alter table atlas.responsibility_applicability_governance enable row level security;
alter table atlas.execution_authority_history enable row level security;
alter table atlas.execution_participation_history enable row level security;
revoke all on atlas.responsibility_applicability_governance from anon, authenticated;
revoke all on atlas.execution_authority_history from anon, authenticated;
revoke all on atlas.execution_participation_history from anon, authenticated;

create or replace function atlas.guard_responsibility_applicability_governance_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, atlas, reality as $$
declare v_kind text; v_subject uuid; v_object uuid;
begin
  select r.relationship_kind, r.subject_entity_id, r.object_entity_id into v_kind, v_subject, v_object
  from reality.entity_relationships r where r.id = new.applicability_relation_id;
  if v_kind is distinct from 'responsibility_applies_to'
     or v_subject is distinct from new.responsibility_entity_id
     or v_object is distinct from new.target_entity_id then
    raise exception 'Applicability governance must reference the exact canonical responsibility_applies_to relation';
  end if;
  if not exists (select 1 from reality.entities e where e.id = new.responsibility_entity_id and e.entity_kind = 'responsibility' and e.identity_state = 'canonical') then
    raise exception 'Applicability governance requires a canonical Responsibility Entity';
  end if;
  if not exists (select 1 from reality.entities e where e.id = new.target_entity_id and e.identity_state = 'canonical') then
    raise exception 'Applicability governance requires a canonical target Reality Entity';
  end if;
  return new;
end; $$;

drop trigger if exists trg_guard_responsibility_applicability_governance_v1 on atlas.responsibility_applicability_governance;
create trigger trg_guard_responsibility_applicability_governance_v1
before insert or update on atlas.responsibility_applicability_governance
for each row execute function atlas.guard_responsibility_applicability_governance_v1();

create or replace function atlas.preserve_responsibility_applicability_governance_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, atlas, reality as $$
begin
  if new.record_id is distinct from old.record_id
     or new.contract_version is distinct from old.contract_version
     or new.applicability_relation_id is distinct from old.applicability_relation_id
     or new.responsibility_entity_id is distinct from old.responsibility_entity_id
     or new.target_entity_id is distinct from old.target_entity_id
     or new.operation_key is distinct from old.operation_key
     or new.governance_state is distinct from old.governance_state
     or new.valid_from is distinct from old.valid_from
     or new.provenance is distinct from old.provenance
     or new.created_at is distinct from old.created_at then
    raise exception 'Responsibility applicability governance semantic history is immutable';
  end if;
  if old.valid_until is not null and new.valid_until is distinct from old.valid_until then
    raise exception 'A closed Responsibility applicability governance interval cannot be rewritten';
  end if;
  if old.valid_until is null and new.valid_until is null then
    raise exception 'The only permitted governance update is closing an open valid_until interval';
  end if;
  new.updated_at := statement_timestamp();
  return new;
end; $$;

drop trigger if exists trg_preserve_responsibility_applicability_governance_v1 on atlas.responsibility_applicability_governance;
create trigger trg_preserve_responsibility_applicability_governance_v1
before update on atlas.responsibility_applicability_governance
for each row execute function atlas.preserve_responsibility_applicability_governance_v1();

create or replace function atlas.reject_responsibility_applicability_governance_delete_v1()
returns trigger language plpgsql as $$
begin
  raise exception 'responsibility_applicability_governance is durable governed history; DELETE is not permitted';
end; $$;

drop trigger if exists trg_reject_responsibility_applicability_governance_delete_v1 on atlas.responsibility_applicability_governance;
create trigger trg_reject_responsibility_applicability_governance_delete_v1
before delete on atlas.responsibility_applicability_governance
for each row execute function atlas.reject_responsibility_applicability_governance_delete_v1();

create or replace function atlas.guard_execution_authority_history_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, atlas, reality as $$
begin
  if not exists (select 1 from reality.entities e where e.id = new.person_entity_id and e.entity_kind = 'person' and e.identity_state = 'canonical') then
    raise exception 'Execution Authority requires a canonical Person Entity';
  end if;
  if not exists (select 1 from reality.entities e where e.id = new.institution_entity_id and e.entity_kind not in ('person','position','responsibility') and e.identity_state = 'canonical') then
    raise exception 'Execution Authority requires a canonical Institution Entity';
  end if;
  if not exists (select 1 from reality.entities e where e.id = new.responsibility_entity_id and e.entity_kind = 'responsibility' and e.identity_state = 'canonical') then
    raise exception 'Execution Authority requires a canonical Responsibility Entity';
  end if;
  if not exists (select 1 from reality.entities e where e.id = new.target_entity_id and e.identity_state = 'canonical') then
    raise exception 'Execution Authority requires a canonical target Reality Entity';
  end if;
  return new;
end; $$;

drop trigger if exists trg_guard_execution_authority_history_v1 on atlas.execution_authority_history;
create trigger trg_guard_execution_authority_history_v1 before insert on atlas.execution_authority_history
for each row execute function atlas.guard_execution_authority_history_v1();

create or replace function atlas.guard_execution_participation_history_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, atlas, reality as $$
declare v_authority atlas.execution_authority_history%rowtype;
begin
  select * into v_authority from atlas.execution_authority_history a where a.event_id = new.basis_authority_event_id;
  if not found then raise exception 'Execution Participation requires an existing basis Execution Authority event'; end if;
  if v_authority.authority_state not in ('leased','started') then
    raise exception 'Execution Participation basis must be an actionable Execution Authority event';
  end if;
  if v_authority.authority_id is distinct from new.basis_authority_id
     or v_authority.person_entity_id is distinct from new.person_entity_id
     or v_authority.institution_entity_id is distinct from new.institution_entity_id
     or v_authority.responsibility_entity_id is distinct from new.responsibility_entity_id
     or v_authority.target_entity_id is distinct from new.target_entity_id
     or v_authority.operation_key is distinct from new.operation_key then
    raise exception 'Execution Participation basis must match the exact canonical Execution Authority coordinate';
  end if;
  return new;
end; $$;

drop trigger if exists trg_guard_execution_participation_history_v1 on atlas.execution_participation_history;
create trigger trg_guard_execution_participation_history_v1 before insert on atlas.execution_participation_history
for each row execute function atlas.guard_execution_participation_history_v1();

create or replace function atlas.reject_reality_sentence_history_mutation_v1()
returns trigger language plpgsql as $$
begin raise exception '% is append-only; % is not permitted', tg_table_name, tg_op; end; $$;

drop trigger if exists trg_reject_execution_authority_history_mutation_v1 on atlas.execution_authority_history;
create trigger trg_reject_execution_authority_history_mutation_v1 before update or delete on atlas.execution_authority_history
for each row execute function atlas.reject_reality_sentence_history_mutation_v1();
drop trigger if exists trg_reject_execution_participation_history_mutation_v1 on atlas.execution_participation_history;
create trigger trg_reject_execution_participation_history_mutation_v1 before update or delete on atlas.execution_participation_history
for each row execute function atlas.reject_reality_sentence_history_mutation_v1();

create or replace function atlas.reality_sentence_entity_read_v1(p_entity_id uuid)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, atlas, reality as $$
  select jsonb_build_object(
    'id',e.id::text,'stableKey',e.stable_key,'kind',e.entity_kind,'displayName',e.display_name,
    'identityState',e.identity_state,'metadata',e.metadata)
  from reality.entities e where e.id = p_entity_id and e.identity_state = 'canonical';
$$;
revoke all on function atlas.reality_sentence_entity_read_v1(uuid) from public, anon, authenticated;

create or replace function atlas.reality_sentence_self_person_entity_id_v1()
returns uuid language plpgsql stable security definer set search_path = pg_catalog, public, auth, atlas, reality as $$
declare v_entity_id uuid; v_count integer;
begin
  select count(distinct b.canonical_entity_id),
         (array_agg(distinct b.canonical_entity_id order by b.canonical_entity_id))[1]
    into v_count, v_entity_id
  from atlas.person_auth_credentials c
  join atlas.person_canonical_entity_bindings b on b.person_id = c.person_id
    and b.binding_state = 'verified' and b.retired_at is null and b.disputed_at is null
  join reality.entities e on e.id = b.canonical_entity_id and e.entity_kind = 'person' and e.identity_state = 'canonical'
  where c.auth_user_id = auth.uid() and c.status = 'active' and c.retired_at is null;
  if v_count <> 1 then return null; end if;
  return v_entity_id;
end; $$;
revoke all on function atlas.reality_sentence_self_person_entity_id_v1() from public, anon, authenticated;

create or replace function atlas.institutional_relation_history_self_api_v1(p_institution_entity_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, auth, atlas, reality as $$
declare
  v_captured_at timestamptz := statement_timestamp();
  v_person_entity_id uuid; v_person jsonb; v_institution jsonb; v_relations jsonb; v_entities jsonb;
begin
  v_person_entity_id := atlas.reality_sentence_self_person_entity_id_v1();
  if v_person_entity_id is null then
    return jsonb_build_object('contractVersion','institutional_relation_history_self_v1','state','person_binding_required',
      'capturedAt',v_captured_at,'relations','[]'::jsonb,'entities','[]'::jsonb,'completeness',jsonb_build_object('complete',false));
  end if;
  v_person := atlas.reality_sentence_entity_read_v1(v_person_entity_id);
  v_institution := atlas.reality_sentence_entity_read_v1(p_institution_entity_id);
  if v_institution is null or coalesce(v_institution->>'kind','') in ('person','position','responsibility') then
    raise exception 'Institutional history requires an exact canonical Institution Entity';
  end if;

  with person_positions as (
    select distinct r.object_entity_id position_id from reality.entity_relationships r
    where r.relationship_kind='occupies_position' and r.subject_entity_id=v_person_entity_id
  ), scoped_positions as (
    select distinct p.position_id from person_positions p where exists (
      select 1 from reality.entity_relationships r where r.relationship_kind='institution_has_position'
      and r.subject_entity_id=p_institution_entity_id and r.object_entity_id=p.position_id)
  ), position_responsibilities as (
    select distinct r.object_entity_id responsibility_id from reality.entity_relationships r
    join scoped_positions p on p.position_id=r.subject_entity_id where r.relationship_kind='position_carries_responsibility'
  ), scoped_responsibilities as (
    select distinct pr.responsibility_id from position_responsibilities pr where exists (
      select 1 from reality.entity_relationships r where r.relationship_kind='institution_has_responsibility'
      and r.subject_entity_id=p_institution_entity_id and r.object_entity_id=pr.responsibility_id)
  ), bounded_relations as (
    select r.* from reality.entity_relationships r where
      (r.relationship_kind='institutional_standing' and r.subject_entity_id=v_person_entity_id and r.object_entity_id=p_institution_entity_id)
      or (r.relationship_kind='occupies_position' and r.subject_entity_id=v_person_entity_id and r.object_entity_id in (select position_id from scoped_positions))
      or (r.relationship_kind='institution_has_position' and r.subject_entity_id=p_institution_entity_id and r.object_entity_id in (select position_id from scoped_positions))
      or (r.relationship_kind='position_carries_responsibility' and r.subject_entity_id in (select position_id from scoped_positions) and r.object_entity_id in (select responsibility_id from scoped_responsibilities))
      or (r.relationship_kind='institution_has_responsibility' and r.subject_entity_id=p_institution_entity_id and r.object_entity_id in (select responsibility_id from scoped_responsibilities))
  ), relation_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'relationId',r.id::text,'relationshipKind',r.relationship_kind,'relationshipState',r.relationship_state,
      'subjectEntityId',r.subject_entity_id::text,'objectEntityId',r.object_entity_id::text,
      'validFrom',r.valid_from,'validUntil',r.valid_until,'evidence',r.evidence,'metadata',r.metadata,
      'createdAt',r.created_at,'updatedAt',r.updated_at) order by r.created_at,r.id),'[]'::jsonb) value
    from bounded_relations r
  ), entity_ids as (
    select v_person_entity_id entity_id union select p_institution_entity_id
    union select position_id from scoped_positions union select responsibility_id from scoped_responsibilities
  ), entity_json as (
    select coalesce(jsonb_agg(atlas.reality_sentence_entity_read_v1(ei.entity_id) order by ei.entity_id)
      filter (where atlas.reality_sentence_entity_read_v1(ei.entity_id) is not null),'[]'::jsonb) value from entity_ids ei
  )
  select rj.value,ej.value into v_relations,v_entities from relation_json rj cross join entity_json ej;

  return jsonb_build_object(
    'contractVersion','institutional_relation_history_self_v1','state','ready','capturedAt',v_captured_at,
    'person',v_person,'institution',v_institution,'relations',v_relations,'entities',v_entities,
    'completeness',jsonb_build_object('complete',true,'boundedToPersonEntityId',v_person_entity_id::text,
      'boundedToInstitutionEntityId',p_institution_entity_id::text,
      'relationFamilies',jsonb_build_array('institutional_standing','institution_has_position','institution_has_responsibility','occupies_position','position_carries_responsibility'),
      'includesAllRelationshipStates',true,'historicalIntervalsPreserved',true,'personPathComplete',true,'institutionWideStructure',false),
    'truthBoundary',jsonb_build_object('readDoesNotCreateReality',true,'readDoesNotEnumerateInstitutionWideStructure',true,
      'legacyOrganizationIdentifiersAcceptedAsCanonical',false,'executionAuthorityCreated',false,'workAllocationCreated',false,'taskCreated',false));
end; $$;

create or replace function atlas.responsibility_applicability_history_api_v1(
  p_responsibility_entity_id uuid,p_target_entity_id uuid,p_operation_key text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, atlas, reality as $$
declare v_captured_at timestamptz := statement_timestamp(); v_responsibility jsonb; v_target jsonb; v_relations jsonb;
begin
  if p_operation_key is null or btrim(p_operation_key)='' then raise exception 'operation_key must be nonblank'; end if;
  v_responsibility := atlas.reality_sentence_entity_read_v1(p_responsibility_entity_id);
  v_target := atlas.reality_sentence_entity_read_v1(p_target_entity_id);
  if v_responsibility is null or v_responsibility->>'kind'<>'responsibility' then raise exception 'Applicability history requires a canonical Responsibility Entity'; end if;
  if v_target is null then raise exception 'Applicability history requires a canonical target Reality Entity'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'relationId',r.id::text,'relationshipKind','responsibility_applies_to','relationshipState',r.relationship_state,
    'responsibilityEntityId',r.subject_entity_id::text,'targetEntityId',r.object_entity_id::text,
    'validFrom',r.valid_from,'validUntil',r.valid_until,'evidence',r.evidence,'metadata',r.metadata,
    'governance',case when g.record_id is null then null else jsonb_build_object(
      'governanceId',g.record_id::text,'operationKey',g.operation_key,'governanceState',g.governance_state,
      'validFrom',g.valid_from,'validUntil',g.valid_until,'provenance',g.provenance,'createdAt',g.created_at,'updatedAt',g.updated_at) end,
    'createdAt',r.created_at,'updatedAt',r.updated_at)
    order by r.created_at,r.id,g.created_at nulls first,g.record_id nulls first),'[]'::jsonb)
  into v_relations
  from reality.entity_relationships r
  left join atlas.responsibility_applicability_governance g on g.applicability_relation_id=r.id
    and g.responsibility_entity_id=p_responsibility_entity_id and g.target_entity_id=p_target_entity_id and g.operation_key=p_operation_key
  where r.relationship_kind='responsibility_applies_to' and r.subject_entity_id=p_responsibility_entity_id and r.object_entity_id=p_target_entity_id;

  return jsonb_build_object(
    'contractVersion','responsibility_applicability_history_v1','state','ready','capturedAt',v_captured_at,
    'responsibility',v_responsibility,'target',v_target,'operationKey',p_operation_key,'relations',v_relations,
    'completeness',jsonb_build_object('complete',true,'exactResponsibilityEntityId',p_responsibility_entity_id::text,
      'exactTargetEntityId',p_target_entity_id::text,'exactOperationKey',p_operation_key,'relationFamily','responsibility_applies_to',
      'includesAllRelationshipStates',true,'includesRelationsWithoutGovernance',true,
      'includesAllMatchingOperationGovernanceStates',true,'historicalIntervalsPreserved',true),
    'truthBoundary',jsonb_build_object('readDoesNotCreateReality',true,'legacyOrganizationResponsibilityIdsAcceptedAsCanonical',false,
      'executionAuthorityCreated',false,'workAllocationCreated',false,'principalClaimCreated',false,'clockOrTodayStateCreated',false));
end; $$;

create or replace function atlas.execution_authority_history_api_v1(
  p_person_entity_id uuid,p_institution_entity_id uuid,p_responsibility_entity_id uuid,p_target_entity_id uuid,p_operation_key text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, auth, atlas, reality as $$
declare
  v_captured_at timestamptz := statement_timestamp(); v_self uuid; v_person jsonb; v_institution jsonb;
  v_responsibility jsonb; v_target jsonb; v_history jsonb;
begin
  v_self := atlas.reality_sentence_self_person_entity_id_v1();
  if v_self is null or v_self<>p_person_entity_id then raise exception 'Execution Authority self read requires the authenticated canonical Person coordinate'; end if;
  if p_operation_key is null or btrim(p_operation_key)='' then raise exception 'operation_key must be nonblank'; end if;
  v_person:=atlas.reality_sentence_entity_read_v1(p_person_entity_id);
  v_institution:=atlas.reality_sentence_entity_read_v1(p_institution_entity_id);
  v_responsibility:=atlas.reality_sentence_entity_read_v1(p_responsibility_entity_id);
  v_target:=atlas.reality_sentence_entity_read_v1(p_target_entity_id);
  if v_person is null or v_person->>'kind'<>'person' then raise exception 'Execution Authority history requires a canonical Person Entity'; end if;
  if v_institution is null or coalesce(v_institution->>'kind','') in ('person','position','responsibility') then raise exception 'Execution Authority history requires a canonical Institution Entity'; end if;
  if v_responsibility is null or v_responsibility->>'kind'<>'responsibility' then raise exception 'Execution Authority history requires a canonical Responsibility Entity'; end if;
  if v_target is null then raise exception 'Execution Authority history requires a canonical target Reality Entity'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',h.event_id::text,'authorityId',h.authority_id::text,'personEntityId',h.person_entity_id::text,
    'institutionEntityId',h.institution_entity_id::text,'responsibilityEntityId',h.responsibility_entity_id::text,
    'targetEntityId',h.target_entity_id::text,'operationKey',h.operation_key,'authorityState',h.authority_state,
    'authorityValidFrom',h.authority_valid_from,'authorityValidUntil',h.authority_valid_until,'effectiveAt',h.effective_at,
    'carrierKind',h.carrier_kind,'carrierId',h.carrier_id,'carrierEventId',h.carrier_event_id,
    'evidence',h.evidence,'provenance',h.provenance,'createdAt',h.created_at)
    order by h.effective_at,h.created_at,h.event_id),'[]'::jsonb)
  into v_history from atlas.execution_authority_history h
  where h.person_entity_id=p_person_entity_id and h.institution_entity_id=p_institution_entity_id
    and h.responsibility_entity_id=p_responsibility_entity_id and h.target_entity_id=p_target_entity_id and h.operation_key=p_operation_key;

  return jsonb_build_object(
    'contractVersion','execution_authority_history_v1','state','ready','capturedAt',v_captured_at,
    'person',v_person,'institution',v_institution,'responsibility',v_responsibility,'target',v_target,'operationKey',p_operation_key,'history',v_history,
    'completeness',jsonb_build_object('complete',true,'exactPersonEntityId',p_person_entity_id::text,
      'exactInstitutionEntityId',p_institution_entity_id::text,'exactResponsibilityEntityId',p_responsibility_entity_id::text,
      'exactTargetEntityId',p_target_entity_id::text,'exactOperationKey',p_operation_key,'includesAllAuthorityStates',true,
      'includesAllMatchingAuthorityChains',true,'historicalEventsPreserved',true,'laterEventsDoNotReplaceEarlierEvents',true),
    'truthBoundary',jsonb_build_object('readDoesNotCreateReality',true,'workerDayIdentifiersAcceptedAsCanonicalIdentity',false,
      'executionAuthorityWarrantCreated',false,'workAllocationCreated',false,'taskCreated',false,'principalClaimCreated',false,
      'clockOrTodayStateCreated',false,'workPerformedEstablished',false,'terminalAuthorityStateEstablishesUnderlyingSubjectOutcome',false));
end; $$;

create or replace function atlas.execution_participation_history_api_v1(
  p_person_entity_id uuid,p_institution_entity_id uuid,p_responsibility_entity_id uuid,p_target_entity_id uuid,
  p_operation_key text,p_work_item_id uuid,p_participation_role_key text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, auth, atlas, reality as $$
declare
  v_captured_at timestamptz := statement_timestamp(); v_self uuid; v_person jsonb; v_institution jsonb;
  v_responsibility jsonb; v_target jsonb; v_history jsonb;
begin
  v_self:=atlas.reality_sentence_self_person_entity_id_v1();
  if v_self is null or v_self<>p_person_entity_id then raise exception 'Execution Participation self read requires the authenticated canonical Person coordinate'; end if;
  if p_operation_key is null or btrim(p_operation_key)='' or p_participation_role_key is null or btrim(p_participation_role_key)='' then
    raise exception 'operation_key and participation_role_key must be nonblank';
  end if;
  if not exists (select 1 from atlas.work_items w where w.id=p_work_item_id) then raise exception 'Execution Participation requires an existing Company Work identity'; end if;
  v_person:=atlas.reality_sentence_entity_read_v1(p_person_entity_id);
  v_institution:=atlas.reality_sentence_entity_read_v1(p_institution_entity_id);
  v_responsibility:=atlas.reality_sentence_entity_read_v1(p_responsibility_entity_id);
  v_target:=atlas.reality_sentence_entity_read_v1(p_target_entity_id);
  if v_person is null or v_person->>'kind'<>'person' or v_institution is null or v_responsibility is null or v_responsibility->>'kind'<>'responsibility' or v_target is null then
    raise exception 'Execution Participation requires complete canonical Reality coordinates';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',h.event_id::text,'participationId',h.participation_id::text,'personEntityId',h.person_entity_id::text,
    'institutionEntityId',h.institution_entity_id::text,'responsibilityEntityId',h.responsibility_entity_id::text,
    'targetEntityId',h.target_entity_id::text,'operationKey',h.operation_key,'workItemId',h.work_item_id::text,
    'participationRoleKey',h.participation_role_key,'participationState',h.participation_state,
    'participationValidFrom',h.participation_valid_from,'participationValidUntil',h.participation_valid_until,
    'basisAuthorityId',h.basis_authority_id::text,'basisAuthorityEventId',h.basis_authority_event_id::text,
    'effectiveAt',h.effective_at,'carrierKind',h.carrier_kind,'carrierId',h.carrier_id,'carrierEventId',h.carrier_event_id,
    'evidence',h.evidence,'provenance',h.provenance,'createdAt',h.created_at)
    order by h.effective_at,h.created_at,h.event_id),'[]'::jsonb)
  into v_history from atlas.execution_participation_history h
  where h.person_entity_id=p_person_entity_id and h.institution_entity_id=p_institution_entity_id
    and h.responsibility_entity_id=p_responsibility_entity_id and h.target_entity_id=p_target_entity_id
    and h.operation_key=p_operation_key and h.work_item_id=p_work_item_id and h.participation_role_key=p_participation_role_key;

  return jsonb_build_object(
    'contractVersion','execution_participation_history_v1','state','ready','capturedAt',v_captured_at,
    'person',v_person,'institution',v_institution,'responsibility',v_responsibility,'target',v_target,'operationKey',p_operation_key,
    'workItemId',p_work_item_id::text,'workIdentitySource','atlas.work_items.id','participationRoleKey',p_participation_role_key,'history',v_history,
    'completeness',jsonb_build_object('complete',true,'exactPersonEntityId',p_person_entity_id::text,
      'exactInstitutionEntityId',p_institution_entity_id::text,'exactResponsibilityEntityId',p_responsibility_entity_id::text,
      'exactTargetEntityId',p_target_entity_id::text,'exactOperationKey',p_operation_key,'exactWorkItemId',p_work_item_id::text,
      'exactParticipationRoleKey',p_participation_role_key,'canonicalWorkIdentitySource','atlas.work_items.id',
      'includesAllParticipationStates',true,'includesAllMatchingParticipationChains',true,'historicalEventsPreserved',true,'laterEventsDoNotReplaceEarlierEvents',true),
    'truthBoundary',jsonb_build_object('readDoesNotCreateReality',true,'workItemIdIsOperationalCompanyWorkIdentity',true,
      'workItemAcceptedAsUnderlyingReferentIdentity',false,'exactWorkResponsibilityCreatedOrRewritten',false,
      'executionAuthorityCreatedOrExtended',false,'executionParticipationWarrantCreated',false,'taskCreated',false,
      'todayOrClockStateCreated',false,'operationPerformedEstablished',false,'actualOrResultEstablished',false,'underlyingSubjectOutcomeEstablished',false));
end; $$;

create or replace function atlas.execution_participation_coordinates_api_v1(
  p_person_entity_id uuid,p_institution_entity_id uuid,p_responsibility_entity_id uuid,p_target_entity_id uuid,p_operation_key text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, auth, atlas, reality as $$
declare v_captured_at timestamptz := statement_timestamp(); v_self uuid; v_coordinates jsonb;
begin
  v_self:=atlas.reality_sentence_self_person_entity_id_v1();
  if v_self is null or v_self<>p_person_entity_id then raise exception 'Execution Participation coordinate discovery requires the authenticated canonical Person coordinate'; end if;
  if p_operation_key is null or btrim(p_operation_key)='' then raise exception 'operation_key must be nonblank'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('workItemId',c.work_item_id::text,'participationRoleKey',c.participation_role_key)
    order by c.work_item_id,c.participation_role_key),'[]'::jsonb) into v_coordinates
  from (select distinct h.work_item_id,h.participation_role_key from atlas.execution_participation_history h
    where h.person_entity_id=p_person_entity_id and h.institution_entity_id=p_institution_entity_id
      and h.responsibility_entity_id=p_responsibility_entity_id and h.target_entity_id=p_target_entity_id and h.operation_key=p_operation_key) c;
  return jsonb_build_object(
    'contractVersion','execution_participation_coordinates_v1','state','ready','capturedAt',v_captured_at,
    'personEntityId',p_person_entity_id::text,'institutionEntityId',p_institution_entity_id::text,
    'responsibilityEntityId',p_responsibility_entity_id::text,'targetEntityId',p_target_entity_id::text,'operationKey',p_operation_key,
    'coordinates',v_coordinates,'completeness',jsonb_build_object('complete',true,'includesAllKnownWorkItemRoleCoordinates',true),
    'truthBoundary',jsonb_build_object('readDoesNotCreateReality',true,'participationRoleInferred',false,'coordinateChosen',false,
      'executionParticipationWarrantCreated',false,'taskCreated',false,'todayOrClockStateCreated',false));
end; $$;

revoke all on function atlas.institutional_relation_history_self_api_v1(uuid) from public, anon;
revoke all on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text) from public, anon;
revoke all on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text) from public, anon;
revoke all on function atlas.execution_participation_history_api_v1(uuid,uuid,uuid,uuid,text,uuid,text) from public, anon;
revoke all on function atlas.execution_participation_coordinates_api_v1(uuid,uuid,uuid,uuid,text) from public, anon;
grant execute on function atlas.institutional_relation_history_self_api_v1(uuid) to authenticated;
grant execute on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text) to authenticated;
grant execute on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text) to authenticated;
grant execute on function atlas.execution_participation_history_api_v1(uuid,uuid,uuid,uuid,text,uuid,text) to authenticated;
grant execute on function atlas.execution_participation_coordinates_api_v1(uuid,uuid,uuid,uuid,text) to authenticated;

comment on table atlas.responsibility_applicability_governance is 'Explicit canonical responsibility-to-target operation governance. Legacy organization responsibility IDs are not canonicalized here.';
comment on table atlas.execution_authority_history is 'Append-only canonical Execution Authority event history. Carrier IDs are provenance only and never canonical identity.';
comment on table atlas.execution_participation_history is 'Append-only canonical Execution Participation event history, explicitly based on an exact Execution Authority event.';
comment on function atlas.institutional_relation_history_self_api_v1(uuid) is 'Complete Person-bounded institutional relation history for the authenticated canonical Person and one exact Institution.';
comment on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text) is 'Complete responsibility_applies_to history plus every exact-operation governance record; preserves missing and competing governance.';
comment on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text) is 'Complete canonical Execution Authority history for one exact self Person/Institution/Responsibility/Target/Operation coordinate.';
comment on function atlas.execution_participation_history_api_v1(uuid,uuid,uuid,uuid,text,uuid,text) is 'Complete canonical Execution Participation history for one exact Company Work and participation-role coordinate.';
comment on function atlas.execution_participation_coordinates_api_v1(uuid,uuid,uuid,uuid,text) is 'Enumerates only already-governed Work Item + participation-role coordinates; never infers or selects a role.';

commit;
