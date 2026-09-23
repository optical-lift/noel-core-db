-- Atlas Identity Resolution Engine v1
-- Cross-source identity continuity without cross-Ledger private-data disclosure.

create table if not exists atlas.identity_resolution_policies (
  policy_key text primary key,
  title text not null,
  auto_resolve_threshold numeric(5,4) not null,
  review_threshold numeric(5,4) not null,
  ambiguity_margin numeric(5,4) not null,
  policy_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint identity_resolution_policies_key_v1
    check (policy_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint identity_resolution_policies_thresholds_v1
    check (
      auto_resolve_threshold between 0 and 1
      and review_threshold between 0 and 1
      and ambiguity_margin between 0 and 1
      and auto_resolve_threshold >= review_threshold
    ),
  constraint identity_resolution_policies_state_v1
    check (policy_state in ('active','retired')),
  constraint identity_resolution_policies_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.identity_resolution_policies(
  policy_key,title,auto_resolve_threshold,review_threshold,ambiguity_margin,metadata
)
values(
  'default_v1',
  'Atlas default identity resolution policy v1',
  0.9700,
  0.5500,
  0.0800,
  '{"basis":"identity_resolution_engine_v1"}'::jsonb
)
on conflict (policy_key) do update
set title=excluded.title,
    auto_resolve_threshold=excluded.auto_resolve_threshold,
    review_threshold=excluded.review_threshold,
    ambiguity_margin=excluded.ambiguity_margin,
    policy_state='active',
    metadata=atlas.identity_resolution_policies.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.identity_resolution_signal_policies (
  identifier_kind text primary key,
  shared_evidence_weight numeric(5,4),
  private_blind_weight numeric(5,4),
  signal_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint identity_resolution_signal_policies_kind_v1
    check (identifier_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint identity_resolution_signal_policies_weights_v1
    check (
      (shared_evidence_weight is null or shared_evidence_weight between 0 and 1)
      and
      (private_blind_weight is null or private_blind_weight between 0 and 1)
      and
      (shared_evidence_weight is not null or private_blind_weight is not null)
    ),
  constraint identity_resolution_signal_policies_state_v1
    check (signal_state in ('active','retired')),
  constraint identity_resolution_signal_policies_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.identity_resolution_signal_policies(
  identifier_kind,shared_evidence_weight,private_blind_weight,metadata
)
values
('government_id',0.9999,0.9999,'{"class":"authoritative_identifier"}'::jsonb),
('registration_number',0.9990,0.9990,'{"class":"authoritative_identifier"}'::jsonb),
('website',0.9800,0.9800,'{"class":"strong_identifier"}'::jsonb),
('domain',0.9500,0.9500,'{"class":"strong_identifier"}'::jsonb),
('email',0.9600,0.9600,'{"class":"strong_identifier"}'::jsonb),
('phone',0.9200,0.9200,'{"class":"strong_identifier"}'::jsonb),
('social_url',0.9000,0.9000,'{"class":"supporting_identifier"}'::jsonb),
('contact_url',0.9000,0.9000,'{"class":"supporting_identifier"}'::jsonb),
('address',0.7000,0.7000,'{"class":"supporting_identifier"}'::jsonb),
('name',0.4000,null,'{"class":"weak_identifier"}'::jsonb)
on conflict (identifier_kind) do update
set shared_evidence_weight=excluded.shared_evidence_weight,
    private_blind_weight=excluded.private_blind_weight,
    signal_state='active',
    metadata=atlas.identity_resolution_signal_policies.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.ledger_source_party_identity_signals (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  source_party_record_id uuid not null,
  identifier_kind text not null,
  signal_mode text not null,
  normalized_value text,
  blind_token text,
  token_version text,
  signal_state text not null default 'current',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,id),
  constraint ledger_source_party_identity_signals_record_fk_v1
    foreign key (ledger_id,source_party_record_id)
    references atlas.ledger_source_party_records(ledger_id,id)
    on delete cascade,
  constraint ledger_source_party_identity_signals_kind_v1
    check (identifier_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ledger_source_party_identity_signals_mode_v1
    check (signal_mode in ('shared_evidence_lookup','private_blind_match')),
  constraint ledger_source_party_identity_signals_shape_v1
    check (
      (
        signal_mode='shared_evidence_lookup'
        and normalized_value is not null
        and btrim(normalized_value)<>''
        and blind_token is null
        and token_version is null
      )
      or
      (
        signal_mode='private_blind_match'
        and normalized_value is null
        and blind_token is not null
        and length(blind_token) >= 32
        and token_version is not null
        and token_version ~ '^[a-zA-Z0-9._-]+$'
      )
    ),
  constraint ledger_source_party_identity_signals_state_v1
    check (signal_state in ('current','superseded')),
  constraint ledger_source_party_identity_signals_provenance_v1
    check (jsonb_typeof(provenance)='object'),
  constraint ledger_source_party_identity_signals_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists ledger_source_party_identity_signal_shared_uq_v1
  on atlas.ledger_source_party_identity_signals(
    source_party_record_id,identifier_kind,normalized_value
  )
  where signal_mode='shared_evidence_lookup' and signal_state='current';

create unique index if not exists ledger_source_party_identity_signal_blind_uq_v1
  on atlas.ledger_source_party_identity_signals(
    source_party_record_id,identifier_kind,token_version,blind_token
  )
  where signal_mode='private_blind_match' and signal_state='current';

create index if not exists ledger_source_party_identity_signal_record_idx_v1
  on atlas.ledger_source_party_identity_signals(
    ledger_id,source_party_record_id,signal_state
  );

comment on table atlas.ledger_source_party_identity_signals is
  'Ledger-private identity signals extracted from one source-party representation. Clear normalized values may only match Shared Intelligence evidence; private cross-Ledger continuity uses opaque keyed blind tokens.';

create table if not exists local_intel.entity_private_match_tokens (
  id uuid primary key default gen_random_uuid(),
  canonical_entity_id uuid not null references local_intel.entities(id) on delete cascade,
  identifier_kind text not null,
  token_version text not null,
  blind_token text not null,
  token_state text not null default 'current',
  first_confirmed_at timestamptz not null default now(),
  last_confirmed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_private_match_tokens_kind_v1
    check (identifier_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint entity_private_match_tokens_version_v1
    check (token_version ~ '^[a-zA-Z0-9._-]+$'),
  constraint entity_private_match_tokens_token_v1
    check (length(blind_token) >= 32),
  constraint entity_private_match_tokens_state_v1
    check (token_state in ('current','retired')),
  constraint entity_private_match_tokens_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists entity_private_match_tokens_current_uq_v1
  on local_intel.entity_private_match_tokens(identifier_kind,token_version,blind_token)
  where token_state='current';

create index if not exists entity_private_match_tokens_entity_idx_v1
  on local_intel.entity_private_match_tokens(canonical_entity_id,token_state);

comment on table local_intel.entity_private_match_tokens is
  'Resolver-only opaque HMAC match tokens. They support same-party recognition without storing or exposing the underlying private identifier or contributing Ledger.';

create table if not exists local_intel.entity_private_match_token_conflicts (
  id uuid primary key default gen_random_uuid(),
  private_match_token_id uuid not null
    references local_intel.entity_private_match_tokens(id) on delete restrict,
  existing_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  asserted_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  conflict_state text not null default 'open',
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_private_match_token_conflicts_entities_v1
    check (existing_entity_id <> asserted_entity_id),
  constraint entity_private_match_token_conflicts_state_v1
    check (conflict_state in ('open','resolved','dismissed')),
  constraint entity_private_match_token_conflicts_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists entity_private_match_token_conflicts_open_uq_v1
  on local_intel.entity_private_match_token_conflicts(
    private_match_token_id,existing_entity_id,asserted_entity_id
  )
  where conflict_state='open';

create table if not exists atlas.ledger_source_party_resolution_cases (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  source_party_record_id uuid not null,
  policy_key text not null references atlas.identity_resolution_policies(policy_key) on delete restrict,
  resolver_version text not null,
  case_state text not null,
  top_score numeric(5,4),
  second_score numeric(5,4),
  selected_entity_id uuid references local_intel.entities(id) on delete restrict,
  decision_basis jsonb not null default '{}'::jsonb,
  evaluated_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by_principal_id uuid references atlas.principals(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,id),
  constraint ledger_source_party_resolution_cases_record_fk_v1
    foreign key (ledger_id,source_party_record_id)
    references atlas.ledger_source_party_records(ledger_id,id)
    on delete cascade,
  constraint ledger_source_party_resolution_cases_state_v1
    check (case_state in (
      'already_resolved','auto_resolvable','needs_review','new_candidate',
      'resolved','rejected','superseded'
    )),
  constraint ledger_source_party_resolution_cases_scores_v1
    check (
      (top_score is null or top_score between 0 and 1)
      and (second_score is null or second_score between 0 and 1)
    ),
  constraint ledger_source_party_resolution_cases_basis_v1
    check (jsonb_typeof(decision_basis)='object'),
  constraint ledger_source_party_resolution_cases_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists ledger_source_party_resolution_cases_record_idx_v1
  on atlas.ledger_source_party_resolution_cases(
    ledger_id,source_party_record_id,evaluated_at desc
  );

create table if not exists atlas.ledger_source_party_resolution_candidates (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  resolution_case_id uuid not null,
  canonical_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  candidate_rank integer not null,
  score numeric(5,4) not null,
  match_summary jsonb not null default '[]'::jsonb,
  candidate_state text not null default 'proposed',
  created_at timestamptz not null default now(),
  unique (resolution_case_id,canonical_entity_id),
  unique (resolution_case_id,candidate_rank),
  constraint ledger_source_party_resolution_candidates_case_fk_v1
    foreign key (ledger_id,resolution_case_id)
    references atlas.ledger_source_party_resolution_cases(ledger_id,id)
    on delete cascade,
  constraint ledger_source_party_resolution_candidates_rank_v1
    check (candidate_rank >= 1),
  constraint ledger_source_party_resolution_candidates_score_v1
    check (score between 0 and 1),
  constraint ledger_source_party_resolution_candidates_summary_v1
    check (jsonb_typeof(match_summary)='array'),
  constraint ledger_source_party_resolution_candidates_state_v1
    check (candidate_state in ('proposed','selected','rejected'))
);

comment on table atlas.ledger_source_party_resolution_cases is
  'Ledger-private resolver decision envelope. Ambiguity is preserved as review state rather than silently creating or selecting identity.';
comment on table atlas.ledger_source_party_resolution_candidates is
  'Canonical candidates for one Ledger-private resolution case. Match summaries contain safe categories/weights only, never blind tokens or another Ledger source record.';

alter table atlas.identity_resolution_policies enable row level security;
alter table atlas.identity_resolution_signal_policies enable row level security;
alter table atlas.ledger_source_party_identity_signals enable row level security;
alter table atlas.ledger_source_party_resolution_cases enable row level security;
alter table atlas.ledger_source_party_resolution_candidates enable row level security;
alter table local_intel.entity_private_match_tokens enable row level security;
alter table local_intel.entity_private_match_token_conflicts enable row level security;

revoke all on table atlas.identity_resolution_policies from public,anon,authenticated;
revoke all on table atlas.identity_resolution_signal_policies from public,anon,authenticated;
revoke all on table atlas.ledger_source_party_identity_signals from public,anon,authenticated;
revoke all on table atlas.ledger_source_party_resolution_cases from public,anon,authenticated;
revoke all on table atlas.ledger_source_party_resolution_candidates from public,anon,authenticated;
revoke all on table local_intel.entity_private_match_tokens from public,anon,authenticated,service_role;
revoke all on table local_intel.entity_private_match_token_conflicts from public,anon,authenticated,service_role;

grant select,insert,update,delete on table atlas.identity_resolution_policies to service_role;
grant select,insert,update,delete on table atlas.identity_resolution_signal_policies to service_role;
grant select,insert,update,delete on table atlas.ledger_source_party_identity_signals to service_role;
grant select,insert,update,delete on table atlas.ledger_source_party_resolution_cases to service_role;
grant select,insert,update,delete on table atlas.ledger_source_party_resolution_candidates to service_role;

create or replace function atlas.set_identity_resolution_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

create or replace function local_intel.set_private_match_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists identity_resolution_policies_updated_at_v1 on atlas.identity_resolution_policies;
create trigger identity_resolution_policies_updated_at_v1
before update on atlas.identity_resolution_policies
for each row execute function atlas.set_identity_resolution_updated_at_v1();

drop trigger if exists identity_resolution_signal_policies_updated_at_v1 on atlas.identity_resolution_signal_policies;
create trigger identity_resolution_signal_policies_updated_at_v1
before update on atlas.identity_resolution_signal_policies
for each row execute function atlas.set_identity_resolution_updated_at_v1();

drop trigger if exists ledger_source_party_identity_signals_updated_at_v1 on atlas.ledger_source_party_identity_signals;
create trigger ledger_source_party_identity_signals_updated_at_v1
before update on atlas.ledger_source_party_identity_signals
for each row execute function atlas.set_identity_resolution_updated_at_v1();

drop trigger if exists ledger_source_party_resolution_cases_updated_at_v1 on atlas.ledger_source_party_resolution_cases;
create trigger ledger_source_party_resolution_cases_updated_at_v1
before update on atlas.ledger_source_party_resolution_cases
for each row execute function atlas.set_identity_resolution_updated_at_v1();

drop trigger if exists entity_private_match_tokens_updated_at_v1 on local_intel.entity_private_match_tokens;
create trigger entity_private_match_tokens_updated_at_v1
before update on local_intel.entity_private_match_tokens
for each row execute function local_intel.set_private_match_updated_at_v1();

drop trigger if exists entity_private_match_token_conflicts_updated_at_v1 on local_intel.entity_private_match_token_conflicts;
create trigger entity_private_match_token_conflicts_updated_at_v1
before update on local_intel.entity_private_match_token_conflicts
for each row execute function local_intel.set_private_match_updated_at_v1();

create or replace function atlas.upsert_ledger_source_party_identity_signal_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_identifier_kind text,
  p_signal_mode text,
  p_value_text text default null,
  p_blind_token text default null,
  p_token_version text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_identifier_kind,'')));
  v_mode text:=lower(btrim(coalesce(p_signal_mode,'')));
  v_normalized text;
  v_signal atlas.ledger_source_party_identity_signals%rowtype;
begin
  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.identity_resolution_signal_policies p
    where p.identifier_kind=v_kind and p.signal_state='active'
  ) then
    raise exception 'Identifier kind is not enabled for identity resolution.'
      using errcode='22023';
  end if;

  if v_mode not in ('shared_evidence_lookup','private_blind_match') then
    raise exception 'Invalid identity signal mode.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Signal provenance and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if v_mode='shared_evidence_lookup' then
    if p_blind_token is not null or p_token_version is not null then
      raise exception 'Shared-evidence signal cannot contain blind-token fields.'
        using errcode='22023';
    end if;

    v_normalized:=local_intel.normalize_evidence_value_v1(v_kind,p_value_text);
    if btrim(coalesce(v_normalized,''))='' then
      raise exception 'Identity signal is blank after normalization.'
        using errcode='22023';
    end if;

    insert into atlas.ledger_source_party_identity_signals(
      ledger_id,source_party_record_id,identifier_kind,signal_mode,
      normalized_value,signal_state,provenance,metadata,observed_at
    )
    values(
      p_ledger_id,p_source_party_record_id,v_kind,v_mode,
      v_normalized,'current',coalesce(p_provenance,'{}'::jsonb),
      coalesce(p_metadata,'{}'::jsonb),coalesce(p_observed_at,now())
    )
    on conflict (source_party_record_id,identifier_kind,normalized_value)
      where signal_mode='shared_evidence_lookup' and signal_state='current'
    do update set
      provenance=atlas.ledger_source_party_identity_signals.provenance || excluded.provenance,
      metadata=atlas.ledger_source_party_identity_signals.metadata || excluded.metadata,
      observed_at=excluded.observed_at,
      updated_at=now()
    returning * into v_signal;

  else
    if p_value_text is not null then
      raise exception 'Private blind signal must not pass raw identifier value.'
        using errcode='22023';
    end if;

    if btrim(coalesce(p_blind_token,''))='' or length(p_blind_token)<32 then
      raise exception 'Opaque blind token is required.' using errcode='22023';
    end if;

    if btrim(coalesce(p_token_version,''))=''
       or p_token_version !~ '^[a-zA-Z0-9._-]+$' then
      raise exception 'Valid blind-token version is required.' using errcode='22023';
    end if;

    insert into atlas.ledger_source_party_identity_signals(
      ledger_id,source_party_record_id,identifier_kind,signal_mode,
      blind_token,token_version,signal_state,provenance,metadata,observed_at
    )
    values(
      p_ledger_id,p_source_party_record_id,v_kind,v_mode,
      p_blind_token,p_token_version,'current',
      coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb),
      coalesce(p_observed_at,now())
    )
    on conflict (source_party_record_id,identifier_kind,token_version,blind_token)
      where signal_mode='private_blind_match' and signal_state='current'
    do update set
      provenance=atlas.ledger_source_party_identity_signals.provenance || excluded.provenance,
      metadata=atlas.ledger_source_party_identity_signals.metadata || excluded.metadata,
      observed_at=excluded.observed_at,
      updated_at=now()
    returning * into v_signal;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_identity_signal_v1',
    'identitySignalId',v_signal.id,
    'ledgerId',v_signal.ledger_id,
    'sourcePartyRecordId',v_signal.source_party_record_id,
    'identifierKind',v_signal.identifier_kind,
    'signalMode',v_signal.signal_mode,
    'tokenVersion',v_signal.token_version,
    'signalState',v_signal.signal_state
  );
end
$function$;

create or replace function atlas.evaluate_ledger_source_party_resolution_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_policy_key text default 'default_v1',
  p_resolver_version text default 'identity_resolution_engine_v1'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_policy atlas.identity_resolution_policies%rowtype;
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_existing atlas.ledger_source_party_resolutions%rowtype;
  v_top numeric(5,4);
  v_second numeric(5,4);
  v_state text;
  v_candidates jsonb;
begin
  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  select * into v_existing
  from atlas.ledger_source_party_resolutions x
  where x.ledger_id=p_ledger_id
    and x.source_party_record_id=p_source_party_record_id
    and x.is_current
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','ledger_source_party_resolution_evaluation_v1',
      'decisionState','already_resolved',
      'sourcePartyRecordId',p_source_party_record_id,
      'canonicalEntityId',v_existing.canonical_entity_id,
      'resolutionId',v_existing.id
    );
  end if;

  select * into v_policy
  from atlas.identity_resolution_policies p
  where p.policy_key=p_policy_key
    and p.policy_state='active';

  if v_policy.policy_key is null then
    raise exception 'Identity resolution policy is missing or inactive.'
      using errcode='P0002';
  end if;

  update atlas.ledger_source_party_resolution_cases c
  set case_state='superseded',
      updated_at=now()
  where c.ledger_id=p_ledger_id
    and c.source_party_record_id=p_source_party_record_id
    and c.case_state in ('auto_resolvable','needs_review','new_candidate');

  create temporary table if not exists pg_temp.atlas_resolution_matches_v1(
    canonical_entity_id uuid,
    identity_signal_id uuid,
    identifier_kind text,
    signal_mode text,
    weight numeric(5,4)
  ) on commit drop;
  truncate pg_temp.atlas_resolution_matches_v1;

  insert into pg_temp.atlas_resolution_matches_v1(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,weight
  )
  select distinct
    e.entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    sp.shared_evidence_weight
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.shared_evidence_weight is not null
  join local_intel.entity_evidence_claims e
    on e.claim_kind=s.identifier_kind
   and e.normalized_value=s.normalized_value
   and e.lifecycle_state='current'
   and e.disclosure_posture<>'suppressed'
   and 'identity_resolution'=any(e.permitted_uses)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='shared_evidence_lookup'
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions sup
      where sup.entity_id=e.entity_id
        and sup.suppression_state='active'
        and (sup.effective_until is null or sup.effective_until > now())
        and sup.suppression_scope='all_use'
        and (sup.evidence_claim_id is null or sup.evidence_claim_id=e.id)
    );

  insert into pg_temp.atlas_resolution_matches_v1(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,weight
  )
  select distinct
    t.canonical_entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    sp.private_blind_weight
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.private_blind_weight is not null
  join local_intel.entity_private_match_tokens t
    on t.identifier_kind=s.identifier_kind
   and t.token_version=s.token_version
   and t.blind_token=s.blind_token
   and t.token_state='current'
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='private_blind_match';

  insert into atlas.ledger_source_party_resolution_cases(
    ledger_id,source_party_record_id,policy_key,resolver_version,
    case_state,decision_basis
  )
  values(
    p_ledger_id,p_source_party_record_id,v_policy.policy_key,
    coalesce(nullif(btrim(p_resolver_version),''),'identity_resolution_engine_v1'),
    'new_candidate',
    jsonb_build_object(
      'autoResolveThreshold',v_policy.auto_resolve_threshold,
      'reviewThreshold',v_policy.review_threshold,
      'ambiguityMargin',v_policy.ambiguity_margin
    )
  )
  returning * into v_case;

  with distinct_matches as (
    select distinct
      canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,weight
    from pg_temp.atlas_resolution_matches_v1
  ),
  scored as (
    select
      canonical_entity_id,
      case
        when bool_or(weight >= 0.9999) then 1.0000::numeric
        else round(
          (1 - exp(sum(ln(greatest(1-weight,0.000001)))))::numeric,
          4
        )
      end as score,
      jsonb_agg(
        jsonb_build_object(
          'identifierKind',identifier_kind,
          'signalMode',signal_mode,
          'weight',weight
        )
        order by weight desc,identifier_kind,signal_mode
      ) as summary
    from distinct_matches
    group by canonical_entity_id
  ),
  ranked as (
    select
      canonical_entity_id,
      least(score,1.0000)::numeric(5,4) as score,
      summary,
      row_number() over(order by score desc,canonical_entity_id) as rank_no
    from scored
  )
  insert into atlas.ledger_source_party_resolution_candidates(
    ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,score,match_summary
  )
  select
    p_ledger_id,v_case.id,canonical_entity_id,rank_no,score,summary
  from ranked;

  select score into v_top
  from atlas.ledger_source_party_resolution_candidates
  where resolution_case_id=v_case.id and candidate_rank=1;

  select score into v_second
  from atlas.ledger_source_party_resolution_candidates
  where resolution_case_id=v_case.id and candidate_rank=2;

  if v_top is null then
    v_state:='new_candidate';
  elsif v_top >= v_policy.auto_resolve_threshold
        and (v_second is null or v_top-v_second >= v_policy.ambiguity_margin) then
    v_state:='auto_resolvable';
  elsif v_top >= v_policy.review_threshold then
    v_state:='needs_review';
  else
    v_state:='new_candidate';
  end if;

  update atlas.ledger_source_party_resolution_cases
  set case_state=v_state,
      top_score=v_top,
      second_score=v_second,
      updated_at=now()
  where id=v_case.id
  returning * into v_case;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'canonicalEntityId',c.canonical_entity_id,
      'candidateRank',c.candidate_rank,
      'score',c.score,
      'matchSummary',c.match_summary,
      'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
        'entityId',e.id,
        'name',e.name,
        'entityType',e.entity_type,
        'city',e.city,
        'state',e.state
      ))
    )
    order by c.candidate_rank
  ),'[]'::jsonb)
  into v_candidates
  from atlas.ledger_source_party_resolution_candidates c
  join local_intel.entities e on e.id=c.canonical_entity_id
  where c.resolution_case_id=v_case.id;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_evaluation_v1',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',p_source_party_record_id,
    'decisionState',v_case.case_state,
    'topScore',v_case.top_score,
    'secondScore',v_case.second_score,
    'candidates',v_candidates
  );
end
$function$;

create or replace function atlas.commit_ledger_source_party_resolution_case_service_v1(
  p_ledger_id uuid,
  p_resolution_case_id uuid,
  p_canonical_entity_id uuid,
  p_decision_method text default 'human_confirmed',
  p_established_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_candidate atlas.ledger_source_party_resolution_candidates%rowtype;
  v_method text:=lower(btrim(coalesce(p_decision_method,'')));
  v_resolution jsonb;
  v_signal record;
  v_token local_intel.entity_private_match_tokens%rowtype;
begin
  select * into v_case
  from atlas.ledger_source_party_resolution_cases c
  where c.id=p_resolution_case_id
    and c.ledger_id=p_ledger_id;

  if v_case.id is null then
    raise exception 'Resolution case is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if v_case.case_state not in ('auto_resolvable','needs_review') then
    raise exception 'Resolution case is not selectable in its current state.'
      using errcode='22023';
  end if;

  select * into v_candidate
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.canonical_entity_id=p_canonical_entity_id;

  if v_candidate.id is null then
    raise exception 'Selected canonical entity is not a candidate for this case.'
      using errcode='22023';
  end if;

  if v_method='automatic' then
    if v_case.case_state<>'auto_resolvable' or v_candidate.candidate_rank<>1 then
      raise exception 'Automatic commit requires the top auto-resolvable candidate.'
        using errcode='22023';
    end if;
  elsif v_method<>'human_confirmed' then
    raise exception 'Decision method must be automatic or human_confirmed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Commit metadata must be a JSON object.' using errcode='22023';
  end if;

  v_resolution:=atlas.resolve_ledger_source_party_record_service_v1(
    p_ledger_id,
    v_case.source_party_record_id,
    p_canonical_entity_id,
    v_method,
    v_candidate.score,
    v_case.resolver_version,
    v_case.decision_basis || jsonb_build_object(
      'resolutionCaseId',v_case.id,
      'candidateRank',v_candidate.candidate_rank,
      'matchSummary',v_candidate.match_summary
    ),
    p_established_by_principal_id,
    coalesce(p_metadata,'{}'::jsonb)
  );

  update atlas.ledger_source_party_resolution_candidates
  set candidate_state=case
    when canonical_entity_id=p_canonical_entity_id then 'selected'
    else 'rejected'
  end
  where resolution_case_id=v_case.id;

  update atlas.ledger_source_party_resolution_cases
  set case_state='resolved',
      selected_entity_id=p_canonical_entity_id,
      decided_at=now(),
      decided_by_principal_id=p_established_by_principal_id,
      metadata=metadata || coalesce(p_metadata,'{}'::jsonb),
      updated_at=now()
  where id=v_case.id;

  for v_signal in
    select s.identifier_kind,s.token_version,s.blind_token
    from atlas.ledger_source_party_identity_signals s
    where s.ledger_id=p_ledger_id
      and s.source_party_record_id=v_case.source_party_record_id
      and s.signal_state='current'
      and s.signal_mode='private_blind_match'
  loop
    select * into v_token
    from local_intel.entity_private_match_tokens t
    where t.identifier_kind=v_signal.identifier_kind
      and t.token_version=v_signal.token_version
      and t.blind_token=v_signal.blind_token
      and t.token_state='current'
    limit 1;

    if v_token.id is null then
      insert into local_intel.entity_private_match_tokens(
        canonical_entity_id,identifier_kind,token_version,blind_token,
        token_state,metadata
      )
      values(
        p_canonical_entity_id,v_signal.identifier_kind,v_signal.token_version,
        v_signal.blind_token,'current',
        jsonb_build_object('basis','confirmed_source_party_resolution')
      );
    elsif v_token.canonical_entity_id=p_canonical_entity_id then
      update local_intel.entity_private_match_tokens
      set last_confirmed_at=now(),
          updated_at=now()
      where id=v_token.id;
    else
      insert into local_intel.entity_private_match_token_conflicts(
        private_match_token_id,existing_entity_id,asserted_entity_id,metadata
      )
      values(
        v_token.id,v_token.canonical_entity_id,p_canonical_entity_id,
        jsonb_build_object('basis','confirmed_resolution_disagreement')
      )
      on conflict (
        private_match_token_id,existing_entity_id,asserted_entity_id
      ) where conflict_state='open'
      do update set
        last_observed_at=now(),
        updated_at=now();
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_commit_v1',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',v_case.source_party_record_id,
    'canonicalEntityId',p_canonical_entity_id,
    'decisionMethod',v_method,
    'resolution',v_resolution
  );
end
$function$;

create or replace function atlas.ledger_source_party_resolution_case_detail_service_v1(
  p_ledger_id uuid,
  p_resolution_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_case_detail_v1',
    'resolutionCaseId',c.id,
    'sourcePartyRecordId',c.source_party_record_id,
    'caseState',c.case_state,
    'policyKey',c.policy_key,
    'resolverVersion',c.resolver_version,
    'topScore',c.top_score,
    'secondScore',c.second_score,
    'selectedEntityId',c.selected_entity_id,
    'evaluatedAt',c.evaluated_at,
    'decidedAt',c.decided_at,
    'candidates',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'canonicalEntityId',x.canonical_entity_id,
          'candidateRank',x.candidate_rank,
          'score',x.score,
          'candidateState',x.candidate_state,
          'matchSummary',x.match_summary,
          'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
            'entityId',e.id,
            'name',e.name,
            'entityType',e.entity_type,
            'city',e.city,
            'state',e.state
          ))
        )
        order by x.candidate_rank
      )
      from atlas.ledger_source_party_resolution_candidates x
      join local_intel.entities e on e.id=x.canonical_entity_id
      where x.resolution_case_id=c.id
        and x.ledger_id=c.ledger_id
    ),'[]'::jsonb)
  )
  from atlas.ledger_source_party_resolution_cases c
  where c.id=p_resolution_case_id
    and c.ledger_id=p_ledger_id;
$function$;

revoke all on function atlas.upsert_ledger_source_party_identity_signal_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,timestamptz
) from public,anon,authenticated;
grant execute on function atlas.upsert_ledger_source_party_identity_signal_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,timestamptz
) to service_role;

revoke all on function atlas.evaluate_ledger_source_party_resolution_service_v1(
  uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function atlas.evaluate_ledger_source_party_resolution_service_v1(
  uuid,uuid,text,text
) to service_role;

revoke all on function atlas.commit_ledger_source_party_resolution_case_service_v1(
  uuid,uuid,uuid,text,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.commit_ledger_source_party_resolution_case_service_v1(
  uuid,uuid,uuid,text,uuid,jsonb
) to service_role;

revoke all on function atlas.ledger_source_party_resolution_case_detail_service_v1(
  uuid,uuid
) from public,anon,authenticated;
grant execute on function atlas.ledger_source_party_resolution_case_detail_service_v1(
  uuid,uuid
) to service_role;
