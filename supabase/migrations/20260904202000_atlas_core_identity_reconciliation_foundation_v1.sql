-- Atlas Core identity reconciliation foundation v1
-- Reality Foundation #788
--
-- Evidence-first identity substrate. This migration deliberately does NOT bulk-copy
-- buyer reconstruction or local_intel rows into a canonical directory.

create table if not exists atlas.identity_subjects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  state text not null default 'active' check (state in ('active','retired')),
  created_by_user_id uuid null,
  creation_basis jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(creation_basis) = 'object')
);

create index if not exists identity_subjects_org_state_idx
  on atlas.identity_subjects (organization_id, state, created_at);

comment on table atlas.identity_subjects is
  'Thin tenant-scoped reconciliation anchors. Identity properties live as evidence/claims and projections, not privileged profile columns.';

create table if not exists atlas.identity_source_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  source_system_key text not null,
  source_record_kind text not null,
  source_record_key text not null,
  source_observed_at timestamptz null,
  source_authority text not null default 'evidence_only'
    check (source_authority in ('evidence_only','enrichment','action_result','authoritative_source')),
  custody_ref jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(source_system_key) <> ''),
  check (btrim(source_record_kind) <> ''),
  check (btrim(source_record_key) <> ''),
  check (jsonb_typeof(custody_ref) = 'object'),
  check (jsonb_typeof(metadata) = 'object'),
  unique (organization_id, source_system_key, source_record_kind, source_record_key)
);

create index if not exists identity_source_records_org_source_idx
  on atlas.identity_source_records (organization_id, source_system_key, source_record_kind);

comment on table atlas.identity_source_records is
  'Provider, legacy, imported, communication, route, or Receive evidence references. Source records remain source records.';

create table if not exists atlas.identity_claims (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  subject_id uuid not null references atlas.identity_subjects(id) on delete cascade,
  source_record_id uuid null references atlas.identity_source_records(id) on delete restrict,
  claim_kind text not null,
  claim_value jsonb not null,
  confidence numeric null check (confidence is null or (confidence >= 0 and confidence <= 1)),
  effective_from timestamptz null,
  effective_to timestamptz null,
  basis text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(claim_kind) <> ''),
  check (claim_value <> 'null'::jsonb),
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (jsonb_typeof(metadata) = 'object')
);

create index if not exists identity_claims_subject_kind_idx
  on atlas.identity_claims (organization_id, subject_id, claim_kind, created_at desc);
create index if not exists identity_claims_source_idx
  on atlas.identity_claims (source_record_id) where source_record_id is not null;

comment on table atlas.identity_claims is
  'Append-only source-attributed identity properties such as names, aliases, classification, email, phone, address, website, provider IDs, and other identity evidence.';

create table if not exists atlas.identity_source_subject_assertions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  source_record_id uuid not null references atlas.identity_source_records(id) on delete cascade,
  subject_id uuid not null references atlas.identity_subjects(id) on delete cascade,
  assertion_kind text not null check (assertion_kind in ('supports','probable','non_match')),
  confidence numeric null check (confidence is null or (confidence >= 0 and confidence <= 1)),
  basis text null,
  idempotency_key text null,
  created_by_user_id uuid null,
  created_at timestamptz not null default now(),
  check (idempotency_key is null or btrim(idempotency_key) <> '')
);

create unique index if not exists identity_source_subject_assertions_idem_uidx
  on atlas.identity_source_subject_assertions (organization_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists identity_source_subject_assertions_source_idx
  on atlas.identity_source_subject_assertions (organization_id, source_record_id, created_at desc);
create index if not exists identity_source_subject_assertions_subject_idx
  on atlas.identity_source_subject_assertions (organization_id, subject_id, created_at desc);

comment on table atlas.identity_source_subject_assertions is
  'Append-only assertions about whether a provider/source record concerns a tenant-scoped identity subject. Explicit non-match is retained.';

create table if not exists atlas.identity_subject_pair_assertions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  left_subject_id uuid not null references atlas.identity_subjects(id) on delete cascade,
  right_subject_id uuid not null references atlas.identity_subjects(id) on delete cascade,
  assertion_kind text not null check (assertion_kind in ('equivalent','probably_equivalent','distinct')),
  confidence numeric null check (confidence is null or (confidence >= 0 and confidence <= 1)),
  source_record_id uuid null references atlas.identity_source_records(id) on delete restrict,
  basis text null,
  idempotency_key text null,
  created_by_user_id uuid null,
  created_at timestamptz not null default now(),
  check (left_subject_id <> right_subject_id),
  check (idempotency_key is null or btrim(idempotency_key) <> '')
);

create unique index if not exists identity_subject_pair_assertions_idem_uidx
  on atlas.identity_subject_pair_assertions (organization_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists identity_subject_pair_assertions_left_idx
  on atlas.identity_subject_pair_assertions (organization_id, left_subject_id, created_at desc);
create index if not exists identity_subject_pair_assertions_right_idx
  on atlas.identity_subject_pair_assertions (organization_id, right_subject_id, created_at desc);

comment on table atlas.identity_subject_pair_assertions is
  'Append-only subject-equivalence, probable-equivalence, and explicit-distinct assertions. No destructive merge is implied.';

create table if not exists atlas.identity_reconciliation_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  review_kind text not null check (review_kind in ('source_binding','subject_equivalence','classification','claim_conflict','split_correction','other')),
  source_record_id uuid null references atlas.identity_source_records(id) on delete restrict,
  left_subject_id uuid null references atlas.identity_subjects(id) on delete restrict,
  right_subject_id uuid null references atlas.identity_subjects(id) on delete restrict,
  claim_id uuid null references atlas.identity_claims(id) on delete restrict,
  status text not null default 'open' check (status in ('open','resolved','superseded')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  candidate_data jsonb not null default '{}'::jsonb,
  opened_by text not null default 'atlas',
  resolution_summary text null,
  resolved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(candidate_data) = 'object'),
  check (btrim(opened_by) <> '')
);

create index if not exists identity_reconciliation_reviews_queue_idx
  on atlas.identity_reconciliation_reviews (organization_id, status, priority, created_at);

comment on table atlas.identity_reconciliation_reviews is
  'Mutable Core work queue for consequential or ambiguous identity questions. Decisions are preserved separately in append-only identity_reconciliation_adjudications.';

create table if not exists atlas.identity_reconciliation_adjudications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  review_id uuid null references atlas.identity_reconciliation_reviews(id) on delete restrict,
  decision_kind text not null check (decision_kind in (
    'accept_source_binding',
    'reject_source_binding',
    'subjects_equivalent',
    'subjects_distinct',
    'accept_claim',
    'reject_claim',
    'split_correction',
    'supersede_prior',
    'other'
  )),
  source_record_id uuid null references atlas.identity_source_records(id) on delete restrict,
  subject_id uuid null references atlas.identity_subjects(id) on delete restrict,
  related_subject_id uuid null references atlas.identity_subjects(id) on delete restrict,
  claim_id uuid null references atlas.identity_claims(id) on delete restrict,
  supersedes_adjudication_id uuid null references atlas.identity_reconciliation_adjudications(id) on delete restrict,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  basis text not null,
  adjudicated_by_user_id uuid null,
  adjudicated_by_label text not null,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(evidence_snapshot) = 'object'),
  check (btrim(basis) <> ''),
  check (btrim(adjudicated_by_label) <> ''),
  check (related_subject_id is null or subject_id is null or related_subject_id <> subject_id)
);

create index if not exists identity_reconciliation_adjudications_review_idx
  on atlas.identity_reconciliation_adjudications (organization_id, review_id, created_at desc)
  where review_id is not null;
create index if not exists identity_reconciliation_adjudications_subject_idx
  on atlas.identity_reconciliation_adjudications (organization_id, subject_id, created_at desc)
  where subject_id is not null;

comment on table atlas.identity_reconciliation_adjudications is
  'Append-only human/system adjudication ledger for identity reconciliation. Prior decisions are superseded explicitly, never rewritten.';

create table if not exists atlas.identity_subject_projections (
  subject_id uuid primary key references atlas.identity_subjects(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  subject_kind text not null default 'unknown' check (subject_kind in ('unknown','person','organization','place')),
  display_name text null,
  aliases jsonb not null default '[]'::jsonb,
  contact_points jsonb not null default '[]'::jsonb,
  unresolved_identity boolean not null default true,
  confidence numeric null check (confidence is null or (confidence >= 0 and confidence <= 1)),
  projection_basis jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  check (display_name is null or btrim(display_name) <> ''),
  check (jsonb_typeof(aliases) = 'array'),
  check (jsonb_typeof(contact_points) = 'array'),
  check (jsonb_typeof(projection_basis) = 'object')
);

create index if not exists identity_subject_projections_org_kind_idx
  on atlas.identity_subject_projections (organization_id, subject_kind, display_name);

comment on table atlas.identity_subject_projections is
  'Mutable read projection over identity evidence/adjudication. This is not the identity evidence ledger.';

create or replace function atlas.block_identity_evidence_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Atlas identity evidence/adjudication rows are append-only.' using errcode='55000';
end;
$function$;

create or replace function atlas.block_identity_subject_delete_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Atlas identity subjects are retired or corrected; they are not deleted.' using errcode='55000';
end;
$function$;

drop trigger if exists identity_subjects_no_delete on atlas.identity_subjects;
create trigger identity_subjects_no_delete
before delete on atlas.identity_subjects
for each row execute function atlas.block_identity_subject_delete_v1();

drop trigger if exists identity_source_records_append_only on atlas.identity_source_records;
create trigger identity_source_records_append_only
before update or delete on atlas.identity_source_records
for each row execute function atlas.block_identity_evidence_mutation_v1();

drop trigger if exists identity_claims_append_only on atlas.identity_claims;
create trigger identity_claims_append_only
before update or delete on atlas.identity_claims
for each row execute function atlas.block_identity_evidence_mutation_v1();

drop trigger if exists identity_source_subject_assertions_append_only on atlas.identity_source_subject_assertions;
create trigger identity_source_subject_assertions_append_only
before update or delete on atlas.identity_source_subject_assertions
for each row execute function atlas.block_identity_evidence_mutation_v1();

drop trigger if exists identity_subject_pair_assertions_append_only on atlas.identity_subject_pair_assertions;
create trigger identity_subject_pair_assertions_append_only
before update or delete on atlas.identity_subject_pair_assertions
for each row execute function atlas.block_identity_evidence_mutation_v1();

drop trigger if exists identity_reconciliation_adjudications_append_only on atlas.identity_reconciliation_adjudications;
create trigger identity_reconciliation_adjudications_append_only
before update or delete on atlas.identity_reconciliation_adjudications
for each row execute function atlas.block_identity_evidence_mutation_v1();

create or replace function atlas.identity_projection_guard_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  if not exists (
    select 1 from atlas.identity_subjects s
    where s.id = new.subject_id
      and s.organization_id = new.organization_id
  ) then
    raise exception 'Identity projection subject must belong to the same organization.' using errcode='23514';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists identity_subject_projections_guard on atlas.identity_subject_projections;
create trigger identity_subject_projections_guard
before insert or update on atlas.identity_subject_projections
for each row execute function atlas.identity_projection_guard_v1();

create or replace function atlas.identity_review_touch_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  new.updated_at := now();
  if new.status = 'resolved' and new.resolved_at is null then
    new.resolved_at := now();
  end if;
  return new;
end;
$function$;

drop trigger if exists identity_reconciliation_reviews_touch on atlas.identity_reconciliation_reviews;
create trigger identity_reconciliation_reviews_touch
before update on atlas.identity_reconciliation_reviews
for each row execute function atlas.identity_review_touch_v1();

-- Cross-row tenant guard. Uses to_jsonb(NEW) so one trigger function can safely
-- validate optional foreign-key columns across several identity evidence tables.
create or replace function atlas.identity_tenant_guard_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
declare
  v_new jsonb := to_jsonb(new);
  v_subject_id uuid;
  v_related_subject_id uuid;
  v_source_record_id uuid;
  v_claim_id uuid;
  v_review_id uuid;
  v_supersedes_adjudication_id uuid;
begin
  if nullif(v_new->>'subject_id','') is not null then
    v_subject_id := (v_new->>'subject_id')::uuid;
    if not exists (
      select 1 from atlas.identity_subjects s
      where s.id=v_subject_id and s.organization_id=new.organization_id
    ) then
      raise exception 'Identity subject is outside organization scope.' using errcode='23514';
    end if;
  end if;

  if nullif(v_new->>'related_subject_id','') is not null then
    v_related_subject_id := (v_new->>'related_subject_id')::uuid;
    if not exists (
      select 1 from atlas.identity_subjects s
      where s.id=v_related_subject_id and s.organization_id=new.organization_id
    ) then
      raise exception 'Related identity subject is outside organization scope.' using errcode='23514';
    end if;
  end if;

  if nullif(v_new->>'source_record_id','') is not null then
    v_source_record_id := (v_new->>'source_record_id')::uuid;
    if not exists (
      select 1 from atlas.identity_source_records r
      where r.id=v_source_record_id and r.organization_id=new.organization_id
    ) then
      raise exception 'Identity source record is outside organization scope.' using errcode='23514';
    end if;
  end if;

  if nullif(v_new->>'claim_id','') is not null then
    v_claim_id := (v_new->>'claim_id')::uuid;
    if not exists (
      select 1 from atlas.identity_claims c
      where c.id=v_claim_id and c.organization_id=new.organization_id
    ) then
      raise exception 'Identity claim is outside organization scope.' using errcode='23514';
    end if;
  end if;

  if nullif(v_new->>'review_id','') is not null then
    v_review_id := (v_new->>'review_id')::uuid;
    if not exists (
      select 1 from atlas.identity_reconciliation_reviews r
      where r.id=v_review_id and r.organization_id=new.organization_id
    ) then
      raise exception 'Identity review is outside organization scope.' using errcode='23514';
    end if;
  end if;

  if nullif(v_new->>'supersedes_adjudication_id','') is not null then
    v_supersedes_adjudication_id := (v_new->>'supersedes_adjudication_id')::uuid;
    if not exists (
      select 1 from atlas.identity_reconciliation_adjudications a
      where a.id=v_supersedes_adjudication_id and a.organization_id=new.organization_id
    ) then
      raise exception 'Superseded identity adjudication is outside organization scope.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists identity_claims_tenant_guard on atlas.identity_claims;
create trigger identity_claims_tenant_guard
before insert on atlas.identity_claims
for each row execute function atlas.identity_tenant_guard_v1();

drop trigger if exists identity_source_subject_assertions_tenant_guard on atlas.identity_source_subject_assertions;
create trigger identity_source_subject_assertions_tenant_guard
before insert on atlas.identity_source_subject_assertions
for each row execute function atlas.identity_tenant_guard_v1();

drop trigger if exists identity_reconciliation_adjudications_tenant_guard on atlas.identity_reconciliation_adjudications;
create trigger identity_reconciliation_adjudications_tenant_guard
before insert on atlas.identity_reconciliation_adjudications
for each row execute function atlas.identity_tenant_guard_v1();

create or replace function atlas.identity_pair_tenant_guard_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
declare
  v_swap uuid;
begin
  if new.left_subject_id::text > new.right_subject_id::text then
    v_swap := new.left_subject_id;
    new.left_subject_id := new.right_subject_id;
    new.right_subject_id := v_swap;
  end if;

  if not exists (
    select 1 from atlas.identity_subjects s
    where s.id=new.left_subject_id and s.organization_id=new.organization_id
  ) or not exists (
    select 1 from atlas.identity_subjects s
    where s.id=new.right_subject_id and s.organization_id=new.organization_id
  ) then
    raise exception 'Identity subject pair is outside organization scope.' using errcode='23514';
  end if;

  if new.source_record_id is not null and not exists (
    select 1 from atlas.identity_source_records r
    where r.id=new.source_record_id and r.organization_id=new.organization_id
  ) then
    raise exception 'Identity pair source record is outside organization scope.' using errcode='23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists identity_subject_pair_assertions_tenant_guard on atlas.identity_subject_pair_assertions;
create trigger identity_subject_pair_assertions_tenant_guard
before insert on atlas.identity_subject_pair_assertions
for each row execute function atlas.identity_pair_tenant_guard_v1();

create or replace function atlas.identity_review_tenant_guard_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  if new.source_record_id is not null and not exists (
    select 1 from atlas.identity_source_records r
    where r.id=new.source_record_id and r.organization_id=new.organization_id
  ) then
    raise exception 'Identity review source record is outside organization scope.' using errcode='23514';
  end if;

  if new.left_subject_id is not null and not exists (
    select 1 from atlas.identity_subjects s
    where s.id=new.left_subject_id and s.organization_id=new.organization_id
  ) then
    raise exception 'Identity review left subject is outside organization scope.' using errcode='23514';
  end if;

  if new.right_subject_id is not null and not exists (
    select 1 from atlas.identity_subjects s
    where s.id=new.right_subject_id and s.organization_id=new.organization_id
  ) then
    raise exception 'Identity review right subject is outside organization scope.' using errcode='23514';
  end if;

  if new.claim_id is not null and not exists (
    select 1 from atlas.identity_claims c
    where c.id=new.claim_id and c.organization_id=new.organization_id
  ) then
    raise exception 'Identity review claim is outside organization scope.' using errcode='23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists identity_reconciliation_reviews_tenant_guard on atlas.identity_reconciliation_reviews;
create trigger identity_reconciliation_reviews_tenant_guard
before insert or update on atlas.identity_reconciliation_reviews
for each row execute function atlas.identity_review_tenant_guard_v1();

-- Party is a projection, not the underlying ontology.
create or replace view atlas.v_identity_parties_v1
with (security_invoker = true)
as
select
  s.id as subject_id,
  s.organization_id,
  s.state,
  coalesce(p.subject_kind, 'unknown') as party_kind,
  p.display_name,
  coalesce(p.aliases, '[]'::jsonb) as aliases,
  coalesce(p.contact_points, '[]'::jsonb) as contact_points,
  coalesce(p.unresolved_identity, true) as unresolved_identity,
  p.confidence,
  coalesce(p.projection_basis, '{}'::jsonb) as projection_basis,
  s.created_at,
  p.updated_at as projection_updated_at
from atlas.identity_subjects s
left join atlas.identity_subject_projections p on p.subject_id=s.id;

comment on view atlas.v_identity_parties_v1 is
  'Usable Party projection over reconciled identity subjects. The view is not an identity evidence ledger.';

-- RLS and direct-access posture.
alter table atlas.identity_subjects enable row level security;
alter table atlas.identity_source_records enable row level security;
alter table atlas.identity_claims enable row level security;
alter table atlas.identity_source_subject_assertions enable row level security;
alter table atlas.identity_subject_pair_assertions enable row level security;
alter table atlas.identity_reconciliation_reviews enable row level security;
alter table atlas.identity_reconciliation_adjudications enable row level security;
alter table atlas.identity_subject_projections enable row level security;

create policy identity_subjects_member_read on atlas.identity_subjects
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_source_records_member_read on atlas.identity_source_records
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_claims_member_read on atlas.identity_claims
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_source_subject_assertions_member_read on atlas.identity_source_subject_assertions
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_subject_pair_assertions_member_read on atlas.identity_subject_pair_assertions
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_reconciliation_reviews_member_read on atlas.identity_reconciliation_reviews
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_reconciliation_adjudications_member_read on atlas.identity_reconciliation_adjudications
for select to authenticated using (atlas.is_organization_member(organization_id));
create policy identity_subject_projections_member_read on atlas.identity_subject_projections
for select to authenticated using (atlas.is_organization_member(organization_id));

revoke all on table atlas.identity_subjects from public, anon, authenticated;
revoke all on table atlas.identity_source_records from public, anon, authenticated;
revoke all on table atlas.identity_claims from public, anon, authenticated;
revoke all on table atlas.identity_source_subject_assertions from public, anon, authenticated;
revoke all on table atlas.identity_subject_pair_assertions from public, anon, authenticated;
revoke all on table atlas.identity_reconciliation_reviews from public, anon, authenticated;
revoke all on table atlas.identity_reconciliation_adjudications from public, anon, authenticated;
revoke all on table atlas.identity_subject_projections from public, anon, authenticated;
revoke all on table atlas.v_identity_parties_v1 from public, anon, authenticated;

grant select on table atlas.identity_subjects to authenticated;
grant select on table atlas.identity_source_records to authenticated;
grant select on table atlas.identity_claims to authenticated;
grant select on table atlas.identity_source_subject_assertions to authenticated;
grant select on table atlas.identity_subject_pair_assertions to authenticated;
grant select on table atlas.identity_reconciliation_reviews to authenticated;
grant select on table atlas.identity_reconciliation_adjudications to authenticated;
grant select on table atlas.identity_subject_projections to authenticated;
grant select on table atlas.v_identity_parties_v1 to authenticated;

grant all on table atlas.identity_subjects to service_role;
grant all on table atlas.identity_source_records to service_role;
grant all on table atlas.identity_claims to service_role;
grant all on table atlas.identity_source_subject_assertions to service_role;
grant all on table atlas.identity_subject_pair_assertions to service_role;
grant all on table atlas.identity_reconciliation_reviews to service_role;
grant all on table atlas.identity_reconciliation_adjudications to service_role;
grant all on table atlas.identity_subject_projections to service_role;
grant select on table atlas.v_identity_parties_v1 to service_role;

revoke all on function atlas.block_identity_evidence_mutation_v1() from public, anon, authenticated;
revoke all on function atlas.block_identity_subject_delete_v1() from public, anon, authenticated;
revoke all on function atlas.identity_projection_guard_v1() from public, anon, authenticated;
revoke all on function atlas.identity_review_touch_v1() from public, anon, authenticated;
revoke all on function atlas.identity_tenant_guard_v1() from public, anon, authenticated;
revoke all on function atlas.identity_pair_tenant_guard_v1() from public, anon, authenticated;
revoke all on function atlas.identity_review_tenant_guard_v1() from public, anon, authenticated;

grant execute on function atlas.block_identity_evidence_mutation_v1() to service_role;
grant execute on function atlas.block_identity_subject_delete_v1() to service_role;
grant execute on function atlas.identity_projection_guard_v1() to service_role;
grant execute on function atlas.identity_review_touch_v1() to service_role;
grant execute on function atlas.identity_tenant_guard_v1() to service_role;
grant execute on function atlas.identity_pair_tenant_guard_v1() to service_role;
grant execute on function atlas.identity_review_tenant_guard_v1() to service_role;
