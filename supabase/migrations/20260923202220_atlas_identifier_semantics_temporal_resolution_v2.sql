-- Atlas Identifier Semantics + Temporal Resolution v2
-- A matching identifier is evidence, not identity.

create table if not exists atlas.identity_identifier_semantics (
  semantic_key text primary key,
  title text not null,
  cardinality_mode text not null,
  allowed_entity_types text[] not null,
  allows_resolution boolean not null default true,
  allows_auto_resolution boolean not null default false,
  teaches_private_binding boolean not null default false,
  claimant_disclosure_rule text not null default 'public_or_self_verified_only',
  semantic_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint identity_identifier_semantics_key_v2
    check (semantic_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint identity_identifier_semantics_cardinality_v2
    check (cardinality_mode in ('exclusive','shared','role','unknown')),
  constraint identity_identifier_semantics_entity_types_v2
    check (cardinality(allowed_entity_types) >= 1),
  constraint identity_identifier_semantics_disclosure_v2
    check (claimant_disclosure_rule in (
      'never_from_private_signal',
      'public_or_self_verified_only'
    )),
  constraint identity_identifier_semantics_state_v2
    check (semantic_state in ('active','retired')),
  constraint identity_identifier_semantics_metadata_v2
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.identity_identifier_semantics(
  semantic_key,title,cardinality_mode,allowed_entity_types,
  allows_resolution,allows_auto_resolution,teaches_private_binding,
  claimant_disclosure_rule,metadata
)
values
(
  'exclusive_personal','Exclusive personal identifier','exclusive',
  array['person'],true,true,true,'public_or_self_verified_only',
  '{"examples":["person-specific email","person-specific mobile"]}'::jsonb
),
(
  'shared_household','Shared household identifier','shared',
  array['person'],true,true,true,'public_or_self_verified_only',
  '{"examples":["family email","household phone"]}'::jsonb
),
(
  'exclusive_organization','Exclusive organization identifier','exclusive',
  array['business','organization','nonprofit','government'],true,true,true,
  'public_or_self_verified_only',
  '{"examples":["registration number","controlled business domain"]}'::jsonb
),
(
  'organization_contact','Organization-shared contact','shared',
  array['business','organization','nonprofit','government'],true,true,true,
  'public_or_self_verified_only',
  '{"examples":["info inbox","main office phone"]}'::jsonb
),
(
  'role_contact','Organization role contact','role',
  array['business','organization','nonprofit','government'],true,false,true,
  'public_or_self_verified_only',
  '{"examples":["pastor@","manager@","billing@"]}'::jsonb
),
(
  'unknown_shared','Unknown/shared identifier semantics','unknown',
  array['person','business','organization','nonprofit','government','place'],
  true,false,false,'never_from_private_signal',
  '{"principle":"uncertain cardinality must not silently gain automatic or claimant-disclosure authority"}'::jsonb
)
on conflict (semantic_key) do update
set title=excluded.title,
    cardinality_mode=excluded.cardinality_mode,
    allowed_entity_types=excluded.allowed_entity_types,
    allows_resolution=excluded.allows_resolution,
    allows_auto_resolution=excluded.allows_auto_resolution,
    teaches_private_binding=excluded.teaches_private_binding,
    claimant_disclosure_rule=excluded.claimant_disclosure_rule,
    semantic_state='active',
    metadata=atlas.identity_identifier_semantics.metadata || excluded.metadata,
    updated_at=now();

alter table atlas.identity_resolution_signal_policies
  add column if not exists default_evidence_family_key text;

update atlas.identity_resolution_signal_policies
set default_evidence_family_key=case identifier_kind
  when 'website' then 'web_presence'
  when 'domain' then 'web_presence'
  when 'contact_url' then 'web_presence'
  when 'social_url' then 'social_presence'
  when 'government_id' then 'government_identifier'
  when 'registration_number' then 'government_registration'
  else identifier_kind
end
where default_evidence_family_key is null;

alter table atlas.identity_resolution_signal_policies
  alter column default_evidence_family_key set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.identity_resolution_signal_policies'::regclass
      and conname='identity_resolution_signal_policies_family_key_v2'
  ) then
    alter table atlas.identity_resolution_signal_policies
      add constraint identity_resolution_signal_policies_family_key_v2
      check (
        default_evidence_family_key ~
        '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
      );
  end if;
end
$$;

alter table atlas.ledger_source_party_identity_signals
  add column if not exists semantic_key text,
  add column if not exists evidence_family_key text,
  add column if not exists valid_from date,
  add column if not exists valid_until date;

update atlas.ledger_source_party_identity_signals
set semantic_key='unknown_shared'
where semantic_key is null;

update atlas.ledger_source_party_identity_signals s
set evidence_family_key=p.default_evidence_family_key
from atlas.identity_resolution_signal_policies p
where p.identifier_kind=s.identifier_kind
  and s.evidence_family_key is null;

update atlas.ledger_source_party_identity_signals
set valid_from=coalesce(valid_from,observed_at::date)
where valid_from is null;

alter table atlas.ledger_source_party_identity_signals
  alter column semantic_key set not null,
  alter column evidence_family_key set not null,
  alter column valid_from set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.ledger_source_party_identity_signals'::regclass
      and conname='ledger_source_party_identity_signals_semantic_fk_v2'
  ) then
    alter table atlas.ledger_source_party_identity_signals
      add constraint ledger_source_party_identity_signals_semantic_fk_v2
      foreign key (semantic_key)
      references atlas.identity_identifier_semantics(semantic_key)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.ledger_source_party_identity_signals'::regclass
      and conname='ledger_source_party_identity_signals_family_key_v2'
  ) then
    alter table atlas.ledger_source_party_identity_signals
      add constraint ledger_source_party_identity_signals_family_key_v2
      check (
        evidence_family_key ~
        '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
      );
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.ledger_source_party_identity_signals'::regclass
      and conname='ledger_source_party_identity_signals_validity_v2'
  ) then
    alter table atlas.ledger_source_party_identity_signals
      add constraint ledger_source_party_identity_signals_validity_v2
      check (valid_until is null or valid_until >= valid_from);
  end if;
end
$$;

create index if not exists ledger_source_party_identity_signals_validity_idx_v2
  on atlas.ledger_source_party_identity_signals(
    source_party_record_id,signal_state,valid_from,valid_until
  );

create table if not exists local_intel.entity_private_identifier_bindings (
  id uuid primary key default gen_random_uuid(),
  canonical_entity_id uuid not null
    references local_intel.entities(id) on delete cascade,
  identifier_kind text not null,
  semantic_key text not null
    references atlas.identity_identifier_semantics(semantic_key) on delete restrict,
  token_version text not null,
  blind_token text not null,
  binding_state text not null default 'current',
  valid_from date not null,
  valid_until date,
  first_confirmed_at timestamptz not null default now(),
  last_confirmed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_private_identifier_bindings_kind_v2
    check (identifier_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint entity_private_identifier_bindings_version_v2
    check (token_version ~ '^[a-zA-Z0-9._-]+$'),
  constraint entity_private_identifier_bindings_token_v2
    check (length(blind_token) >= 32),
  constraint entity_private_identifier_bindings_state_v2
    check (binding_state in ('current','retired')),
  constraint entity_private_identifier_bindings_validity_v2
    check (valid_until is null or valid_until >= valid_from),
  constraint entity_private_identifier_bindings_metadata_v2
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists entity_private_identifier_bindings_current_uq_v2
  on local_intel.entity_private_identifier_bindings(
    canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,valid_from
  )
  where binding_state='current';

create index if not exists entity_private_identifier_bindings_lookup_idx_v2
  on local_intel.entity_private_identifier_bindings(
    identifier_kind,token_version,blind_token,binding_state,valid_from,valid_until
  );

create table if not exists local_intel.entity_private_identifier_binding_conflicts (
  id uuid primary key default gen_random_uuid(),
  existing_binding_id uuid not null
    references local_intel.entity_private_identifier_bindings(id) on delete restrict,
  asserted_entity_id uuid not null
    references local_intel.entities(id) on delete restrict,
  conflict_state text not null default 'open',
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_private_identifier_binding_conflicts_state_v2
    check (conflict_state in ('open','resolved','dismissed')),
  constraint entity_private_identifier_binding_conflicts_metadata_v2
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists entity_private_identifier_binding_conflicts_open_uq_v2
  on local_intel.entity_private_identifier_binding_conflicts(
    existing_binding_id,asserted_entity_id
  )
  where conflict_state='open';

comment on table local_intel.entity_private_identifier_bindings is
  'Resolver-only temporal opaque identifier bindings. Shared semantics may bind one blind identifier to several canonical entities; exclusive semantics conflict on overlapping assignments rather than silently reassign.';
comment on table local_intel.entity_private_identifier_binding_conflicts is
  'Conflicts where an exclusive private identifier is asserted for a second canonical entity during an overlapping validity interval.';

alter table atlas.identity_identifier_semantics enable row level security;
alter table local_intel.entity_private_identifier_bindings enable row level security;
alter table local_intel.entity_private_identifier_binding_conflicts enable row level security;

revoke all on table atlas.identity_identifier_semantics from public,anon,authenticated;
revoke all on table local_intel.entity_private_identifier_bindings
  from public,anon,authenticated,service_role;
revoke all on table local_intel.entity_private_identifier_binding_conflicts
  from public,anon,authenticated,service_role;

grant select,insert,update,delete on table atlas.identity_identifier_semantics to service_role;

create or replace function atlas.set_identifier_semantics_updated_at_v2()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

create or replace function local_intel.set_private_identifier_binding_updated_at_v2()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists identity_identifier_semantics_updated_at_v2
  on atlas.identity_identifier_semantics;
create trigger identity_identifier_semantics_updated_at_v2
before update on atlas.identity_identifier_semantics
for each row execute function atlas.set_identifier_semantics_updated_at_v2();

drop trigger if exists entity_private_identifier_bindings_updated_at_v2
  on local_intel.entity_private_identifier_bindings;
create trigger entity_private_identifier_bindings_updated_at_v2
before update on local_intel.entity_private_identifier_bindings
for each row execute function local_intel.set_private_identifier_binding_updated_at_v2();

drop trigger if exists entity_private_identifier_binding_conflicts_updated_at_v2
  on local_intel.entity_private_identifier_binding_conflicts;
create trigger entity_private_identifier_binding_conflicts_updated_at_v2
before update on local_intel.entity_private_identifier_binding_conflicts
for each row execute function local_intel.set_private_identifier_binding_updated_at_v2();

-- Conservatively preserve any already-taught v1 tokens without granting
-- them automatic or exclusive semantics.
insert into local_intel.entity_private_identifier_bindings(
  canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,
  binding_state,valid_from,first_confirmed_at,last_confirmed_at,metadata
)
select
  t.canonical_entity_id,
  t.identifier_kind,
  'unknown_shared',
  t.token_version,
  t.blind_token,
  case when t.token_state='current' then 'current' else 'retired' end,
  t.first_confirmed_at::date,
  t.first_confirmed_at,
  t.last_confirmed_at,
  t.metadata || '{"migratedFrom":"entity_private_match_tokens_v1"}'::jsonb
from local_intel.entity_private_match_tokens t
where not exists(
  select 1
  from local_intel.entity_private_identifier_bindings b
  where b.canonical_entity_id=t.canonical_entity_id
    and b.identifier_kind=t.identifier_kind
    and b.token_version=t.token_version
    and b.blind_token=t.blind_token
    and b.valid_from=t.first_confirmed_at::date
);

create or replace function atlas.refresh_private_identifier_bindings_for_source_record_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_resolution atlas.ledger_source_party_resolutions%rowtype;
  v_signal record;
  v_existing local_intel.entity_private_identifier_bindings%rowtype;
  v_semantic atlas.identity_identifier_semantics%rowtype;
begin
  select * into v_resolution
  from atlas.ledger_source_party_resolutions r
  where r.ledger_id=p_ledger_id
    and r.source_party_record_id=p_source_party_record_id
    and r.is_current
  limit 1;

  if v_resolution.id is null then
    return;
  end if;

  for v_signal in
    select
      s.identifier_kind,s.semantic_key,s.token_version,s.blind_token,
      s.valid_from,s.valid_until
    from atlas.ledger_source_party_identity_signals s
    where s.ledger_id=p_ledger_id
      and s.source_party_record_id=p_source_party_record_id
      and s.signal_state='current'
      and s.signal_mode='private_blind_match'
  loop
    select * into v_semantic
    from atlas.identity_identifier_semantics m
    where m.semantic_key=v_signal.semantic_key
      and m.semantic_state='active';

    if v_semantic.semantic_key is null
       or not v_semantic.teaches_private_binding then
      continue;
    end if;

    if not exists(
      select 1
      from local_intel.entities e
      where e.id=v_resolution.canonical_entity_id
        and e.entity_type=any(v_semantic.allowed_entity_types)
    ) then
      continue;
    end if;

    v_existing:=null;

    if v_semantic.cardinality_mode='exclusive' then
      select b.* into v_existing
      from local_intel.entity_private_identifier_bindings b
      where b.identifier_kind=v_signal.identifier_kind
        and b.token_version=v_signal.token_version
        and b.blind_token=v_signal.blind_token
        and b.binding_state='current'
        and b.canonical_entity_id<>v_resolution.canonical_entity_id
        and (b.valid_until is null or b.valid_until >= v_signal.valid_from)
        and (v_signal.valid_until is null or v_signal.valid_until >= b.valid_from)
      order by b.first_confirmed_at
      limit 1;

      if v_existing.id is not null then
        insert into local_intel.entity_private_identifier_binding_conflicts(
          existing_binding_id,asserted_entity_id,metadata
        )
        values(
          v_existing.id,v_resolution.canonical_entity_id,
          jsonb_build_object(
            'basis','exclusive_identifier_overlap',
            'sourcePartyRecordId',p_source_party_record_id
          )
        )
        on conflict (existing_binding_id,asserted_entity_id)
          where conflict_state='open'
        do update set
          last_observed_at=now(),
          updated_at=now();
        continue;
      end if;
    end if;

    insert into local_intel.entity_private_identifier_bindings(
      canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,
      binding_state,valid_from,valid_until,metadata
    )
    values(
      v_resolution.canonical_entity_id,
      v_signal.identifier_kind,
      v_signal.semantic_key,
      v_signal.token_version,
      v_signal.blind_token,
      'current',
      v_signal.valid_from,
      v_signal.valid_until,
      jsonb_build_object(
        'basis','confirmed_source_party_resolution_v2'
      )
    )
    on conflict (
      canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,valid_from
    ) where binding_state='current'
    do update set
      valid_until=excluded.valid_until,
      last_confirmed_at=now(),
      metadata=local_intel.entity_private_identifier_bindings.metadata
        || excluded.metadata,
      updated_at=now();
  end loop;
end
$function$;

revoke all on function atlas.refresh_private_identifier_bindings_for_source_record_v2(
  uuid,uuid
) from public,anon,authenticated,service_role;

create or replace function atlas.project_private_identifier_bindings_after_resolution_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.is_current then
    perform atlas.refresh_private_identifier_bindings_for_source_record_v2(
      new.ledger_id,new.source_party_record_id
    );
  end if;
  return new;
end
$function$;

drop trigger if exists project_private_identifier_bindings_after_resolution_v2
  on atlas.ledger_source_party_resolutions;
create trigger project_private_identifier_bindings_after_resolution_v2
after insert or update of is_current,canonical_entity_id
on atlas.ledger_source_party_resolutions
for each row execute function atlas.project_private_identifier_bindings_after_resolution_v2();

create or replace function atlas.upsert_ledger_source_party_identity_signal_service_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_identifier_kind text,
  p_signal_mode text,
  p_semantic_key text,
  p_value_text text default null,
  p_blind_token text default null,
  p_token_version text default null,
  p_evidence_family_key text default null,
  p_valid_from date default current_date,
  p_valid_until date default null,
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
  v_semantic text:=lower(btrim(coalesce(p_semantic_key,'')));
  v_family text;
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
    from atlas.identity_identifier_semantics s
    where s.semantic_key=v_semantic
      and s.semantic_state='active'
      and s.allows_resolution
  ) then
    raise exception 'Identifier semantic is missing, inactive, or not resolvable.'
      using errcode='22023';
  end if;

  select coalesce(
    nullif(lower(btrim(coalesce(p_evidence_family_key,''))),''),
    p.default_evidence_family_key
  )
  into v_family
  from atlas.identity_resolution_signal_policies p
  where p.identifier_kind=v_kind
    and p.signal_state='active';

  if v_family is null then
    raise exception 'Identifier kind is not enabled for identity resolution.'
      using errcode='22023';
  end if;

  if v_family !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Evidence family key must be normalized.'
      using errcode='22023';
  end if;

  if p_valid_from is null
     or (p_valid_until is not null and p_valid_until<p_valid_from) then
    raise exception 'Invalid signal validity interval.'
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
      normalized_value,semantic_key,evidence_family_key,
      valid_from,valid_until,signal_state,provenance,metadata,observed_at
    )
    values(
      p_ledger_id,p_source_party_record_id,v_kind,v_mode,
      v_normalized,v_semantic,v_family,
      p_valid_from,p_valid_until,'current',
      coalesce(p_provenance,'{}'::jsonb),
      coalesce(p_metadata,'{}'::jsonb),coalesce(p_observed_at,now())
    )
    on conflict (source_party_record_id,identifier_kind,normalized_value)
      where signal_mode='shared_evidence_lookup' and signal_state='current'
    do update set
      semantic_key=excluded.semantic_key,
      evidence_family_key=excluded.evidence_family_key,
      valid_from=excluded.valid_from,
      valid_until=excluded.valid_until,
      provenance=atlas.ledger_source_party_identity_signals.provenance
        || excluded.provenance,
      metadata=atlas.ledger_source_party_identity_signals.metadata
        || excluded.metadata,
      observed_at=excluded.observed_at,
      updated_at=now()
    returning * into v_signal;
  elsif v_mode='private_blind_match' then
    if p_value_text is not null then
      raise exception 'Private blind signal must not pass raw identifier value.'
        using errcode='22023';
    end if;
    if btrim(coalesce(p_blind_token,''))='' or length(p_blind_token)<32 then
      raise exception 'Opaque blind token is required.' using errcode='22023';
    end if;
    if btrim(coalesce(p_token_version,''))=''
       or p_token_version !~ '^[a-zA-Z0-9._-]+$' then
      raise exception 'Valid blind-token version is required.'
        using errcode='22023';
    end if;

    insert into atlas.ledger_source_party_identity_signals(
      ledger_id,source_party_record_id,identifier_kind,signal_mode,
      blind_token,token_version,semantic_key,evidence_family_key,
      valid_from,valid_until,signal_state,provenance,metadata,observed_at
    )
    values(
      p_ledger_id,p_source_party_record_id,v_kind,v_mode,
      p_blind_token,p_token_version,v_semantic,v_family,
      p_valid_from,p_valid_until,'current',
      coalesce(p_provenance,'{}'::jsonb),
      coalesce(p_metadata,'{}'::jsonb),coalesce(p_observed_at,now())
    )
    on conflict (source_party_record_id,identifier_kind,token_version,blind_token)
      where signal_mode='private_blind_match' and signal_state='current'
    do update set
      semantic_key=excluded.semantic_key,
      evidence_family_key=excluded.evidence_family_key,
      valid_from=excluded.valid_from,
      valid_until=excluded.valid_until,
      provenance=atlas.ledger_source_party_identity_signals.provenance
        || excluded.provenance,
      metadata=atlas.ledger_source_party_identity_signals.metadata
        || excluded.metadata,
      observed_at=excluded.observed_at,
      updated_at=now()
    returning * into v_signal;

    perform atlas.refresh_private_identifier_bindings_for_source_record_v2(
      p_ledger_id,p_source_party_record_id
    );
  else
    raise exception 'Invalid identity signal mode.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_identity_signal_v2',
    'identitySignalId',v_signal.id,
    'ledgerId',v_signal.ledger_id,
    'sourcePartyRecordId',v_signal.source_party_record_id,
    'identifierKind',v_signal.identifier_kind,
    'signalMode',v_signal.signal_mode,
    'semanticKey',v_signal.semantic_key,
    'evidenceFamilyKey',v_signal.evidence_family_key,
    'validFrom',v_signal.valid_from,
    'validUntil',v_signal.valid_until,
    'signalState',v_signal.signal_state
  );
end
$function$;

create or replace function atlas.evaluate_ledger_source_party_resolution_service_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_as_of_date date default current_date,
  p_policy_key text default 'default_v1',
  p_resolver_version text default 'identity_resolution_engine_v2'
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
  v_top_auto_eligible boolean;
  v_state text;
  v_candidates jsonb;
begin
  if p_as_of_date is null then
    raise exception 'Resolution as-of date is required.' using errcode='22023';
  end if;

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
      'contractVersion','ledger_source_party_resolution_evaluation_v2',
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

  create temporary table if not exists pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id uuid,
    identity_signal_id uuid,
    identifier_kind text,
    signal_mode text,
    semantic_key text,
    evidence_family_key text,
    weight numeric(5,4),
    allows_auto_resolution boolean
  ) on commit drop;
  truncate pg_temp.atlas_resolution_matches_v2;

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    e.entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.shared_evidence_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.shared_evidence_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_evidence_claims e
    on e.claim_kind=s.identifier_kind
   and e.normalized_value=s.normalized_value
   and e.lifecycle_state='current'
   and e.disclosure_posture<>'suppressed'
   and 'identity_resolution'=any(e.permitted_uses)
   and (e.valid_from is null or e.valid_from<=p_as_of_date)
   and (e.valid_until is null or e.valid_until>=p_as_of_date)
  join local_intel.entities ent
    on ent.id=e.entity_id
   and ent.entity_type=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='shared_evidence_lookup'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date)
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions sup
      where sup.entity_id=e.entity_id
        and sup.suppression_state='active'
        and (sup.effective_until is null or sup.effective_until>now())
        and sup.suppression_scope='all_use'
        and (sup.evidence_claim_id is null or sup.evidence_claim_id=e.id)
    );

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    b.canonical_entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.private_blind_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.private_blind_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_private_identifier_bindings b
    on b.identifier_kind=s.identifier_kind
   and b.token_version=s.token_version
   and b.blind_token=s.blind_token
   and b.binding_state='current'
   and b.valid_from<=p_as_of_date
   and (b.valid_until is null or b.valid_until>=p_as_of_date)
  join local_intel.entities ent
    on ent.id=b.canonical_entity_id
   and ent.entity_type=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='private_blind_match'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date);

  insert into atlas.ledger_source_party_resolution_cases(
    ledger_id,source_party_record_id,policy_key,resolver_version,
    case_state,decision_basis
  )
  values(
    p_ledger_id,p_source_party_record_id,v_policy.policy_key,
    coalesce(nullif(btrim(p_resolver_version),''),'identity_resolution_engine_v2'),
    'new_candidate',
    jsonb_build_object(
      'asOfDate',p_as_of_date,
      'autoResolveThreshold',v_policy.auto_resolve_threshold,
      'reviewThreshold',v_policy.review_threshold,
      'ambiguityMargin',v_policy.ambiguity_margin,
      'scoring','strongest_signal_per_evidence_family_then_probabilistic_union'
    )
  )
  returning * into v_case;

  with family_matches as (
    select
      canonical_entity_id,
      evidence_family_key,
      max(weight) as family_weight,
      bool_or(allows_auto_resolution) as family_auto_eligible,
      jsonb_agg(
        distinct jsonb_build_object(
          'identifierKind',identifier_kind,
          'signalMode',signal_mode,
          'semanticKey',semantic_key
        )
      ) as family_signals
    from pg_temp.atlas_resolution_matches_v2
    group by canonical_entity_id,evidence_family_key
  ),
  scored as (
    select
      canonical_entity_id,
      case
        when bool_or(family_weight>=0.9999) then 1.0000::numeric
        else round(
          (1-exp(sum(ln(greatest(1-family_weight,0.000001)))))::numeric,
          4
        )
      end as score,
      bool_or(family_auto_eligible) as auto_eligible,
      jsonb_agg(
        jsonb_build_object(
          'evidenceFamilyKey',evidence_family_key,
          'familyWeight',family_weight,
          'signals',family_signals
        )
        order by family_weight desc,evidence_family_key
      ) as summary
    from family_matches
    group by canonical_entity_id
  ),
  ranked as (
    select
      canonical_entity_id,
      least(score,1.0000)::numeric(5,4) as score,
      auto_eligible,
      summary,
      row_number() over(order by score desc,canonical_entity_id) as rank_no
    from scored
  )
  insert into atlas.ledger_source_party_resolution_candidates(
    ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,score,match_summary
  )
  select
    p_ledger_id,v_case.id,canonical_entity_id,rank_no,score,
    jsonb_build_object(
      'autoEligible',auto_eligible,
      'families',summary
    )
  from ranked;

  select
    c.score,
    coalesce((c.match_summary->>'autoEligible')::boolean,false)
  into v_top,v_top_auto_eligible
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=1;

  select c.score into v_second
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=2;

  if v_top is null then
    v_state:='new_candidate';
  elsif v_top>=v_policy.auto_resolve_threshold
        and coalesce(v_top_auto_eligible,false)
        and (v_second is null or v_top-v_second>=v_policy.ambiguity_margin) then
    v_state:='auto_resolvable';
  elsif v_top>=v_policy.review_threshold then
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
    'contractVersion','ledger_source_party_resolution_evaluation_v2',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',p_source_party_record_id,
    'asOfDate',p_as_of_date,
    'decisionState',v_case.case_state,
    'topScore',v_case.top_score,
    'secondScore',v_case.second_score,
    'candidates',v_candidates
  );
end
$function$;

revoke all on function atlas.upsert_ledger_source_party_identity_signal_service_v2(
  uuid,uuid,text,text,text,text,text,text,text,date,date,jsonb,jsonb,timestamptz
) from public,anon,authenticated;
grant execute on function atlas.upsert_ledger_source_party_identity_signal_service_v2(
  uuid,uuid,text,text,text,text,text,text,text,date,date,jsonb,jsonb,timestamptz
) to service_role;

revoke all on function atlas.evaluate_ledger_source_party_resolution_service_v2(
  uuid,uuid,date,text,text
) from public,anon,authenticated;
grant execute on function atlas.evaluate_ledger_source_party_resolution_service_v2(
  uuid,uuid,date,text,text
) to service_role;
