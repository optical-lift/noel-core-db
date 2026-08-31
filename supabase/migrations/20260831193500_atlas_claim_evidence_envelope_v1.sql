-- Atlas universal Claim / Evidence envelope v1
--
-- Establishes one source-custodied truth membrane that can carry first-party
-- reports, observations, accepted requirements, corrections, and later domain
-- adapters without turning those facts into Tasks, diagnoses, causes, or Clock
-- placements. Only person-scope authenticated write/read APIs are exposed in v1;
-- other scopes remain private until their own authority membrane is added.

begin;

create table atlas.evidence_records (
  id uuid primary key default gen_random_uuid(),
  scope_kind text not null check (btrim(scope_kind) <> ''),
  scope_id uuid not null,
  subject_domain text not null check (btrim(subject_domain) <> ''),
  subject_kind text not null check (btrim(subject_kind) <> ''),
  subject_id text not null check (btrim(subject_id) <> ''),
  evidence_kind text not null check (btrim(evidence_kind) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_key text not null check (btrim(source_key) <> ''),
  actor_user_id uuid references auth.users(id) on delete set null,
  value jsonb not null,
  confidence numeric,
  observed_at timestamptz,
  learned_at timestamptz not null default now(),
  effective_from timestamptz,
  effective_until timestamptz,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (confidence is null or (confidence >= 0 and confidence <= 1)),
  check (effective_until is null or effective_from is null or effective_until >= effective_from),
  unique (scope_kind, scope_id, source_kind, source_key)
);

comment on table atlas.evidence_records is
  'Universal source-custodied evidence records. Evidence preserves what was reported or observed, when Atlas learned it, when it was observed/effective, and provenance. Evidence does not itself create work, causation, diagnosis, or Clock placement.';

create index evidence_records_scope_subject_time_idx
  on atlas.evidence_records(scope_kind, scope_id, subject_domain, subject_kind, subject_id, observed_at desc nulls last, learned_at desc, id);
create index evidence_records_actor_time_idx
  on atlas.evidence_records(actor_user_id, learned_at desc, id)
  where actor_user_id is not null;

create table atlas.claim_records (
  id uuid primary key default gen_random_uuid(),
  scope_kind text not null check (btrim(scope_kind) <> ''),
  scope_id uuid not null,
  subject_domain text not null check (btrim(subject_domain) <> ''),
  subject_kind text not null check (btrim(subject_kind) <> ''),
  subject_id text not null check (btrim(subject_id) <> ''),
  claim_type text not null check (btrim(claim_type) <> ''),
  lifecycle_state text not null check (lifecycle_state in (
    'reported','observed','inferred','proposed','accepted','rejected','superseded','expired','unknown'
  )),
  authority_kind text not null check (btrim(authority_kind) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_key text not null check (btrim(source_key) <> ''),
  value jsonb not null,
  confidence numeric,
  primary_evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  supersedes_claim_id uuid references atlas.claim_records(id) on delete restrict,
  valid_from timestamptz,
  valid_until timestamptz,
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (confidence is null or (confidence >= 0 and confidence <= 1)),
  check (valid_until is null or valid_from is null or valid_until >= valid_from),
  check (supersedes_claim_id is null or supersedes_claim_id <> id),
  unique (scope_kind, scope_id, source_kind, source_key)
);

comment on table atlas.claim_records is
  'Universal claims separated from their supporting evidence. Claim lifecycle, authority, validity time, and supersession are explicit so correction never mutates away original evidence.';

create index claim_records_scope_subject_state_idx
  on atlas.claim_records(scope_kind, scope_id, subject_domain, subject_kind, subject_id, lifecycle_state, recorded_at desc, id);
create index claim_records_supersedes_idx
  on atlas.claim_records(supersedes_claim_id)
  where supersedes_claim_id is not null;

create table atlas.claim_evidence_links (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references atlas.claim_records(id) on delete cascade,
  evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  relation_kind text not null check (relation_kind in ('supports','contradicts','corrects','context')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (claim_id, evidence_id, relation_kind)
);

comment on table atlas.claim_evidence_links is
  'Many-to-many evidence graph for claim support, contradiction, correction, and context. A link records relation only; it does not establish causation.';

create index claim_evidence_links_evidence_idx
  on atlas.claim_evidence_links(evidence_id, claim_id);

create or replace function atlas.guard_claim_evidence_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_evidence_scope_kind text;
  v_evidence_scope_id uuid;
  v_evidence_subject_domain text;
  v_evidence_subject_kind text;
  v_evidence_subject_id text;
  v_old_scope_kind text;
  v_old_scope_id uuid;
  v_old_subject_domain text;
  v_old_subject_kind text;
  v_old_subject_id text;
begin
  select e.scope_kind,e.scope_id,e.subject_domain,e.subject_kind,e.subject_id
  into v_evidence_scope_kind,v_evidence_scope_id,v_evidence_subject_domain,v_evidence_subject_kind,v_evidence_subject_id
  from atlas.evidence_records e
  where e.id=new.primary_evidence_id;

  if v_evidence_scope_kind is null
     or v_evidence_scope_kind is distinct from new.scope_kind
     or v_evidence_scope_id is distinct from new.scope_id
     or v_evidence_subject_domain is distinct from new.subject_domain
     or v_evidence_subject_kind is distinct from new.subject_kind
     or v_evidence_subject_id is distinct from new.subject_id then
    raise exception 'Primary evidence custody and subject must match the claim.' using errcode='23514';
  end if;

  if new.supersedes_claim_id is not null then
    select c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id
    into v_old_scope_kind,v_old_scope_id,v_old_subject_domain,v_old_subject_kind,v_old_subject_id
    from atlas.claim_records c
    where c.id=new.supersedes_claim_id;

    if v_old_scope_kind is null
       or v_old_scope_kind is distinct from new.scope_kind
       or v_old_scope_id is distinct from new.scope_id
       or v_old_subject_domain is distinct from new.subject_domain
       or v_old_subject_kind is distinct from new.subject_kind
       or v_old_subject_id is distinct from new.subject_id then
      raise exception 'Supersession must remain inside the same scope and subject.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_claim_evidence_scope_v1() from public, anon, authenticated;
grant execute on function atlas.guard_claim_evidence_scope_v1() to service_role;

create trigger claim_records_scope_guard_v1
before insert or update on atlas.claim_records
for each row execute function atlas.guard_claim_evidence_scope_v1();

create or replace function atlas.guard_claim_evidence_link_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_claim_scope_kind text;
  v_claim_scope_id uuid;
  v_evidence_scope_kind text;
  v_evidence_scope_id uuid;
begin
  select c.scope_kind,c.scope_id into v_claim_scope_kind,v_claim_scope_id
  from atlas.claim_records c where c.id=new.claim_id;
  select e.scope_kind,e.scope_id into v_evidence_scope_kind,v_evidence_scope_id
  from atlas.evidence_records e where e.id=new.evidence_id;

  if v_claim_scope_kind is null or v_evidence_scope_kind is null
     or v_claim_scope_kind is distinct from v_evidence_scope_kind
     or v_claim_scope_id is distinct from v_evidence_scope_id then
    raise exception 'Claim/evidence links cannot cross custody scopes.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_claim_evidence_link_scope_v1() from public, anon, authenticated;
grant execute on function atlas.guard_claim_evidence_link_scope_v1() to service_role;

create trigger claim_evidence_links_scope_guard_v1
before insert or update on atlas.claim_evidence_links
for each row execute function atlas.guard_claim_evidence_link_scope_v1();

alter table atlas.evidence_records enable row level security;
alter table atlas.claim_records enable row level security;
alter table atlas.claim_evidence_links enable row level security;

create policy evidence_records_person_self_read
on atlas.evidence_records for select to authenticated
using (scope_kind='person' and scope_id=auth.uid());

create policy claim_records_person_self_read
on atlas.claim_records for select to authenticated
using (scope_kind='person' and scope_id=auth.uid());

create policy claim_evidence_links_person_self_read
on atlas.claim_evidence_links for select to authenticated
using (
  exists (
    select 1 from atlas.claim_records c
    where c.id=claim_id and c.scope_kind='person' and c.scope_id=auth.uid()
  )
);

grant select on atlas.evidence_records to authenticated;
grant select on atlas.claim_records to authenticated;
grant select on atlas.claim_evidence_links to authenticated;
grant select,insert,update,delete on atlas.evidence_records to service_role;
grant select,insert,update,delete on atlas.claim_records to service_role;
grant select,insert,update,delete on atlas.claim_evidence_links to service_role;

create or replace function atlas.record_person_claim_evidence_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_subject jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_evidence jsonb;
  v_claim jsonb;
  v_evidence_kind text;
  v_claim_type text;
  v_lifecycle text;
  v_authority text;
  v_confidence numeric;
  v_evidence_confidence numeric;
  v_supersedes_claim_id uuid;
  v_old_state text;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_created_evidence boolean := false;
  v_created_claim boolean := false;
  v_existing_value jsonb;
  v_existing_metadata jsonb;
  v_existing_provenance jsonb;
  v_existing_observed_at timestamptz;
  v_existing_effective_from timestamptz;
  v_existing_effective_until timestamptz;
  v_existing_confidence numeric;
  v_existing_claim_type text;
  v_existing_lifecycle text;
  v_existing_authority text;
  v_existing_primary_evidence_id uuid;
  v_existing_supersedes_claim_id uuid;
  v_existing_valid_from timestamptz;
  v_existing_valid_until timestamptz;
  v_updated integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  v_subject := p_payload->'subject';
  v_evidence := p_payload->'evidence';
  v_claim := p_payload->'claim';
  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;
  if jsonb_typeof(v_subject)<>'object' or jsonb_typeof(v_evidence)<>'object' or jsonb_typeof(v_claim)<>'object' then
    raise exception 'subject, evidence, and claim objects are required.' using errcode='22023';
  end if;

  v_subject_domain := btrim(coalesce(v_subject->>'domain',''));
  v_subject_kind := btrim(coalesce(v_subject->>'kind',''));
  v_subject_id := btrim(coalesce(v_subject->>'id',''));
  if v_subject_domain='' or v_subject_kind='' or v_subject_id='' then
    raise exception 'subject.domain, subject.kind, and subject.id are required.' using errcode='22023';
  end if;

  v_evidence_kind := btrim(coalesce(v_evidence->>'kind',''));
  v_claim_type := btrim(coalesce(v_claim->>'claimType',''));
  v_lifecycle := btrim(coalesce(v_claim->>'lifecycleState',''));
  if v_evidence_kind='' or v_claim_type='' or v_lifecycle='' then
    raise exception 'evidence.kind, claim.claimType, and claim.lifecycleState are required.' using errcode='22023';
  end if;
  if v_lifecycle not in ('reported','observed','proposed','accepted','rejected','unknown') then
    raise exception 'First-party capture cannot author inferred, superseded, or expired claim state.' using errcode='22023';
  end if;
  if not (v_evidence ? 'value') or not (v_claim ? 'value') then
    raise exception 'evidence.value and claim.value are required, including explicit JSON null when that is the evidence.' using errcode='22023';
  end if;

  if v_evidence ? 'confidence' then
    v_evidence_confidence := (v_evidence->>'confidence')::numeric;
    if v_evidence_confidence < 0 or v_evidence_confidence > 1 then raise exception 'evidence confidence must be between 0 and 1.' using errcode='22023'; end if;
  end if;
  if v_claim ? 'confidence' then
    v_confidence := (v_claim->>'confidence')::numeric;
    if v_confidence < 0 or v_confidence > 1 then raise exception 'claim confidence must be between 0 and 1.' using errcode='22023'; end if;
  end if;

  v_supersedes_claim_id := nullif(v_claim->>'supersedesClaimId','')::uuid;
  v_authority := case
    when v_supersedes_claim_id is not null then 'person_correction'
    when v_lifecycle='observed' then 'person_reported_observation'
    when v_lifecycle='accepted' then 'person_acceptance'
    when v_lifecycle='rejected' then 'person_rejection'
    when v_lifecycle='proposed' then 'person_proposal'
    else 'person'
  end;

  if v_supersedes_claim_id is not null then
    select c.lifecycle_state into v_old_state
    from atlas.claim_records c
    where c.id=v_supersedes_claim_id
      and c.scope_kind='person'
      and c.scope_id=v_user_id
      and c.subject_domain=v_subject_domain
      and c.subject_kind=v_subject_kind
      and c.subject_id=v_subject_id;
    if v_old_state is null then
      raise exception 'supersedesClaimId must identify this person own claim for the same subject.' using errcode='42501';
    end if;
  end if;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    evidence_kind,source_kind,source_key,actor_user_id,value,confidence,
    observed_at,effective_from,effective_until,provenance,metadata
  ) values (
    'person',v_user_id,v_subject_domain,v_subject_kind,v_subject_id,
    v_evidence_kind,'person_capture',v_source_key,v_user_id,v_evidence->'value',v_evidence_confidence,
    nullif(v_evidence->>'observedAt','')::timestamptz,
    nullif(v_evidence->>'effectiveFrom','')::timestamptz,
    nullif(v_evidence->>'effectiveUntil','')::timestamptz,
    coalesce(v_evidence->'provenance','{}'::jsonb),
    coalesce(v_evidence->'metadata','{}'::jsonb)
  )
  on conflict (scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_id;

  if v_evidence_id is not null then
    v_created_evidence := true;
  else
    select e.id,e.value,e.metadata,e.provenance,e.observed_at,e.effective_from,e.effective_until,e.confidence
    into v_evidence_id,v_existing_value,v_existing_metadata,v_existing_provenance,v_existing_observed_at,v_existing_effective_from,v_existing_effective_until,v_existing_confidence
    from atlas.evidence_records e
    where e.scope_kind='person' and e.scope_id=v_user_id and e.source_kind='person_capture' and e.source_key=v_source_key
      and e.subject_domain=v_subject_domain and e.subject_kind=v_subject_kind and e.subject_id=v_subject_id
      and e.evidence_kind=v_evidence_kind;

    if v_evidence_id is null
       or v_existing_value is distinct from v_evidence->'value'
       or v_existing_metadata is distinct from coalesce(v_evidence->'metadata','{}'::jsonb)
       or v_existing_provenance is distinct from coalesce(v_evidence->'provenance','{}'::jsonb)
       or v_existing_observed_at is distinct from nullif(v_evidence->>'observedAt','')::timestamptz
       or v_existing_effective_from is distinct from nullif(v_evidence->>'effectiveFrom','')::timestamptz
       or v_existing_effective_until is distinct from nullif(v_evidence->>'effectiveUntil','')::timestamptz
       or v_existing_confidence is distinct from v_evidence_confidence then
      raise exception 'sourceKey retry does not match existing evidence.' using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    claim_type,lifecycle_state,authority_kind,source_kind,source_key,value,confidence,
    primary_evidence_id,supersedes_claim_id,valid_from,valid_until,metadata
  ) values (
    'person',v_user_id,v_subject_domain,v_subject_kind,v_subject_id,
    v_claim_type,v_lifecycle,v_authority,'person_capture',v_source_key,v_claim->'value',v_confidence,
    v_evidence_id,v_supersedes_claim_id,
    nullif(v_claim->>'validFrom','')::timestamptz,
    nullif(v_claim->>'validUntil','')::timestamptz,
    coalesce(v_claim->'metadata','{}'::jsonb)
  )
  on conflict (scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_claim_id;

  if v_claim_id is not null then
    v_created_claim := true;
  else
    select c.id,c.claim_type,c.lifecycle_state,c.authority_kind,c.value,c.metadata,c.confidence,
           c.primary_evidence_id,c.supersedes_claim_id,c.valid_from,c.valid_until
    into v_claim_id,v_existing_claim_type,v_existing_lifecycle,v_existing_authority,v_existing_value,v_existing_metadata,v_existing_confidence,
         v_existing_primary_evidence_id,v_existing_supersedes_claim_id,v_existing_valid_from,v_existing_valid_until
    from atlas.claim_records c
    where c.scope_kind='person' and c.scope_id=v_user_id and c.source_kind='person_capture' and c.source_key=v_source_key
      and c.subject_domain=v_subject_domain and c.subject_kind=v_subject_kind and c.subject_id=v_subject_id;

    if v_claim_id is null
       or v_existing_claim_type is distinct from v_claim_type
       or v_existing_lifecycle is distinct from v_lifecycle
       or v_existing_authority is distinct from v_authority
       or v_existing_value is distinct from v_claim->'value'
       or v_existing_metadata is distinct from coalesce(v_claim->'metadata','{}'::jsonb)
       or v_existing_confidence is distinct from v_confidence
       or v_existing_primary_evidence_id is distinct from v_evidence_id
       or v_existing_supersedes_claim_id is distinct from v_supersedes_claim_id
       or v_existing_valid_from is distinct from nullif(v_claim->>'validFrom','')::timestamptz
       or v_existing_valid_until is distinct from nullif(v_claim->>'validUntil','')::timestamptz then
      raise exception 'sourceKey retry does not match existing claim.' using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
  values (v_claim_id,v_evidence_id,'supports',jsonb_build_object('primary',true))
  on conflict do nothing;

  if v_created_claim and v_supersedes_claim_id is not null then
    update atlas.claim_records c
    set lifecycle_state='superseded',superseded_at=now()
    where c.id=v_supersedes_claim_id
      and c.scope_kind='person'
      and c.scope_id=v_user_id
      and c.lifecycle_state<>'superseded';
    get diagnostics v_updated = row_count;
    if v_updated <> 1 then
      raise exception 'The claim being corrected was already superseded.' using errcode='23505';
    end if;

    insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
    values (v_claim_id,v_evidence_id,'corrects',jsonb_build_object('supersedesClaimId',v_supersedes_claim_id))
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created_claim,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'subject',v_subject,
    'evidenceId',v_evidence_id,
    'claimId',v_claim_id,
    'claimType',v_claim_type,
    'lifecycleState',v_lifecycle,
    'authorityKind',v_authority,
    'supersedesClaimId',v_supersedes_claim_id,
    'truthBoundary',jsonb_build_object(
      'privateByDefault',true,
      'evidenceIsNotTask',true,
      'claimIsNotTask',true,
      'doesNotEstablishCausation',true,
      'doesNotDiagnose',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true,
      'inferenceAuthorityGranted',false,
      'practitionerAccessGranted',false
    )
  );
end;
$$;

comment on function atlas.record_person_claim_evidence_api_v1(jsonb) is
  'Atomic first-party Claim/Evidence writer. Person custody and authority are derived from auth.uid() and lifecycle state; inference, task, causation, diagnosis, sharing, carrier selection, and Clock placement are not granted.';

create or replace function atlas.person_claim_evidence_state_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_evidence jsonb;
  v_claims jsonb;
  v_current_claims jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'evidenceId',e.id,
    'subject',jsonb_build_object('domain',e.subject_domain,'kind',e.subject_kind,'id',e.subject_id),
    'evidenceKind',e.evidence_kind,
    'sourceKind',e.source_kind,
    'sourceKey',e.source_key,
    'actorUserId',e.actor_user_id,
    'value',e.value,
    'confidence',e.confidence,
    'observedAt',e.observed_at,
    'learnedAt',e.learned_at,
    'effectiveFrom',e.effective_from,
    'effectiveUntil',e.effective_until,
    'provenance',e.provenance,
    'metadata',e.metadata
  ) order by e.learned_at,e.id),'[]'::jsonb)
  into v_evidence
  from atlas.evidence_records e
  where e.scope_kind='person' and e.scope_id=v_user_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,
    'subject',jsonb_build_object('domain',c.subject_domain,'kind',c.subject_kind,'id',c.subject_id),
    'claimType',c.claim_type,
    'lifecycleState',c.lifecycle_state,
    'authorityKind',c.authority_kind,
    'sourceKind',c.source_kind,
    'sourceKey',c.source_key,
    'value',c.value,
    'confidence',c.confidence,
    'primaryEvidenceId',c.primary_evidence_id,
    'supersedesClaimId',c.supersedes_claim_id,
    'validFrom',c.valid_from,
    'validUntil',c.valid_until,
    'recordedAt',c.recorded_at,
    'supersededAt',c.superseded_at,
    'metadata',c.metadata
  ) order by c.recorded_at,c.id),'[]'::jsonb)
  into v_claims
  from atlas.claim_records c
  where c.scope_kind='person' and c.scope_id=v_user_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,
    'subject',jsonb_build_object('domain',c.subject_domain,'kind',c.subject_kind,'id',c.subject_id),
    'claimType',c.claim_type,
    'lifecycleState',c.lifecycle_state,
    'authorityKind',c.authority_kind,
    'value',c.value,
    'primaryEvidenceId',c.primary_evidence_id,
    'validFrom',c.valid_from,
    'validUntil',c.valid_until
  ) order by c.recorded_at,c.id),'[]'::jsonb)
  into v_current_claims
  from atlas.claim_records c
  where c.scope_kind='person' and c.scope_id=v_user_id
    and c.lifecycle_state not in ('superseded','expired');

  return jsonb_build_object(
    'ok',true,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'evidenceRecords',v_evidence,
    'claims',v_claims,
    'currentClaims',v_current_claims,
    'truthBoundary',jsonb_build_object(
      'privateByDefault',true,
      'historyPreservedThroughSupersession',true,
      'evidenceDoesNotBecomeTask',true,
      'claimDoesNotBecomeTask',true,
      'clockPlacementAuthority',false,
      'practitionerAccessGranted',false
    )
  );
end;
$$;

comment on function atlas.person_claim_evidence_state_api_v1() is
  'Read membrane for the signed-in person source-custodied evidence and full/current claim history. Superseded claims remain readable; no operational or sharing authority is implied.';

revoke all on function atlas.record_person_claim_evidence_api_v1(jsonb) from public, anon;
revoke all on function atlas.person_claim_evidence_state_api_v1() from public, anon;
grant execute on function atlas.record_person_claim_evidence_api_v1(jsonb) to authenticated, service_role;
grant execute on function atlas.person_claim_evidence_state_api_v1() to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values
  (
    'atlas.record_person_claim_evidence_api_v1(jsonb)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Atomically preserve one first-party evidence record and its explicit claim lifecycle/authority envelope.',
      'authorizationBoundary','SECURITY DEFINER fixes scope and actor to auth.uid(); first-party clients cannot author inferred/superseded/expired state and cannot grant task, Clock, causation, diagnosis, practitioner, or cross-scope authority.',
      'directSignedInEndpoint',true
    ),now(),false
  ),
  (
    'atlas.person_claim_evidence_state_api_v1()',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Read the signed-in person evidence, claim history, and current non-superseded claims.',
      'authorizationBoundary','SECURITY DEFINER fixes reads to auth.uid(); other scopes remain inaccessible until separate authority membranes exist.',
      'directSignedInEndpoint',true
    ),now(),false
  )
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after universal Claim/Evidence registration.';
  end if;
end
$$;

commit;
