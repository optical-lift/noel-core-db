-- Atlas Core evidence-first identity reconciliation v1
-- Reality Foundation #788
--
-- One atomic post-fence Atlas migration owned by noel-core-db.
-- Source/provider/legacy records remain evidence. Thin identity subjects are
-- reconciliation anchors. Party/Person/Organization/Place remain projections.
-- This migration deliberately does NOT bulk-copy buyer reconstruction or
-- local_intel rows into a canonical directory.

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
    'reject_split_correction',
    'defer_unresolved',
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

-- Guarded Core identity reconciliation contracts.

create or replace function atlas.require_identity_steward_v1(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_membership atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_membership
  from atlas.organization_memberships om
  where om.organization_id=p_organization_id
    and om.user_id=auth.uid()
    and om.active=true
  order by case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end, om.created_at
  limit 1;

  if v_membership.id is null or v_membership.role not in ('owner','consultant') then
    raise exception 'Identity stewardship requires Owner or Consultant authority.' using errcode='42501';
  end if;

  return v_membership.id;
end;
$function$;

create or replace function atlas.identity_party_projection_v1(p_subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_subject atlas.identity_subjects%rowtype;
  v_projection atlas.identity_subject_projections%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_subject from atlas.identity_subjects where id=p_subject_id;
  if v_subject.id is null then
    raise exception 'Identity subject not found.' using errcode='P0002';
  end if;
  if not atlas.is_organization_member(v_subject.organization_id) then
    raise exception 'Identity subject is outside your organization.' using errcode='42501';
  end if;

  select * into v_projection from atlas.identity_subject_projections where subject_id=v_subject.id;

  return jsonb_build_object(
    'contractVersion','identity_party_projection_v1',
    'subjectId',v_subject.id,
    'organizationId',v_subject.organization_id,
    'subjectState',v_subject.state,
    'partyKind',coalesce(v_projection.subject_kind,'unknown'),
    'displayName',v_projection.display_name,
    'aliases',coalesce(v_projection.aliases,'[]'::jsonb),
    'contactPoints',coalesce(v_projection.contact_points,'[]'::jsonb),
    'unresolvedIdentity',coalesce(v_projection.unresolved_identity,true),
    'confidence',v_projection.confidence,
    'projectionBasis',coalesce(v_projection.projection_basis,'{}'::jsonb),
    'projectionUpdatedAt',v_projection.updated_at
  );
end;
$function$;

create or replace function atlas.identity_subject_provenance_v1(p_subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_subject atlas.identity_subjects%rowtype;
  v_membership_id uuid;
  v_claims jsonb;
  v_source_bindings jsonb;
  v_pair_assertions jsonb;
  v_adjudications jsonb;
  v_reviews jsonb;
begin
  select * into v_subject from atlas.identity_subjects where id=p_subject_id;
  if v_subject.id is null then raise exception 'Identity subject not found.' using errcode='P0002'; end if;
  v_membership_id := atlas.require_identity_steward_v1(v_subject.organization_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,'claimKind',c.claim_kind,'claimValue',c.claim_value,
    'confidence',c.confidence,'effectiveFrom',c.effective_from,'effectiveTo',c.effective_to,
    'basis',c.basis,'sourceRecordId',c.source_record_id,'createdAt',c.created_at
  ) order by c.created_at,c.id),'[]'::jsonb)
  into v_claims
  from atlas.identity_claims c
  where c.organization_id=v_subject.organization_id and c.subject_id=v_subject.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'assertionId',a.id,'sourceRecordId',a.source_record_id,'sourceSystemKey',r.source_system_key,
    'sourceRecordKind',r.source_record_kind,'sourceRecordKey',r.source_record_key,
    'sourceAuthority',r.source_authority,'sourceObservedAt',r.source_observed_at,
    'assertionKind',a.assertion_kind,'confidence',a.confidence,'basis',a.basis,'createdAt',a.created_at
  ) order by a.created_at,a.id),'[]'::jsonb)
  into v_source_bindings
  from atlas.identity_source_subject_assertions a
  join atlas.identity_source_records r on r.id=a.source_record_id
  where a.organization_id=v_subject.organization_id and a.subject_id=v_subject.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'assertionId',p.id,'leftSubjectId',p.left_subject_id,'rightSubjectId',p.right_subject_id,
    'assertionKind',p.assertion_kind,'confidence',p.confidence,'sourceRecordId',p.source_record_id,
    'basis',p.basis,'createdAt',p.created_at
  ) order by p.created_at,p.id),'[]'::jsonb)
  into v_pair_assertions
  from atlas.identity_subject_pair_assertions p
  where p.organization_id=v_subject.organization_id
    and (p.left_subject_id=v_subject.id or p.right_subject_id=v_subject.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'adjudicationId',a.id,'reviewId',a.review_id,'decisionKind',a.decision_kind,
    'sourceRecordId',a.source_record_id,'subjectId',a.subject_id,'relatedSubjectId',a.related_subject_id,
    'claimId',a.claim_id,'supersedesAdjudicationId',a.supersedes_adjudication_id,
    'basis',a.basis,'adjudicatedByLabel',a.adjudicated_by_label,'createdAt',a.created_at
  ) order by a.created_at,a.id),'[]'::jsonb)
  into v_adjudications
  from atlas.identity_reconciliation_adjudications a
  where a.organization_id=v_subject.organization_id
    and (a.subject_id=v_subject.id or a.related_subject_id=v_subject.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'reviewId',r.id,'reviewKind',r.review_kind,'sourceRecordId',r.source_record_id,
    'leftSubjectId',r.left_subject_id,'rightSubjectId',r.right_subject_id,'claimId',r.claim_id,
    'status',r.status,'priority',r.priority,'candidateData',r.candidate_data,
    'resolutionSummary',r.resolution_summary,'createdAt',r.created_at,'resolvedAt',r.resolved_at
  ) order by r.created_at,r.id),'[]'::jsonb)
  into v_reviews
  from atlas.identity_reconciliation_reviews r
  where r.organization_id=v_subject.organization_id
    and (r.left_subject_id=v_subject.id or r.right_subject_id=v_subject.id
      or r.claim_id in (select c.id from atlas.identity_claims c where c.subject_id=v_subject.id));

  return jsonb_build_object(
    'contractVersion','identity_subject_provenance_v1',
    'subjectId',v_subject.id,
    'organizationId',v_subject.organization_id,
    'reviewerMembershipId',v_membership_id,
    'party',atlas.identity_party_projection_v1(v_subject.id),
    'claims',v_claims,
    'sourceBindings',v_source_bindings,
    'subjectPairAssertions',v_pair_assertions,
    'adjudications',v_adjudications,
    'reviews',v_reviews
  );
end;
$function$;

create or replace function atlas.identity_review_queue_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_membership_id uuid;
  v_items jsonb;
begin
  v_membership_id := atlas.require_identity_steward_v1(p_organization_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'reviewId',r.id,
    'reviewKind',r.review_kind,
    'sourceRecordId',r.source_record_id,
    'leftSubjectId',r.left_subject_id,
    'rightSubjectId',r.right_subject_id,
    'claimId',r.claim_id,
    'priority',r.priority,
    'candidateData',r.candidate_data,
    'openedBy',r.opened_by,
    'createdAt',r.created_at,
    'reviewChoices',case
      when r.review_kind in ('source_binding','subject_equivalence') then jsonb_build_array('same','different','not_enough_evidence')
      when r.review_kind='split_correction' then jsonb_build_array('split','keep_together','not_enough_evidence')
      else jsonb_build_array('accept','reject','not_enough_evidence')
    end
  ) order by
    case r.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
    r.created_at,r.id
  ),'[]'::jsonb)
  into v_items
  from atlas.identity_reconciliation_reviews r
  where r.organization_id=p_organization_id and r.status='open';

  return jsonb_build_object(
    'contractVersion','identity_review_queue_v1',
    'organizationId',p_organization_id,
    'reviewerMembershipId',v_membership_id,
    'state',case when jsonb_array_length(v_items)=0 then 'clear' else 'review_required' end,
    'pendingCount',jsonb_array_length(v_items),
    'items',v_items
  );
end;
$function$;

create or replace function atlas.identity_adjudicate_review_v1(
  p_review_id uuid,
  p_decision text,
  p_basis text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_review atlas.identity_reconciliation_reviews%rowtype;
  v_membership_id uuid;
  v_decision text := lower(btrim(coalesce(p_decision,'')));
  v_basis text := nullif(btrim(coalesce(p_basis,'')),'');
  v_user_id uuid := auth.uid();
  v_reviewer_label text;
  v_decision_kind text;
  v_assertion_id uuid;
  v_adjudication_id uuid;
  v_evidence jsonb;
  v_resolves_review boolean := true;
begin
  if v_user_id is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if v_decision not in ('same','different','not_enough_evidence','split','keep_together','accept','reject') then
    raise exception 'Unsupported identity review decision.' using errcode='22023';
  end if;
  if v_basis is null then raise exception 'A reviewer basis is required.' using errcode='22023'; end if;
  if length(v_basis)>4000 then raise exception 'Reviewer basis is too long.' using errcode='22023'; end if;

  select * into v_review from atlas.identity_reconciliation_reviews where id=p_review_id for update;
  if v_review.id is null then raise exception 'Identity review item not found.' using errcode='P0002'; end if;
  v_membership_id := atlas.require_identity_steward_v1(v_review.organization_id);
  if v_review.status<>'open' then raise exception 'Identity review item is no longer pending.' using errcode='22023'; end if;

  if v_review.review_kind in ('source_binding','subject_equivalence')
     and v_decision not in ('same','different','not_enough_evidence') then
    raise exception 'Choose Same, Different, or Not enough evidence for this identity review.' using errcode='22023';
  elsif v_review.review_kind='split_correction'
     and v_decision not in ('split','keep_together','not_enough_evidence') then
    raise exception 'Choose Split, Keep together, or Not enough evidence for this correction review.' using errcode='22023';
  elsif v_review.review_kind not in ('source_binding','subject_equivalence','split_correction')
     and v_decision not in ('accept','reject','not_enough_evidence') then
    raise exception 'Choose Accept, Reject, or Not enough evidence for this review.' using errcode='22023';
  end if;

  select coalesce(nullif(btrim(up.display_name),''),v_user_id::text)
  into v_reviewer_label from atlas.user_profiles up where up.user_id=v_user_id;
  v_reviewer_label := coalesce(v_reviewer_label,v_user_id::text);

  v_evidence := jsonb_build_object(
    'reviewKind',v_review.review_kind,
    'sourceRecordId',v_review.source_record_id,
    'leftSubjectId',v_review.left_subject_id,
    'rightSubjectId',v_review.right_subject_id,
    'claimId',v_review.claim_id,
    'candidateData',v_review.candidate_data
  );

  if v_decision='not_enough_evidence' then
    v_decision_kind := 'defer_unresolved';
    v_resolves_review := false;
  elsif v_review.review_kind='source_binding' then
    if v_review.source_record_id is null or v_review.left_subject_id is null then
      raise exception 'Source-binding review is missing source/subject evidence.' using errcode='23514';
    end if;
    insert into atlas.identity_source_subject_assertions(
      organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
    ) values (
      v_review.organization_id,v_review.source_record_id,v_review.left_subject_id,
      case when v_decision='same' then 'supports' else 'non_match' end,
      1,v_basis,'identity-review:'||v_review.id::text||':'||v_decision,v_user_id
    ) returning id into v_assertion_id;
    v_decision_kind := case when v_decision='same' then 'accept_source_binding' else 'reject_source_binding' end;
  elsif v_review.review_kind='subject_equivalence' then
    if v_review.left_subject_id is null or v_review.right_subject_id is null then
      raise exception 'Subject-equivalence review is missing subject evidence.' using errcode='23514';
    end if;
    insert into atlas.identity_subject_pair_assertions(
      organization_id,left_subject_id,right_subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
    ) values (
      v_review.organization_id,v_review.left_subject_id,v_review.right_subject_id,
      case when v_decision='same' then 'equivalent' else 'distinct' end,
      1,v_basis,'identity-review:'||v_review.id::text||':'||v_decision,v_user_id
    ) returning id into v_assertion_id;
    v_decision_kind := case when v_decision='same' then 'subjects_equivalent' else 'subjects_distinct' end;
  elsif v_review.review_kind in ('classification','claim_conflict') then
    if v_review.claim_id is null then raise exception 'Claim review is missing claim evidence.' using errcode='23514'; end if;
    v_decision_kind := case when v_decision='accept' then 'accept_claim' else 'reject_claim' end;
  elsif v_review.review_kind='split_correction' then
    if v_review.left_subject_id is null or v_review.right_subject_id is null then
      raise exception 'Split-correction review is missing subject evidence.' using errcode='23514';
    end if;
    if v_decision='split' then
      insert into atlas.identity_subject_pair_assertions(
        organization_id,left_subject_id,right_subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
      ) values (
        v_review.organization_id,v_review.left_subject_id,v_review.right_subject_id,
        'distinct',1,v_basis,'identity-review:'||v_review.id::text||':'||v_decision,v_user_id
      ) returning id into v_assertion_id;
      v_decision_kind := 'split_correction';
    else
      v_decision_kind := 'reject_split_correction';
    end if;
  else
    v_decision_kind := case when v_decision='accept' then 'accept_claim' else 'reject_claim' end;
  end if;

  insert into atlas.identity_reconciliation_adjudications(
    organization_id,review_id,decision_kind,source_record_id,subject_id,related_subject_id,claim_id,
    evidence_snapshot,basis,adjudicated_by_user_id,adjudicated_by_label
  ) values (
    v_review.organization_id,v_review.id,v_decision_kind,v_review.source_record_id,v_review.left_subject_id,
    v_review.right_subject_id,v_review.claim_id,
    v_evidence || jsonb_build_object('decision',v_decision,'resolvedReview',v_resolves_review),
    v_basis,v_user_id,v_reviewer_label
  ) returning id into v_adjudication_id;

  if v_resolves_review then
    update atlas.identity_reconciliation_reviews
    set status='resolved',resolution_summary=v_decision||': '||v_basis
    where id=v_review.id;
  else
    update atlas.identity_reconciliation_reviews
    set resolution_summary='Still unresolved: '||v_basis
    where id=v_review.id;
  end if;

  return jsonb_build_object(
    'contractVersion','identity_adjudicate_review_v1',
    'reviewId',v_review.id,
    'organizationId',v_review.organization_id,
    'reviewerMembershipId',v_membership_id,
    'decision',v_decision,
    'decisionKind',v_decision_kind,
    'reviewState',case when v_resolves_review then 'resolved' else 'open' end,
    'assertionId',v_assertion_id,
    'adjudicationId',v_adjudication_id,
    'canonicalPartyRowCreated',false
  );
end;
$function$;

revoke all on function atlas.require_identity_steward_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_party_projection_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_subject_provenance_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_review_queue_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_adjudicate_review_v1(uuid,text,text) from public,anon,authenticated;

grant execute on function atlas.identity_party_projection_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_subject_provenance_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_review_queue_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_adjudicate_review_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.require_identity_steward_v1(uuid) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,service_execute_expected,
  security_definer_expected,caller_count,policy_reference_count,evidence
) values
(
  'atlas.identity_party_projection_v1(uuid)','app_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_party_projection_v1',
    'purpose','Read the ordinary Party projection over a reconciled identity subject.',
    'authorizationBoundary','Requires authenticated organization membership; exposes projection only, not identity custody internals.',
    'partyIsProjection',true
  )
),
(
  'atlas.identity_subject_provenance_v1(uuid)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_subject_provenance_v1',
    'purpose','Inspect identity evidence, assertions, reviews and adjudications for one subject.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority.',
    'rawMutationExposed',false
  )
),
(
  'atlas.identity_review_queue_v1(uuid)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_review_queue_v1',
    'purpose','Read unresolved Core identity reconciliation work for one Atlas organization.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority.',
    'threeWayReview',true,
    'dependsOnLocalIntel',false
  )
),
(
  'atlas.identity_adjudicate_review_v1(uuid, text, text)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_adjudicate_review_v1',
    'purpose','Record one governed identity decision and its append-only assertion/adjudication consequence.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority and re-reads a pending Core review item.',
    'notEnoughEvidenceRemainsOpen',true,
    'canonicalPartyRowCreated',false,
    'dependsOnLocalIntel',false
  )
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  service_execute_expected=excluded.service_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=now();
