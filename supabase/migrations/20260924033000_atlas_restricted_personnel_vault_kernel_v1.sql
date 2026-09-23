-- Atlas Restricted Personnel Vault Kernel v1.
-- Ledger authority does not imply vault access. Vault payloads are ciphertext only.

create table if not exists atlas.restricted_vault_capabilities (
  capability_key text primary key,
  title text not null,
  capability_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint restricted_vault_capabilities_key_v1
    check (capability_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_capabilities_state_v1
    check (capability_state in ('active','retired')),
  constraint restricted_vault_capabilities_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.restricted_vault_capabilities(capability_key,title,metadata)
values
('vault_metadata_read','Read vault metadata','{"class":"read"}'::jsonb),
('vault_subject_index','Read vault subject index','{"class":"read"}'::jsonb),
('vault_subject_admin','Bind or retire vault subjects','{"class":"administration"}'::jsonb),
('vault_record_read','Read encrypted personnel record envelopes','{"class":"read"}'::jsonb),
('vault_record_write','Write encrypted personnel record envelopes','{"class":"write"}'::jsonb),
('vault_assertion_read','Read approved vault-safe assertions','{"class":"read"}'::jsonb),
('vault_assertion_write','Write approved vault-safe assertions','{"class":"write"}'::jsonb),
('vault_entitlement_admin','Grant or revoke vault entitlements','{"class":"administration"}'::jsonb),
('vault_audit_read','Read vault audit events','{"class":"audit"}'::jsonb),
('vault_bulk_export','Bulk export encrypted vault contents','{"class":"high_risk"}'::jsonb),
('vault_key_admin','Administer vault encryption-key references','{"class":"high_risk"}'::jsonb)
on conflict (capability_key) do update
set title=excluded.title,
    capability_state='active',
    metadata=atlas.restricted_vault_capabilities.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.restricted_vault_record_classes (
  record_class_key text primary key,
  title text not null,
  default_sensitivity text not null,
  class_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint restricted_vault_record_classes_key_v1
    check (record_class_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_record_classes_sensitivity_v1
    check (default_sensitivity in ('restricted','highly_restricted')),
  constraint restricted_vault_record_classes_state_v1
    check (class_state in ('active','retired')),
  constraint restricted_vault_record_classes_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.restricted_vault_record_classes(
  record_class_key,title,default_sensitivity,metadata
)
values
('compensation','Compensation','restricted','{}'::jsonb),
('tax_identity','Tax identity','highly_restricted','{}'::jsonb),
('banking_payroll','Banking / payroll','highly_restricted','{}'::jsonb),
('background_record','Background record','highly_restricted','{}'::jsonb),
('disciplinary_record','Disciplinary record','highly_restricted','{}'::jsonb),
('performance_review','Performance review','restricted','{}'::jsonb),
('accommodation_record','Accommodation record','highly_restricted','{}'::jsonb),
('identity_document','Identity document','highly_restricted','{}'::jsonb),
('other_personnel_sensitive','Other personnel-sensitive record','restricted','{}'::jsonb)
on conflict (record_class_key) do update
set title=excluded.title,
    default_sensitivity=excluded.default_sensitivity,
    class_state='active',
    metadata=atlas.restricted_vault_record_classes.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.restricted_vaults (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  stable_key text not null,
  title text not null,
  vault_kind text not null default 'personnel',
  vault_state text not null default 'active',
  crypto_profile text not null default 'envelope_aes_256_gcm_v1',
  kms_key_ref text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,stable_key),
  unique (ledger_id,id),
  constraint restricted_vaults_stable_key_v1
    check (stable_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vaults_title_v1
    check (btrim(title) <> ''),
  constraint restricted_vaults_kind_v1
    check (vault_kind in ('personnel')),
  constraint restricted_vaults_state_v1
    check (vault_state in ('active','sealed','retired')),
  constraint restricted_vaults_crypto_profile_v1
    check (crypto_profile in ('envelope_aes_256_gcm_v1')),
  constraint restricted_vaults_kms_key_ref_v1
    check (btrim(kms_key_ref) <> ''),
  constraint restricted_vaults_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.restricted_vaults is
  'Restricted custody boundary inside one Atlas Ledger. Ledger authority alone never grants personnel-record read access. kms_key_ref identifies an external KMS key; key material is never stored here.';

create table if not exists atlas.restricted_vault_subjects (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references atlas.restricted_vaults(id) on delete restrict,
  canonical_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  subject_state text not null default 'active',
  bound_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  bound_at timestamptz not null default now(),
  retired_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vault_id,id),
  constraint restricted_vault_subjects_state_v1
    check (subject_state in ('active','retired')),
  constraint restricted_vault_subjects_shape_v1
    check (
      (subject_state='active' and retired_at is null)
      or
      (subject_state='retired' and retired_at is not null)
    ),
  constraint restricted_vault_subjects_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists restricted_vault_subjects_current_uq_v1
  on atlas.restricted_vault_subjects(vault_id,canonical_entity_id)
  where subject_state='active';

comment on table atlas.restricted_vault_subjects is
  'Private binding that this vault has restricted personnel custody for one canonical person. It does not expose vault contents to Shared Intelligence.';

create table if not exists atlas.restricted_vault_entitlements (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references atlas.restricted_vaults(id) on delete restrict,
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  capability_key text not null
    references atlas.restricted_vault_capabilities(capability_key) on delete restrict,
  record_class_scope text[] not null default '{}'::text[],
  purpose_scope text[] not null default '{}'::text[],
  entitlement_state text not null default 'active',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  grant_basis jsonb not null default '{}'::jsonb,
  revoked_by_principal_id uuid references atlas.principals(id) on delete restrict,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint restricted_vault_entitlements_state_v1
    check (entitlement_state in ('active','revoked','expired')),
  constraint restricted_vault_entitlements_validity_v1
    check (valid_until is null or valid_until >= valid_from),
  constraint restricted_vault_entitlements_shape_v1
    check (
      (entitlement_state='active' and revoked_at is null and revoked_by_principal_id is null)
      or
      (entitlement_state='revoked' and revoked_at is not null and revoked_by_principal_id is not null)
      or
      (entitlement_state='expired')
    ),
  constraint restricted_vault_entitlements_basis_v1
    check (jsonb_typeof(grant_basis)='object'),
  constraint restricted_vault_entitlements_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists restricted_vault_entitlements_lookup_idx_v1
  on atlas.restricted_vault_entitlements(
    vault_id,principal_id,capability_key,entitlement_state,valid_from,valid_until
  );

comment on table atlas.restricted_vault_entitlements is
  'Explicit time-bounded vault capability grant. Empty class/purpose scopes mean all classes/purposes for that capability. Ledger authority is not a substitute for a vault entitlement.';

create table if not exists atlas.restricted_vault_records (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references atlas.restricted_vaults(id) on delete restrict,
  vault_subject_id uuid not null,
  record_class_key text not null
    references atlas.restricted_vault_record_classes(record_class_key) on delete restrict,
  purpose_key text not null,
  sensitivity text not null,
  record_state text not null default 'current',
  supersedes_record_id uuid references atlas.restricted_vault_records(id) on delete restrict,
  crypto_profile text not null,
  kms_key_ref text not null,
  kms_key_version text,
  ciphertext bytea not null,
  wrapped_data_key bytea not null,
  encryption_context jsonb not null default '{}'::jsonb,
  content_hash text not null,
  content_hash_algorithm text not null default 'sha256',
  retention_until date,
  metadata jsonb not null default '{}'::jsonb,
  written_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  written_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint restricted_vault_records_subject_fk_v1
    foreign key (vault_id,vault_subject_id)
    references atlas.restricted_vault_subjects(vault_id,id)
    on delete restrict,
  constraint restricted_vault_records_purpose_v1
    check (purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_records_sensitivity_v1
    check (sensitivity in ('restricted','highly_restricted')),
  constraint restricted_vault_records_state_v1
    check (record_state in ('current','superseded','retired')),
  constraint restricted_vault_records_crypto_v1
    check (crypto_profile in ('envelope_aes_256_gcm_v1')),
  constraint restricted_vault_records_kms_ref_v1
    check (btrim(kms_key_ref) <> ''),
  constraint restricted_vault_records_ciphertext_v1
    check (octet_length(ciphertext) >= 16),
  constraint restricted_vault_records_wrapped_key_v1
    check (octet_length(wrapped_data_key) >= 16),
  constraint restricted_vault_records_hash_v1
    check (length(content_hash) >= 32),
  constraint restricted_vault_records_hash_algorithm_v1
    check (content_hash_algorithm ~ '^[a-z0-9][a-z0-9_-]*$'),
  constraint restricted_vault_records_encryption_context_v1
    check (jsonb_typeof(encryption_context)='object'),
  constraint restricted_vault_records_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists restricted_vault_records_subject_idx_v1
  on atlas.restricted_vault_records(vault_id,vault_subject_id,record_class_key,record_state,written_at desc);

comment on table atlas.restricted_vault_records is
  'Ciphertext-only personnel payload storage. Plaintext and KMS master-key material have no columns in this table. Encryption/decryption occurs in a trusted external crypto/KMS layer.';

create table if not exists atlas.restricted_vault_assertions (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references atlas.restricted_vaults(id) on delete restrict,
  vault_subject_id uuid not null,
  assertion_key text not null,
  assertion_value jsonb not null,
  assertion_state text not null default 'current',
  purpose_key text not null,
  basis_record_id uuid references atlas.restricted_vault_records(id) on delete set null,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  written_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint restricted_vault_assertions_subject_fk_v1
    foreign key (vault_id,vault_subject_id)
    references atlas.restricted_vault_subjects(vault_id,id)
    on delete restrict,
  constraint restricted_vault_assertions_key_v1
    check (assertion_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_assertions_value_v1
    check (jsonb_typeof(assertion_value) in ('boolean','string','number','null')),
  constraint restricted_vault_assertions_state_v1
    check (assertion_state in ('current','superseded','retired')),
  constraint restricted_vault_assertions_purpose_v1
    check (purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_assertions_validity_v1
    check (effective_until is null or effective_until >= effective_from),
  constraint restricted_vault_assertions_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists restricted_vault_assertions_subject_idx_v1
  on atlas.restricted_vault_assertions(vault_id,vault_subject_id,assertion_key,assertion_state);

comment on table atlas.restricted_vault_assertions is
  'Controlled derived answers from restricted records. Assertions remain vault-controlled in v1 and do not automatically become Ledger or Shared Intelligence facts.';

create table if not exists atlas.restricted_vault_audit_events (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references atlas.restricted_vaults(id) on delete restrict,
  principal_id uuid references atlas.principals(id) on delete set null,
  action_key text not null,
  outcome text not null,
  capability_key text,
  vault_subject_id uuid,
  record_id uuid,
  assertion_id uuid,
  purpose_key text,
  reason_text text,
  context jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint restricted_vault_audit_action_v1
    check (action_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_audit_outcome_v1
    check (outcome in ('allowed','denied','completed','failed')),
  constraint restricted_vault_audit_capability_v1
    check (capability_key is null or capability_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_audit_purpose_v1
    check (purpose_key is null or purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_audit_context_v1
    check (jsonb_typeof(context)='object')
);

create index if not exists restricted_vault_audit_vault_time_idx_v1
  on atlas.restricted_vault_audit_events(vault_id,occurred_at desc);

create index if not exists restricted_vault_audit_principal_time_idx_v1
  on atlas.restricted_vault_audit_events(principal_id,occurred_at desc);

comment on table atlas.restricted_vault_audit_events is
  'Append-only access/accountability trail for restricted-vault actions, including denied reads.';

alter table atlas.restricted_vault_capabilities enable row level security;
alter table atlas.restricted_vault_record_classes enable row level security;
alter table atlas.restricted_vaults enable row level security;
alter table atlas.restricted_vault_subjects enable row level security;
alter table atlas.restricted_vault_entitlements enable row level security;
alter table atlas.restricted_vault_records enable row level security;
alter table atlas.restricted_vault_assertions enable row level security;
alter table atlas.restricted_vault_audit_events enable row level security;

revoke all on table atlas.restricted_vault_capabilities from public,anon,authenticated;
revoke all on table atlas.restricted_vault_record_classes from public,anon,authenticated;
revoke all on table atlas.restricted_vaults from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_subjects from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_entitlements from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_records from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_assertions from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_audit_events from public,anon,authenticated,service_role;

grant select on table atlas.restricted_vault_capabilities to service_role;
grant select on table atlas.restricted_vault_record_classes to service_role;

create or replace function atlas.set_restricted_vault_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists restricted_vault_capabilities_updated_at_v1
  on atlas.restricted_vault_capabilities;
create trigger restricted_vault_capabilities_updated_at_v1
before update on atlas.restricted_vault_capabilities
for each row execute function atlas.set_restricted_vault_updated_at_v1();

drop trigger if exists restricted_vault_record_classes_updated_at_v1
  on atlas.restricted_vault_record_classes;
create trigger restricted_vault_record_classes_updated_at_v1
before update on atlas.restricted_vault_record_classes
for each row execute function atlas.set_restricted_vault_updated_at_v1();

drop trigger if exists restricted_vaults_updated_at_v1
  on atlas.restricted_vaults;
create trigger restricted_vaults_updated_at_v1
before update on atlas.restricted_vaults
for each row execute function atlas.set_restricted_vault_updated_at_v1();

drop trigger if exists restricted_vault_subjects_updated_at_v1
  on atlas.restricted_vault_subjects;
create trigger restricted_vault_subjects_updated_at_v1
before update on atlas.restricted_vault_subjects
for each row execute function atlas.set_restricted_vault_updated_at_v1();

drop trigger if exists restricted_vault_entitlements_updated_at_v1
  on atlas.restricted_vault_entitlements;
create trigger restricted_vault_entitlements_updated_at_v1
before update on atlas.restricted_vault_entitlements
for each row execute function atlas.set_restricted_vault_updated_at_v1();

drop trigger if exists restricted_vault_assertions_updated_at_v1
  on atlas.restricted_vault_assertions;
create trigger restricted_vault_assertions_updated_at_v1
before update on atlas.restricted_vault_assertions
for each row execute function atlas.set_restricted_vault_updated_at_v1();

create or replace function atlas.prevent_restricted_vault_audit_mutation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  raise exception 'Restricted-vault audit events are append-only.'
    using errcode='42501';
end
$function$;

drop trigger if exists restricted_vault_audit_append_only_v1
  on atlas.restricted_vault_audit_events;
create trigger restricted_vault_audit_append_only_v1
before update or delete on atlas.restricted_vault_audit_events
for each row execute function atlas.prevent_restricted_vault_audit_mutation_v1();

create or replace function atlas.write_restricted_vault_audit_event_internal_v1(
  p_vault_id uuid,
  p_principal_id uuid,
  p_action_key text,
  p_outcome text,
  p_capability_key text default null,
  p_vault_subject_id uuid default null,
  p_record_id uuid default null,
  p_assertion_id uuid default null,
  p_purpose_key text default null,
  p_reason_text text default null,
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_id uuid;
begin
  insert into atlas.restricted_vault_audit_events(
    vault_id,principal_id,action_key,outcome,capability_key,
    vault_subject_id,record_id,assertion_id,purpose_key,reason_text,context
  )
  values(
    p_vault_id,p_principal_id,lower(btrim(p_action_key)),lower(btrim(p_outcome)),
    case when p_capability_key is null then null else lower(btrim(p_capability_key)) end,
    p_vault_subject_id,p_record_id,p_assertion_id,
    case when p_purpose_key is null then null else lower(btrim(p_purpose_key)) end,
    nullif(btrim(p_reason_text),''),
    coalesce(p_context,'{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end
$function$;

revoke all on function atlas.write_restricted_vault_audit_event_internal_v1(
  uuid,uuid,text,text,text,uuid,uuid,uuid,text,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.principal_has_restricted_vault_capability_v1(
  p_principal_id uuid,
  p_vault_id uuid,
  p_capability_key text,
  p_record_class_key text default null,
  p_purpose_key text default null
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select exists(
    select 1
    from atlas.restricted_vault_entitlements e
    join atlas.restricted_vault_capabilities c
      on c.capability_key=e.capability_key
     and c.capability_state='active'
    join atlas.restricted_vaults v
      on v.id=e.vault_id
     and v.vault_state='active'
    where e.principal_id=p_principal_id
      and e.vault_id=p_vault_id
      and e.capability_key=lower(btrim(p_capability_key))
      and e.entitlement_state='active'
      and e.valid_from<=now()
      and (e.valid_until is null or e.valid_until>now())
      and (
        cardinality(e.record_class_scope)=0
        or (
          p_record_class_key is not null
          and lower(btrim(p_record_class_key))=any(e.record_class_scope)
        )
      )
      and (
        cardinality(e.purpose_scope)=0
        or (
          p_purpose_key is not null
          and lower(btrim(p_purpose_key))=any(e.purpose_scope)
        )
      )
  );
$function$;

revoke all on function atlas.principal_has_restricted_vault_capability_v1(
  uuid,uuid,text,text,text
) from public,anon,authenticated;
grant execute on function atlas.principal_has_restricted_vault_capability_v1(
  uuid,uuid,text,text,text
) to service_role;

create or replace function atlas.create_restricted_personnel_vault_service_v1(
  p_ledger_id uuid,
  p_created_by_principal_id uuid,
  p_stable_key text,
  p_title text,
  p_kms_key_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text:=lower(btrim(coalesce(p_stable_key,'')));
  v_vault atlas.restricted_vaults%rowtype;
  v_cap text;
begin
  if not atlas.principal_has_ledger_authority_v1(
    p_created_by_principal_id,p_ledger_id
  ) then
    raise exception 'Principal lacks governing authority over Ledger.'
      using errcode='42501';
  end if;

  if not exists(
    select 1 from atlas.ledgers l
    where l.id=p_ledger_id and l.status='active'
  ) then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  if v_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_title,''))=''
     or btrim(coalesce(p_kms_key_ref,''))='' then
    raise exception 'Vault key, title, and KMS key reference are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Vault metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into atlas.restricted_vaults(
    ledger_id,stable_key,title,vault_kind,vault_state,
    crypto_profile,kms_key_ref,metadata,created_by_principal_id
  )
  values(
    p_ledger_id,v_key,btrim(p_title),'personnel','active',
    'envelope_aes_256_gcm_v1',btrim(p_kms_key_ref),
    coalesce(p_metadata,'{}'::jsonb),p_created_by_principal_id
  )
  returning * into v_vault;

  foreach v_cap in array array[
    'vault_metadata_read',
    'vault_subject_index',
    'vault_subject_admin',
    'vault_entitlement_admin',
    'vault_audit_read'
  ]::text[]
  loop
    insert into atlas.restricted_vault_entitlements(
      vault_id,principal_id,capability_key,record_class_scope,purpose_scope,
      entitlement_state,valid_from,granted_by_principal_id,grant_basis,metadata
    )
    values(
      v_vault.id,p_created_by_principal_id,v_cap,'{}'::text[],'{}'::text[],
      'active',now(),p_created_by_principal_id,
      jsonb_build_object('basis','vault_creator_bootstrap'),
      '{}'::jsonb
    );
  end loop;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    v_vault.id,p_created_by_principal_id,'vault_create','completed',
    null,null,null,null,null,'initial restricted personnel vault creation',
    jsonb_build_object('ledgerId',p_ledger_id,'stableKey',v_key)
  );

  return jsonb_build_object(
    'contractVersion','restricted_personnel_vault_v1',
    'vaultId',v_vault.id,
    'ledgerId',v_vault.ledger_id,
    'stableKey',v_vault.stable_key,
    'title',v_vault.title,
    'vaultState',v_vault.vault_state,
    'cryptoProfile',v_vault.crypto_profile,
    'kmsKeyRef',v_vault.kms_key_ref
  );
end
$function$;

create or replace function atlas.grant_restricted_vault_entitlement_service_v1(
  p_vault_id uuid,
  p_target_principal_id uuid,
  p_capability_key text,
  p_granted_by_principal_id uuid,
  p_record_class_scope text[] default '{}'::text[],
  p_purpose_scope text[] default '{}'::text[],
  p_valid_from timestamptz default now(),
  p_valid_until timestamptz default null,
  p_grant_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_cap text:=lower(btrim(coalesce(p_capability_key,'')));
  v_record_scope text[];
  v_purpose_scope text[];
  v_entitlement atlas.restricted_vault_entitlements%rowtype;
  v_allowed boolean;
begin
  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_granted_by_principal_id,p_vault_id,'vault_entitlement_admin',null,null
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      p_vault_id,p_granted_by_principal_id,'entitlement_grant','denied',
      'vault_entitlement_admin',null,null,null,null,
      'grantor lacks vault entitlement administration capability',
      jsonb_build_object('targetPrincipalId',p_target_principal_id,'requestedCapability',v_cap)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_entitlement_grant_v1',
      'authorized',false,
      'reason','vault_entitlement_admin_required'
    );
  end if;

  if not exists(
    select 1 from atlas.principals p
    where p.id=p_target_principal_id and p.status='active'
  ) then
    raise exception 'Active target Principal not found.' using errcode='P0002';
  end if;

  if not exists(
    select 1 from atlas.restricted_vault_capabilities c
    where c.capability_key=v_cap and c.capability_state='active'
  ) then
    raise exception 'Vault capability is missing or inactive.' using errcode='P0002';
  end if;

  select coalesce(array_agg(distinct lower(btrim(x)) order by lower(btrim(x))),'{}'::text[])
  into v_record_scope
  from unnest(coalesce(p_record_class_scope,'{}'::text[])) t(x);

  if exists(
    select 1 from unnest(v_record_scope) x
    where not exists(
      select 1 from atlas.restricted_vault_record_classes c
      where c.record_class_key=x and c.class_state='active'
    )
  ) then
    raise exception 'Record-class entitlement scope contains an unknown class.'
      using errcode='22023';
  end if;

  select coalesce(array_agg(distinct lower(btrim(x)) order by lower(btrim(x))),'{}'::text[])
  into v_purpose_scope
  from unnest(coalesce(p_purpose_scope,'{}'::text[])) t(x);

  if exists(
    select 1 from unnest(v_purpose_scope) x
    where x !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) then
    raise exception 'Purpose entitlement scope contains an invalid key.'
      using errcode='22023';
  end if;

  if p_valid_until is not null
     and p_valid_until<=coalesce(p_valid_from,now()) then
    raise exception 'Entitlement end must be after entitlement start.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_grant_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Entitlement basis/metadata must be JSON objects.'
      using errcode='22023';
  end if;

  insert into atlas.restricted_vault_entitlements(
    vault_id,principal_id,capability_key,record_class_scope,purpose_scope,
    entitlement_state,valid_from,valid_until,granted_by_principal_id,
    grant_basis,metadata
  )
  values(
    p_vault_id,p_target_principal_id,v_cap,v_record_scope,v_purpose_scope,
    'active',coalesce(p_valid_from,now()),p_valid_until,
    p_granted_by_principal_id,coalesce(p_grant_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_entitlement;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_granted_by_principal_id,'entitlement_grant','completed',
    'vault_entitlement_admin',null,null,null,null,
    'vault entitlement granted',
    jsonb_build_object(
      'entitlementId',v_entitlement.id,
      'targetPrincipalId',p_target_principal_id,
      'grantedCapability',v_cap,
      'validFrom',v_entitlement.valid_from,
      'validUntil',v_entitlement.valid_until
    )
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_entitlement_grant_v1',
    'authorized',true,
    'entitlementId',v_entitlement.id,
    'vaultId',v_entitlement.vault_id,
    'principalId',v_entitlement.principal_id,
    'capabilityKey',v_entitlement.capability_key,
    'recordClassScope',to_jsonb(v_entitlement.record_class_scope),
    'purposeScope',to_jsonb(v_entitlement.purpose_scope),
    'validFrom',v_entitlement.valid_from,
    'validUntil',v_entitlement.valid_until
  );
end
$function$;

create or replace function atlas.revoke_restricted_vault_entitlement_service_v1(
  p_entitlement_id uuid,
  p_revoked_by_principal_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_entitlement atlas.restricted_vault_entitlements%rowtype;
  v_allowed boolean;
begin
  select * into v_entitlement
  from atlas.restricted_vault_entitlements e
  where e.id=p_entitlement_id;

  if v_entitlement.id is null then
    raise exception 'Vault entitlement not found.' using errcode='P0002';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_revoked_by_principal_id,v_entitlement.vault_id,
    'vault_entitlement_admin',null,null
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      v_entitlement.vault_id,p_revoked_by_principal_id,
      'entitlement_revoke','denied','vault_entitlement_admin',
      null,null,null,null,'revoker lacks vault entitlement administration capability',
      jsonb_build_object('entitlementId',p_entitlement_id)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_entitlement_revoke_v1',
      'authorized',false,
      'reason','vault_entitlement_admin_required'
    );
  end if;

  if btrim(coalesce(p_reason,''))='' then
    raise exception 'Revocation reason is required.' using errcode='22023';
  end if;

  update atlas.restricted_vault_entitlements
  set entitlement_state='revoked',
      revoked_by_principal_id=p_revoked_by_principal_id,
      revoked_at=now(),
      updated_at=now()
  where id=p_entitlement_id
    and entitlement_state='active'
  returning * into v_entitlement;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    v_entitlement.vault_id,p_revoked_by_principal_id,
    'entitlement_revoke','completed','vault_entitlement_admin',
    null,null,null,null,p_reason,
    jsonb_build_object('entitlementId',p_entitlement_id)
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_entitlement_revoke_v1',
    'authorized',true,
    'entitlementId',p_entitlement_id,
    'entitlementState','revoked'
  );
end
$function$;

create or replace function atlas.bind_restricted_vault_subject_service_v1(
  p_vault_id uuid,
  p_canonical_entity_id uuid,
  p_bound_by_principal_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_subject atlas.restricted_vault_subjects%rowtype;
  v_allowed boolean;
begin
  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_bound_by_principal_id,p_vault_id,'vault_subject_admin',null,null
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      p_vault_id,p_bound_by_principal_id,'subject_bind','denied',
      'vault_subject_admin',null,null,null,null,
      'principal lacks subject administration capability',
      jsonb_build_object('canonicalEntityId',p_canonical_entity_id)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_subject_v1',
      'authorized',false,
      'reason','vault_subject_admin_required'
    );
  end if;

  if not exists(
    select 1 from local_intel.entities e
    where e.id=p_canonical_entity_id and e.entity_type='person'
  ) then
    raise exception 'Restricted personnel vault subject must be a canonical person.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Subject metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_subject
  from atlas.restricted_vault_subjects s
  where s.vault_id=p_vault_id
    and s.canonical_entity_id=p_canonical_entity_id
    and s.subject_state='active'
  limit 1;

  if v_subject.id is null then
    insert into atlas.restricted_vault_subjects(
      vault_id,canonical_entity_id,subject_state,bound_by_principal_id,metadata
    )
    values(
      p_vault_id,p_canonical_entity_id,'active',
      p_bound_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_subject;
  end if;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_bound_by_principal_id,'subject_bind','completed',
    'vault_subject_admin',v_subject.id,null,null,null,
    'canonical person bound to restricted personnel vault',
    jsonb_build_object('canonicalEntityId',p_canonical_entity_id)
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_subject_v1',
    'authorized',true,
    'vaultSubjectId',v_subject.id,
    'vaultId',v_subject.vault_id,
    'canonicalEntityId',v_subject.canonical_entity_id,
    'subjectState',v_subject.subject_state
  );
end
$function$;

create or replace function atlas.store_restricted_vault_record_service_v1(
  p_vault_id uuid,
  p_vault_subject_id uuid,
  p_record_class_key text,
  p_purpose_key text,
  p_written_by_principal_id uuid,
  p_ciphertext bytea,
  p_wrapped_data_key bytea,
  p_content_hash text,
  p_kms_key_version text default null,
  p_encryption_context jsonb default '{}'::jsonb,
  p_retention_until date default null,
  p_supersedes_record_id uuid default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_class text:=lower(btrim(coalesce(p_record_class_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_vault atlas.restricted_vaults%rowtype;
  v_record_class atlas.restricted_vault_record_classes%rowtype;
  v_record atlas.restricted_vault_records%rowtype;
  v_allowed boolean;
begin
  select * into v_vault
  from atlas.restricted_vaults v
  where v.id=p_vault_id and v.vault_state='active';

  if v_vault.id is null then
    raise exception 'Active restricted vault not found.' using errcode='P0002';
  end if;

  select * into v_record_class
  from atlas.restricted_vault_record_classes c
  where c.record_class_key=v_class and c.class_state='active';

  if v_record_class.record_class_key is null then
    raise exception 'Restricted-vault record class is missing or inactive.'
      using errcode='P0002';
  end if;

  if v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Purpose key must be normalized.' using errcode='22023';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_written_by_principal_id,p_vault_id,'vault_record_write',v_class,v_purpose
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      p_vault_id,p_written_by_principal_id,'record_write','denied',
      'vault_record_write',p_vault_subject_id,null,null,v_purpose,
      coalesce(nullif(btrim(p_reason),''),'principal lacks record-write capability'),
      jsonb_build_object('recordClassKey',v_class)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_record_write_v1',
      'authorized',false,
      'reason','vault_record_write_required'
    );
  end if;

  if not exists(
    select 1 from atlas.restricted_vault_subjects s
    where s.id=p_vault_subject_id
      and s.vault_id=p_vault_id
      and s.subject_state='active'
  ) then
    raise exception 'Active vault subject not found.' using errcode='P0002';
  end if;

  if octet_length(p_ciphertext)<16
     or octet_length(p_wrapped_data_key)<16
     or length(coalesce(p_content_hash,''))<32 then
    raise exception 'Encrypted record envelope is incomplete.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_encryption_context,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Encryption context and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if p_supersedes_record_id is not null
     and not exists(
       select 1 from atlas.restricted_vault_records r
       where r.id=p_supersedes_record_id
         and r.vault_id=p_vault_id
         and r.vault_subject_id=p_vault_subject_id
     ) then
    raise exception 'Superseded record is outside this vault subject.'
      using errcode='22023';
  end if;

  insert into atlas.restricted_vault_records(
    vault_id,vault_subject_id,record_class_key,purpose_key,sensitivity,
    record_state,supersedes_record_id,crypto_profile,kms_key_ref,kms_key_version,
    ciphertext,wrapped_data_key,encryption_context,content_hash,
    content_hash_algorithm,retention_until,metadata,written_by_principal_id
  )
  values(
    p_vault_id,p_vault_subject_id,v_class,v_purpose,
    v_record_class.default_sensitivity,'current',p_supersedes_record_id,
    v_vault.crypto_profile,v_vault.kms_key_ref,nullif(btrim(p_kms_key_version),''),
    p_ciphertext,p_wrapped_data_key,coalesce(p_encryption_context,'{}'::jsonb),
    btrim(p_content_hash),'sha256',p_retention_until,
    coalesce(p_metadata,'{}'::jsonb),p_written_by_principal_id
  )
  returning * into v_record;

  if p_supersedes_record_id is not null then
    update atlas.restricted_vault_records
    set record_state='superseded'
    where id=p_supersedes_record_id and record_state='current';
  end if;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_written_by_principal_id,'record_write','completed',
    'vault_record_write',p_vault_subject_id,v_record.id,null,v_purpose,
    coalesce(nullif(btrim(p_reason),''),'encrypted personnel record stored'),
    jsonb_build_object('recordClassKey',v_class,'sensitivity',v_record.sensitivity)
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_record_write_v1',
    'authorized',true,
    'recordId',v_record.id,
    'vaultId',v_record.vault_id,
    'vaultSubjectId',v_record.vault_subject_id,
    'recordClassKey',v_record.record_class_key,
    'purposeKey',v_record.purpose_key,
    'sensitivity',v_record.sensitivity,
    'recordState',v_record.record_state,
    'cryptoProfile',v_record.crypto_profile
  );
end
$function$;

create or replace function atlas.read_restricted_vault_record_envelope_service_v1(
  p_record_id uuid,
  p_principal_id uuid,
  p_reason text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_record atlas.restricted_vault_records%rowtype;
  v_allowed boolean;
begin
  select * into v_record
  from atlas.restricted_vault_records r
  where r.id=p_record_id;

  if v_record.id is null then
    raise exception 'Restricted-vault record not found.' using errcode='P0002';
  end if;

  if btrim(coalesce(p_reason,''))='' then
    raise exception 'Restricted-vault read reason is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Read context must be a JSON object.' using errcode='22023';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_principal_id,v_record.vault_id,'vault_record_read',
    v_record.record_class_key,v_record.purpose_key
  );

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    v_record.vault_id,p_principal_id,'record_read_attempt',
    case when v_allowed then 'allowed' else 'denied' end,
    'vault_record_read',v_record.vault_subject_id,v_record.id,null,
    v_record.purpose_key,p_reason,
    coalesce(p_context,'{}'::jsonb) || jsonb_build_object(
      'recordClassKey',v_record.record_class_key
    )
  );

  if not v_allowed then
    return jsonb_build_object(
      'contractVersion','restricted_vault_record_envelope_v1',
      'authorized',false,
      'recordId',v_record.id,
      'reason','vault_record_read_required'
    );
  end if;

  return jsonb_build_object(
    'contractVersion','restricted_vault_record_envelope_v1',
    'authorized',true,
    'recordId',v_record.id,
    'vaultId',v_record.vault_id,
    'vaultSubjectId',v_record.vault_subject_id,
    'recordClassKey',v_record.record_class_key,
    'purposeKey',v_record.purpose_key,
    'sensitivity',v_record.sensitivity,
    'recordState',v_record.record_state,
    'cryptoProfile',v_record.crypto_profile,
    'kmsKeyRef',v_record.kms_key_ref,
    'kmsKeyVersion',v_record.kms_key_version,
    'ciphertextBase64',encode(v_record.ciphertext,'base64'),
    'wrappedDataKeyBase64',encode(v_record.wrapped_data_key,'base64'),
    'encryptionContext',v_record.encryption_context,
    'contentHash',v_record.content_hash,
    'contentHashAlgorithm',v_record.content_hash_algorithm,
    'retentionUntil',v_record.retention_until,
    'writtenAt',v_record.written_at
  );
end
$function$;

create or replace function atlas.write_restricted_vault_assertion_service_v1(
  p_vault_id uuid,
  p_vault_subject_id uuid,
  p_assertion_key text,
  p_assertion_value jsonb,
  p_purpose_key text,
  p_written_by_principal_id uuid,
  p_basis_record_id uuid default null,
  p_effective_until timestamptz default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text:=lower(btrim(coalesce(p_assertion_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_assertion atlas.restricted_vault_assertions%rowtype;
  v_allowed boolean;
begin
  if v_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Assertion and purpose keys must be normalized.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_assertion_value) not in ('boolean','string','number','null') then
    raise exception 'Vault-safe assertion value must be scalar.'
      using errcode='22023';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_written_by_principal_id,p_vault_id,'vault_assertion_write',null,v_purpose
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      p_vault_id,p_written_by_principal_id,'assertion_write','denied',
      'vault_assertion_write',p_vault_subject_id,null,null,v_purpose,
      coalesce(nullif(btrim(p_reason),''),'principal lacks assertion-write capability'),
      jsonb_build_object('assertionKey',v_key)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_assertion_write_v1',
      'authorized',false,
      'reason','vault_assertion_write_required'
    );
  end if;

  if not exists(
    select 1 from atlas.restricted_vault_subjects s
    where s.id=p_vault_subject_id
      and s.vault_id=p_vault_id
      and s.subject_state='active'
  ) then
    raise exception 'Active vault subject not found.' using errcode='P0002';
  end if;

  if p_basis_record_id is not null
     and not exists(
       select 1 from atlas.restricted_vault_records r
       where r.id=p_basis_record_id
         and r.vault_id=p_vault_id
         and r.vault_subject_id=p_vault_subject_id
     ) then
    raise exception 'Assertion basis record is outside this vault subject.'
      using errcode='22023';
  end if;

  if p_effective_until is not null and p_effective_until<=now() then
    raise exception 'Assertion effective-until must be in the future.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Assertion metadata must be a JSON object.'
      using errcode='22023';
  end if;

  update atlas.restricted_vault_assertions
  set assertion_state='superseded',
      updated_at=now()
  where vault_id=p_vault_id
    and vault_subject_id=p_vault_subject_id
    and assertion_key=v_key
    and purpose_key=v_purpose
    and assertion_state='current';

  insert into atlas.restricted_vault_assertions(
    vault_id,vault_subject_id,assertion_key,assertion_value,assertion_state,
    purpose_key,basis_record_id,effective_from,effective_until,
    written_by_principal_id,metadata
  )
  values(
    p_vault_id,p_vault_subject_id,v_key,p_assertion_value,'current',
    v_purpose,p_basis_record_id,now(),p_effective_until,
    p_written_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_assertion;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_written_by_principal_id,'assertion_write','completed',
    'vault_assertion_write',p_vault_subject_id,p_basis_record_id,
    v_assertion.id,v_purpose,
    coalesce(nullif(btrim(p_reason),''),'vault-safe assertion written'),
    jsonb_build_object('assertionKey',v_key)
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_assertion_write_v1',
    'authorized',true,
    'assertionId',v_assertion.id,
    'assertionKey',v_assertion.assertion_key,
    'purposeKey',v_assertion.purpose_key,
    'assertionState',v_assertion.assertion_state
  );
end
$function$;

create or replace function atlas.read_restricted_vault_assertions_service_v1(
  p_vault_id uuid,
  p_vault_subject_id uuid,
  p_principal_id uuid,
  p_purpose_key text,
  p_reason text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_allowed boolean;
  v_assertions jsonb;
begin
  if v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_reason,''))='' then
    raise exception 'Purpose and read reason are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Assertion-read context must be a JSON object.'
      using errcode='22023';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_principal_id,p_vault_id,'vault_assertion_read',null,v_purpose
  );

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_principal_id,'assertion_read_attempt',
    case when v_allowed then 'allowed' else 'denied' end,
    'vault_assertion_read',p_vault_subject_id,null,null,v_purpose,
    p_reason,coalesce(p_context,'{}'::jsonb)
  );

  if not v_allowed then
    return jsonb_build_object(
      'contractVersion','restricted_vault_assertion_read_v1',
      'authorized',false,
      'reason','vault_assertion_read_required',
      'assertions','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'assertionId',a.id,
      'assertionKey',a.assertion_key,
      'assertionValue',a.assertion_value,
      'purposeKey',a.purpose_key,
      'effectiveFrom',a.effective_from,
      'effectiveUntil',a.effective_until
    )
    order by a.assertion_key,a.created_at
  ),'[]'::jsonb)
  into v_assertions
  from atlas.restricted_vault_assertions a
  where a.vault_id=p_vault_id
    and a.vault_subject_id=p_vault_subject_id
    and a.purpose_key=v_purpose
    and a.assertion_state='current'
    and a.effective_from<=now()
    and (a.effective_until is null or a.effective_until>now());

  return jsonb_build_object(
    'contractVersion','restricted_vault_assertion_read_v1',
    'authorized',true,
    'vaultId',p_vault_id,
    'vaultSubjectId',p_vault_subject_id,
    'purposeKey',v_purpose,
    'assertions',v_assertions
  );
end
$function$;

create or replace function atlas.read_restricted_vault_audit_service_v1(
  p_vault_id uuid,
  p_principal_id uuid,
  p_limit integer default 100,
  p_reason text default 'vault audit review'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_allowed boolean;
  v_events jsonb;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
begin
  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_principal_id,p_vault_id,'vault_audit_read',null,null
  );

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_principal_id,'audit_read_attempt',
    case when v_allowed then 'allowed' else 'denied' end,
    'vault_audit_read',null,null,null,null,p_reason,
    jsonb_build_object('limit',v_limit)
  );

  if not v_allowed then
    return jsonb_build_object(
      'contractVersion','restricted_vault_audit_read_v1',
      'authorized',false,
      'reason','vault_audit_read_required',
      'events','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'auditEventId',q.id,
      'principalId',q.principal_id,
      'actionKey',q.action_key,
      'outcome',q.outcome,
      'capabilityKey',q.capability_key,
      'vaultSubjectId',q.vault_subject_id,
      'recordId',q.record_id,
      'assertionId',q.assertion_id,
      'purposeKey',q.purpose_key,
      'reason',q.reason_text,
      'context',q.context,
      'occurredAt',q.occurred_at
    )
    order by q.occurred_at desc,q.id
  ),'[]'::jsonb)
  into v_events
  from (
    select *
    from atlas.restricted_vault_audit_events e
    where e.vault_id=p_vault_id
    order by e.occurred_at desc,e.id
    limit v_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','restricted_vault_audit_read_v1',
    'authorized',true,
    'vaultId',p_vault_id,
    'events',v_events
  );
end
$function$;

revoke all on function atlas.create_restricted_personnel_vault_service_v1(
  uuid,uuid,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.create_restricted_personnel_vault_service_v1(
  uuid,uuid,text,text,text,jsonb
) to service_role;

revoke all on function atlas.grant_restricted_vault_entitlement_service_v1(
  uuid,uuid,text,uuid,text[],text[],timestamptz,timestamptz,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.grant_restricted_vault_entitlement_service_v1(
  uuid,uuid,text,uuid,text[],text[],timestamptz,timestamptz,jsonb,jsonb
) to service_role;

revoke all on function atlas.revoke_restricted_vault_entitlement_service_v1(
  uuid,uuid,text
) from public,anon,authenticated;
grant execute on function atlas.revoke_restricted_vault_entitlement_service_v1(
  uuid,uuid,text
) to service_role;

revoke all on function atlas.bind_restricted_vault_subject_service_v1(
  uuid,uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.bind_restricted_vault_subject_service_v1(
  uuid,uuid,uuid,jsonb
) to service_role;

revoke all on function atlas.store_restricted_vault_record_service_v1(
  uuid,uuid,text,text,uuid,bytea,bytea,text,text,jsonb,date,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.store_restricted_vault_record_service_v1(
  uuid,uuid,text,text,uuid,bytea,bytea,text,text,jsonb,date,uuid,text,jsonb
) to service_role;

revoke all on function atlas.read_restricted_vault_record_envelope_service_v1(
  uuid,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.read_restricted_vault_record_envelope_service_v1(
  uuid,uuid,text,jsonb
) to service_role;

revoke all on function atlas.write_restricted_vault_assertion_service_v1(
  uuid,uuid,text,jsonb,text,uuid,uuid,timestamptz,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.write_restricted_vault_assertion_service_v1(
  uuid,uuid,text,jsonb,text,uuid,uuid,timestamptz,text,jsonb
) to service_role;

revoke all on function atlas.read_restricted_vault_assertions_service_v1(
  uuid,uuid,uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.read_restricted_vault_assertions_service_v1(
  uuid,uuid,uuid,text,text,jsonb
) to service_role;

revoke all on function atlas.read_restricted_vault_audit_service_v1(
  uuid,uuid,integer,text
) from public,anon,authenticated;
grant execute on function atlas.read_restricted_vault_audit_service_v1(
  uuid,uuid,integer,text
) to service_role;
