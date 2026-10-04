-- Atlas Evidence + Disclosure Membrane v1
-- Wide evidence intake, narrow disclosure/action rights.

create table if not exists local_intel.evidence_source_classes (
  source_class_key text primary key,
  title text not null,
  default_evidence_strength text not null,
  maximum_disclosure_posture text not null,
  allowed_uses text[] not null default '{}'::text[],
  default_contact_intents text[] not null default '{}'::text[],
  class_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evidence_source_classes_key_nonblank_v1
    check (btrim(source_class_key) <> ''),
  constraint evidence_source_classes_max_posture_v1
    check (maximum_disclosure_posture in (
      'public_contactable','public_directory','resolution_only','restricted','suppressed'
    )),
  constraint evidence_source_classes_state_v1
    check (class_state in ('active','retired')),
  constraint evidence_source_classes_metadata_object_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table local_intel.evidence_source_classes is
  'Conservative source-class policy ceiling for Shared Intelligence evidence ingestion. Source accessibility does not itself authorize directory display or outreach.';

insert into local_intel.evidence_source_classes(
  source_class_key,title,default_evidence_strength,maximum_disclosure_posture,
  allowed_uses,default_contact_intents,metadata
)
values
(
  'owner_verified_public',
  'Owner-verified public profile',
  'owner_verified',
  'public_contactable',
  array['identity_resolution','directory_display','outreach'],
  array['general'],
  '{"principle":"subject/controller intentionally publishes the fact"}'::jsonb
),
(
  'self_published_business',
  'Self-published business source',
  'official_source',
  'public_contactable',
  array['identity_resolution','directory_display','outreach'],
  array['general'],
  '{"examples":["official business website","business social profile","official contact page"]}'::jsonb
),
(
  'self_published_professional',
  'Self-published professional source',
  'official_source',
  'public_contactable',
  array['identity_resolution','directory_display','outreach'],
  array['general'],
  '{"principle":"professional contact intentionally published by the subject or employing organization"}'::jsonb
),
(
  'government_registry',
  'Government registration source',
  'government_authoritative',
  'public_directory',
  array['identity_resolution','directory_display'],
  '{}'::text[],
  '{"principle":"authoritative registration facts are not automatically marketing channels"}'::jsonb
),
(
  'public_record_resolution',
  'Public record used for identity resolution',
  'government_authoritative',
  'resolution_only',
  array['identity_resolution'],
  '{}'::text[],
  '{"examples":["parcel record","permit record","ownership filing"],"principle":"obtainable does not mean contactable"}'::jsonb
),
(
  'third_party_directory',
  'Third-party public directory',
  'third_party_observed',
  'public_directory',
  array['identity_resolution','directory_display'],
  '{}'::text[],
  '{"principle":"directory publication alone does not establish outreach intent"}'::jsonb
),
(
  'legacy_unclassified',
  'Legacy unclassified evidence',
  'unclassified',
  'resolution_only',
  array['identity_resolution'],
  '{}'::text[],
  '{"principle":"legacy data is not promoted to contactable without explicit provenance"}'::jsonb
)
on conflict (source_class_key) do update
set title=excluded.title,
    default_evidence_strength=excluded.default_evidence_strength,
    maximum_disclosure_posture=excluded.maximum_disclosure_posture,
    allowed_uses=excluded.allowed_uses,
    default_contact_intents=excluded.default_contact_intents,
    class_state='active',
    metadata=local_intel.evidence_source_classes.metadata || excluded.metadata,
    updated_at=now();

alter table local_intel.sources
  add column if not exists source_class_key text;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='local_intel.sources'::regclass
      and conname='sources_source_class_key_fkey_v1'
  ) then
    alter table local_intel.sources
      add constraint sources_source_class_key_fkey_v1
      foreign key (source_class_key)
      references local_intel.evidence_source_classes(source_class_key)
      on delete restrict;
  end if;
end
$$;

create index if not exists sources_source_class_key_idx_v1
  on local_intel.sources(source_class_key)
  where source_class_key is not null;

comment on column local_intel.sources.source_class_key is
  'Optional Evidence + Disclosure source classification. Existing unclassified sources are not implicitly contactable.';

create or replace function local_intel.disclosure_posture_rank_v1(p_posture text)
returns integer
language sql
immutable
strict
set search_path to 'pg_catalog'
as $function$
  select case p_posture
    when 'suppressed' then 0
    when 'restricted' then 1
    when 'resolution_only' then 2
    when 'public_directory' then 3
    when 'public_contactable' then 4
    else -1
  end;
$function$;

create or replace function local_intel.normalize_evidence_value_v1(
  p_claim_kind text,
  p_value text
)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select case lower(btrim(coalesce(p_claim_kind,'')))
    when 'email' then lower(btrim(coalesce(p_value,'')))
    when 'phone' then regexp_replace(coalesce(p_value,''),'[^0-9]+','','g')
    when 'website' then lower(regexp_replace(btrim(coalesce(p_value,'')),'/+$','','g'))
    when 'contact_url' then lower(regexp_replace(btrim(coalesce(p_value,'')),'/+$','','g'))
    when 'social_url' then lower(regexp_replace(btrim(coalesce(p_value,'')),'/+$','','g'))
    else lower(regexp_replace(btrim(coalesce(p_value,'')),'[[:space:]]+',' ','g'))
  end;
$function$;

create table if not exists local_intel.entity_evidence_claims (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references local_intel.entities(id) on delete cascade,
  claim_kind text not null,
  value_text text not null,
  normalized_value text not null,
  source_id uuid references local_intel.sources(id) on delete set null,
  source_class_key text not null
    references local_intel.evidence_source_classes(source_class_key) on delete restrict,
  evidence_strength text not null,
  disclosure_posture text not null,
  permitted_uses text[] not null default '{}'::text[],
  contact_channel text,
  contact_intents text[] not null default '{}'::text[],
  lifecycle_state text not null default 'current',
  observed_at timestamptz not null default now(),
  valid_from date,
  valid_until date,
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_evidence_claims_kind_key_v1
    check (claim_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint entity_evidence_claims_value_nonblank_v1
    check (btrim(value_text) <> '' and btrim(normalized_value) <> ''),
  constraint entity_evidence_claims_posture_v1
    check (disclosure_posture in (
      'public_contactable','public_directory','resolution_only','restricted','suppressed'
    )),
  constraint entity_evidence_claims_channel_key_v1
    check (
      contact_channel is null
      or contact_channel ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
    ),
  constraint entity_evidence_claims_lifecycle_v1
    check (lifecycle_state in ('current','stale','superseded','invalid')),
  constraint entity_evidence_claims_valid_dates_v1
    check (valid_until is null or valid_from is null or valid_until >= valid_from),
  constraint entity_evidence_claims_metadata_object_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table local_intel.entity_evidence_claims is
  'Claim-level Shared Intelligence evidence beneath canonical entity identity. Disclosure posture and permitted uses govern whether the claim may resolve identity, display in a directory, or participate in outreach. Organization-private contact data does not belong here.';

create unique index if not exists entity_evidence_claims_sourced_uq_v1
  on local_intel.entity_evidence_claims(entity_id,claim_kind,normalized_value,source_id)
  where source_id is not null;

create unique index if not exists entity_evidence_claims_unsourced_uq_v1
  on local_intel.entity_evidence_claims(entity_id,claim_kind,normalized_value,source_class_key)
  where source_id is null;

create index if not exists entity_evidence_claims_resolution_idx_v1
  on local_intel.entity_evidence_claims(claim_kind,normalized_value,lifecycle_state);

create index if not exists entity_evidence_claims_entity_idx_v1
  on local_intel.entity_evidence_claims(entity_id,lifecycle_state,disclosure_posture);

create table if not exists local_intel.entity_contact_suppressions (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references local_intel.entities(id) on delete cascade,
  evidence_claim_id uuid references local_intel.entity_evidence_claims(id) on delete cascade,
  suppression_scope text not null,
  suppression_state text not null default 'active',
  reason_key text not null,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  authority_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_contact_suppressions_scope_v1
    check (suppression_scope in ('outreach','directory_display','all_use')),
  constraint entity_contact_suppressions_state_v1
    check (suppression_state in ('active','lifted')),
  constraint entity_contact_suppressions_reason_key_v1
    check (reason_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint entity_contact_suppressions_effective_dates_v1
    check (effective_until is null or effective_until >= effective_from),
  constraint entity_contact_suppressions_authority_object_v1
    check (jsonb_typeof(authority_basis)='object'),
  constraint entity_contact_suppressions_metadata_object_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table local_intel.entity_contact_suppressions is
  'System-level suppression membrane for shared directory/outreach use. This is distinct from any Organization-private do-not-contact preference.';

create unique index if not exists entity_contact_suppressions_active_uq_v1
  on local_intel.entity_contact_suppressions(
    entity_id,
    coalesce(evidence_claim_id,'00000000-0000-0000-0000-000000000000'::uuid),
    suppression_scope
  )
  where suppression_state='active';

create index if not exists entity_contact_suppressions_lookup_idx_v1
  on local_intel.entity_contact_suppressions(entity_id,suppression_state,suppression_scope);

alter table local_intel.evidence_source_classes enable row level security;
alter table local_intel.entity_evidence_claims enable row level security;
alter table local_intel.entity_contact_suppressions enable row level security;

revoke all on table local_intel.evidence_source_classes from public,anon,authenticated;
revoke all on table local_intel.entity_evidence_claims from public,anon,authenticated;
revoke all on table local_intel.entity_contact_suppressions from public,anon,authenticated;

grant select,insert,update,delete on table local_intel.evidence_source_classes to service_role;
grant select,insert,update,delete on table local_intel.entity_evidence_claims to service_role;
grant select,insert,update,delete on table local_intel.entity_contact_suppressions to service_role;

create or replace function local_intel.set_evidence_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists evidence_source_classes_updated_at_v1
  on local_intel.evidence_source_classes;
create trigger evidence_source_classes_updated_at_v1
before update on local_intel.evidence_source_classes
for each row execute function local_intel.set_evidence_updated_at_v1();

drop trigger if exists entity_evidence_claims_updated_at_v1
  on local_intel.entity_evidence_claims;
create trigger entity_evidence_claims_updated_at_v1
before update on local_intel.entity_evidence_claims
for each row execute function local_intel.set_evidence_updated_at_v1();

drop trigger if exists entity_contact_suppressions_updated_at_v1
  on local_intel.entity_contact_suppressions;
create trigger entity_contact_suppressions_updated_at_v1
before update on local_intel.entity_contact_suppressions
for each row execute function local_intel.set_evidence_updated_at_v1();

create or replace function local_intel.record_entity_evidence_claim_service_v1(
  p_entity_id uuid,
  p_claim_kind text,
  p_value_text text,
  p_source_class_key text,
  p_disclosure_posture text,
  p_permitted_uses text[],
  p_source_id uuid default null,
  p_evidence_strength text default null,
  p_contact_channel text default null,
  p_contact_intents text[] default '{}'::text[],
  p_observed_at timestamptz default now(),
  p_valid_from date default null,
  p_valid_until date default null,
  p_last_verified_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_class local_intel.evidence_source_classes%rowtype;
  v_claim local_intel.entity_evidence_claims%rowtype;
  v_kind text;
  v_normalized text;
  v_uses text[];
  v_intents text[];
  v_strength text;
  v_channel text;
begin
  if not exists(select 1 from local_intel.entities e where e.id=p_entity_id) then
    raise exception 'Canonical entity not found.' using errcode='P0002';
  end if;

  select * into v_class
  from local_intel.evidence_source_classes s
  where s.source_class_key=p_source_class_key
    and s.class_state='active';

  if v_class.source_class_key is null then
    raise exception 'Evidence source class is missing or inactive.' using errcode='P0002';
  end if;

  if local_intel.disclosure_posture_rank_v1(p_disclosure_posture) < 0
     or local_intel.disclosure_posture_rank_v1(p_disclosure_posture)
        > local_intel.disclosure_posture_rank_v1(v_class.maximum_disclosure_posture) then
    raise exception 'Requested disclosure posture exceeds source-class policy ceiling.'
      using errcode='22023';
  end if;

  if p_source_id is not null and not exists(
    select 1
    from local_intel.sources s
    where s.id=p_source_id
      and (s.source_class_key is null or s.source_class_key=p_source_class_key)
  ) then
    raise exception 'Source is missing or has an incompatible source classification.'
      using errcode='22023';
  end if;

  v_kind:=lower(btrim(coalesce(p_claim_kind,'')));
  if v_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Claim kind must be a normalized key.' using errcode='22023';
  end if;

  v_normalized:=local_intel.normalize_evidence_value_v1(v_kind,p_value_text);
  if btrim(coalesce(v_normalized,''))='' then
    raise exception 'Evidence claim value is blank after normalization.' using errcode='22023';
  end if;

  select coalesce(array_agg(x.k order by x.k),'{}'::text[])
  into v_uses
  from (
    select distinct lower(btrim(v)) as k
    from unnest(coalesce(p_permitted_uses,'{}'::text[])) v
    where lower(btrim(v)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) x;

  if not (v_uses <@ v_class.allowed_uses) then
    raise exception 'Requested permitted uses exceed source-class allowed uses.'
      using errcode='22023';
  end if;

  select coalesce(array_agg(x.k order by x.k),'{}'::text[])
  into v_intents
  from (
    select distinct lower(btrim(v)) as k
    from unnest(coalesce(p_contact_intents,'{}'::text[])) v
    where lower(btrim(v)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) x;

  v_channel:=nullif(lower(btrim(coalesce(p_contact_channel,''))),'');
  if v_channel is not null
     and v_channel !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Contact channel must be a normalized key.' using errcode='22023';
  end if;

  if p_disclosure_posture='suppressed' and cardinality(v_uses)>0 then
    raise exception 'Suppressed evidence cannot have permitted uses.' using errcode='22023';
  end if;

  if p_disclosure_posture='resolution_only'
     and not (v_uses <@ array['identity_resolution']::text[]) then
    raise exception 'Resolution-only evidence may only permit identity resolution.'
      using errcode='22023';
  end if;

  if p_disclosure_posture='public_directory'
     and 'outreach'=any(v_uses) then
    raise exception 'Public-directory evidence is not an outreach channel.'
      using errcode='22023';
  end if;

  if 'outreach'=any(v_uses)
     and (p_disclosure_posture<>'public_contactable'
          or v_channel is null
          or cardinality(v_intents)=0) then
    raise exception 'Outreach evidence must be public_contactable with channel and contact intent.'
      using errcode='22023';
  end if;

  if cardinality(v_intents)>0 and v_channel is null then
    raise exception 'Contact intents require a contact channel.' using errcode='22023';
  end if;

  if p_valid_until is not null
     and p_valid_from is not null
     and p_valid_until < p_valid_from then
    raise exception 'Evidence validity end precedes start.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Evidence metadata must be a JSON object.' using errcode='22023';
  end if;

  v_strength:=coalesce(
    nullif(lower(btrim(coalesce(p_evidence_strength,''))),''),
    v_class.default_evidence_strength
  );

  if p_source_id is not null then
    select * into v_claim
    from local_intel.entity_evidence_claims c
    where c.entity_id=p_entity_id
      and c.claim_kind=v_kind
      and c.normalized_value=v_normalized
      and c.source_id=p_source_id
    limit 1;
  else
    select * into v_claim
    from local_intel.entity_evidence_claims c
    where c.entity_id=p_entity_id
      and c.claim_kind=v_kind
      and c.normalized_value=v_normalized
      and c.source_id is null
      and c.source_class_key=p_source_class_key
    limit 1;
  end if;

  if v_claim.id is null then
    insert into local_intel.entity_evidence_claims(
      entity_id,claim_kind,value_text,normalized_value,source_id,source_class_key,
      evidence_strength,disclosure_posture,permitted_uses,contact_channel,
      contact_intents,lifecycle_state,observed_at,valid_from,valid_until,
      last_verified_at,metadata
    )
    values(
      p_entity_id,v_kind,btrim(p_value_text),v_normalized,p_source_id,p_source_class_key,
      v_strength,p_disclosure_posture,v_uses,v_channel,v_intents,'current',
      coalesce(p_observed_at,now()),p_valid_from,p_valid_until,p_last_verified_at,
      coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_claim;
  else
    update local_intel.entity_evidence_claims c
    set value_text=btrim(p_value_text),
        source_class_key=p_source_class_key,
        evidence_strength=v_strength,
        disclosure_posture=p_disclosure_posture,
        permitted_uses=v_uses,
        contact_channel=v_channel,
        contact_intents=v_intents,
        lifecycle_state='current',
        observed_at=coalesce(p_observed_at,c.observed_at),
        valid_from=p_valid_from,
        valid_until=p_valid_until,
        last_verified_at=coalesce(p_last_verified_at,c.last_verified_at),
        metadata=c.metadata || coalesce(p_metadata,'{}'::jsonb),
        updated_at=now()
    where c.id=v_claim.id
    returning * into v_claim;
  end if;

  return jsonb_build_object(
    'contractVersion','entity_evidence_claim_v1',
    'evidenceClaimId',v_claim.id,
    'entityId',v_claim.entity_id,
    'claimKind',v_claim.claim_kind,
    'sourceClassKey',v_claim.source_class_key,
    'evidenceStrength',v_claim.evidence_strength,
    'disclosurePosture',v_claim.disclosure_posture,
    'permittedUses',to_jsonb(v_claim.permitted_uses),
    'contactChannel',v_claim.contact_channel,
    'contactIntents',to_jsonb(v_claim.contact_intents),
    'lifecycleState',v_claim.lifecycle_state
  );
end
$function$;

create or replace function local_intel.set_entity_contact_suppression_service_v1(
  p_entity_id uuid,
  p_suppression_scope text,
  p_reason_key text,
  p_evidence_claim_id uuid default null,
  p_effective_until timestamptz default null,
  p_authority_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_suppression local_intel.entity_contact_suppressions%rowtype;
  v_scope text:=lower(btrim(coalesce(p_suppression_scope,'')));
  v_reason text:=lower(btrim(coalesce(p_reason_key,'')));
begin
  if not exists(select 1 from local_intel.entities e where e.id=p_entity_id) then
    raise exception 'Canonical entity not found.' using errcode='P0002';
  end if;

  if v_scope not in ('outreach','directory_display','all_use') then
    raise exception 'Invalid suppression scope.' using errcode='22023';
  end if;

  if v_reason !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Suppression reason must be a normalized key.' using errcode='22023';
  end if;

  if p_evidence_claim_id is not null and not exists(
    select 1 from local_intel.entity_evidence_claims c
    where c.id=p_evidence_claim_id and c.entity_id=p_entity_id
  ) then
    raise exception 'Evidence claim does not belong to canonical entity.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_authority_basis,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Suppression authority and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  select * into v_suppression
  from local_intel.entity_contact_suppressions s
  where s.entity_id=p_entity_id
    and s.evidence_claim_id is not distinct from p_evidence_claim_id
    and s.suppression_scope=v_scope
    and s.suppression_state='active'
  limit 1;

  if v_suppression.id is null then
    insert into local_intel.entity_contact_suppressions(
      entity_id,evidence_claim_id,suppression_scope,suppression_state,
      reason_key,effective_until,authority_basis,metadata
    )
    values(
      p_entity_id,p_evidence_claim_id,v_scope,'active',
      v_reason,p_effective_until,coalesce(p_authority_basis,'{}'::jsonb),
      coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_suppression;
  else
    update local_intel.entity_contact_suppressions s
    set reason_key=v_reason,
        effective_until=p_effective_until,
        authority_basis=coalesce(p_authority_basis,'{}'::jsonb),
        metadata=s.metadata || coalesce(p_metadata,'{}'::jsonb),
        updated_at=now()
    where s.id=v_suppression.id
    returning * into v_suppression;
  end if;

  return jsonb_build_object(
    'contractVersion','entity_contact_suppression_v1',
    'suppressionId',v_suppression.id,
    'entityId',v_suppression.entity_id,
    'evidenceClaimId',v_suppression.evidence_claim_id,
    'suppressionScope',v_suppression.suppression_scope,
    'suppressionState',v_suppression.suppression_state,
    'reasonKey',v_suppression.reason_key
  );
end
$function$;

create or replace function local_intel.entity_directory_evidence_service_v1(
  p_entity_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','entity_directory_evidence_v1',
    'entityId',p_entity_id,
    'claims',coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'evidenceClaimId',c.id,
        'claimKind',c.claim_kind,
        'value',c.value_text,
        'sourceClassKey',c.source_class_key,
        'evidenceStrength',c.evidence_strength,
        'disclosurePosture',c.disclosure_posture,
        'contactChannel',c.contact_channel,
        'contactIntents',to_jsonb(c.contact_intents),
        'lastVerifiedAt',c.last_verified_at,
        'sourceId',c.source_id
      ))
      order by c.claim_kind,c.value_text,c.id
    ) filter (where c.id is not null),'[]'::jsonb)
  )
  from local_intel.entity_evidence_claims c
  where c.entity_id=p_entity_id
    and c.lifecycle_state='current'
    and c.disclosure_posture in ('public_directory','public_contactable')
    and 'directory_display'=any(c.permitted_uses)
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions s
      where s.entity_id=c.entity_id
        and s.suppression_state='active'
        and (s.effective_until is null or s.effective_until > now())
        and s.suppression_scope in ('directory_display','all_use')
        and (s.evidence_claim_id is null or s.evidence_claim_id=c.id)
    );
$function$;

create or replace function local_intel.entity_contactable_evidence_service_v1(
  p_entity_id uuid,
  p_contact_intent text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_intent text:=lower(btrim(coalesce(p_contact_intent,'')));
  v_claims jsonb;
begin
  if v_intent !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Contact intent must be a normalized key.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'evidenceClaimId',c.id,
      'claimKind',c.claim_kind,
      'value',c.value_text,
      'contactChannel',c.contact_channel,
      'contactIntents',to_jsonb(c.contact_intents),
      'sourceClassKey',c.source_class_key,
      'evidenceStrength',c.evidence_strength,
      'lastVerifiedAt',c.last_verified_at,
      'sourceId',c.source_id
    ))
    order by c.contact_channel,c.claim_kind,c.value_text,c.id
  ),'[]'::jsonb)
  into v_claims
  from local_intel.entity_evidence_claims c
  where c.entity_id=p_entity_id
    and c.lifecycle_state='current'
    and c.disclosure_posture='public_contactable'
    and 'outreach'=any(c.permitted_uses)
    and c.contact_channel is not null
    and (v_intent=any(c.contact_intents) or 'general'=any(c.contact_intents))
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions s
      where s.entity_id=c.entity_id
        and s.suppression_state='active'
        and (s.effective_until is null or s.effective_until > now())
        and s.suppression_scope in ('outreach','all_use')
        and (s.evidence_claim_id is null or s.evidence_claim_id=c.id)
    );

  return jsonb_build_object(
    'contractVersion','entity_contactable_evidence_v1',
    'entityId',p_entity_id,
    'contactIntent',v_intent,
    'claims',v_claims
  );
end
$function$;

create or replace function local_intel.resolve_entities_by_evidence_value_service_v1(
  p_claim_kind text,
  p_value_text text,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_claim_kind,'')));
  v_normalized text;
  v_limit integer:=greatest(1,least(coalesce(p_limit,20),100));
  v_matches jsonb;
begin
  if v_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Claim kind must be a normalized key.' using errcode='22023';
  end if;

  v_normalized:=local_intel.normalize_evidence_value_v1(v_kind,p_value_text);
  if btrim(coalesce(v_normalized,''))='' then
    raise exception 'Resolution value is blank after normalization.' using errcode='22023';
  end if;

  with matched as (
    select
      e.id,
      e.name,
      e.entity_type,
      e.city,
      e.state,
      count(*) as evidence_count,
      array_agg(distinct c.source_class_key order by c.source_class_key) as source_classes,
      max(local_intel.disclosure_posture_rank_v1(c.disclosure_posture)) as strongest_posture_rank
    from local_intel.entity_evidence_claims c
    join local_intel.entities e on e.id=c.entity_id
    where c.claim_kind=v_kind
      and c.normalized_value=v_normalized
      and c.lifecycle_state='current'
      and c.disclosure_posture<>'suppressed'
      and 'identity_resolution'=any(c.permitted_uses)
      and not exists(
        select 1
        from local_intel.entity_contact_suppressions s
        where s.entity_id=c.entity_id
          and s.suppression_state='active'
          and (s.effective_until is null or s.effective_until > now())
          and s.suppression_scope='all_use'
          and (s.evidence_claim_id is null or s.evidence_claim_id=c.id)
      )
    group by e.id,e.name,e.entity_type,e.city,e.state
    order by count(*) desc,e.name,e.id
    limit v_limit
  )
  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'entityId',m.id,
      'name',m.name,
      'entityType',m.entity_type,
      'city',m.city,
      'state',m.state,
      'evidenceCount',m.evidence_count,
      'sourceClasses',to_jsonb(m.source_classes)
    ))
    order by m.evidence_count desc,m.name,m.id
  ),'[]'::jsonb)
  into v_matches
  from matched m;

  return jsonb_build_object(
    'contractVersion','evidence_identity_resolution_v1',
    'claimKind',v_kind,
    'matchCount',jsonb_array_length(v_matches),
    'matches',v_matches
  );
end
$function$;

revoke all on function local_intel.record_entity_evidence_claim_service_v1(
  uuid,text,text,text,text,text[],uuid,text,text,text[],timestamptz,date,date,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.record_entity_evidence_claim_service_v1(
  uuid,text,text,text,text,text[],uuid,text,text,text[],timestamptz,date,date,timestamptz,jsonb
) to service_role;

revoke all on function local_intel.set_entity_contact_suppression_service_v1(
  uuid,text,text,uuid,timestamptz,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.set_entity_contact_suppression_service_v1(
  uuid,text,text,uuid,timestamptz,jsonb,jsonb
) to service_role;

revoke all on function local_intel.entity_directory_evidence_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function local_intel.entity_directory_evidence_service_v1(uuid)
  to service_role;

revoke all on function local_intel.entity_contactable_evidence_service_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function local_intel.entity_contactable_evidence_service_v1(uuid,text)
  to service_role;

revoke all on function local_intel.resolve_entities_by_evidence_value_service_v1(text,text,integer)
  from public,anon,authenticated;
grant execute on function local_intel.resolve_entities_by_evidence_value_service_v1(text,text,integer)
  to service_role;

comment on function local_intel.entity_contactable_evidence_service_v1(uuid,text) is
  'Governed contactability membrane. Returns only current public_contactable evidence explicitly permitted for outreach and matching the requested contact intent, excluding active outreach/all-use suppressions. Legacy entity email/phone columns are not sufficient authority.';

comment on function local_intel.resolve_entities_by_evidence_value_service_v1(text,text,integer) is
  'Identity-resolution membrane. May use resolution_only evidence but returns canonical entity candidates without revealing hidden evidence values.';
