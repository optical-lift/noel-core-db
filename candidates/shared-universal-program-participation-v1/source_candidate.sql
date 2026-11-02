-- SOURCE CANDIDATE / NO PRODUCTION DDL OR INVITATIONS AUTHORIZED.
-- Atlas universal Program relationships, shared boundary for native Titus.
-- Requires shared_ custody review, production-schema clone and signed tests.
-- This is relationship custody, NOT a second Program/course engine.
-- No service_role or authenticated privileges; no invitation writer exists.
--
-- 1) The original is always the immutable Atlas authored Program or native
-- Titus Program, never a second copy. A specific approved/source version is
-- frozen for a single invitation and for the resulting participation.
-- 2) "Offered" does not confer study, teaching, authorship or review rights.
-- 3) Participation acceptance itself is NOT a teaching/authoring grant.

create table atlas.universal_program_invitations_v1 (
  invitation_id uuid primary key default gen_random_uuid(),
  invitee_person_id uuid not null references atlas.people(id) on delete restrict,
  invited_by_person_id uuid not null references atlas.people(id) on delete restrict,
  atlas_program_id uuid references atlas.personal_training_programs(id) on delete restrict,
  atlas_program_version_id uuid references atlas.personal_training_program_versions(id) on delete restrict,
  titus_program_id uuid references titus.programs(program_id) on delete restrict,
  titus_curriculum_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete restrict,
  state text not null default 'pending_acceptance' check
    (state in ('pending_acceptance','accepted','declined','revoked','expired')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  authority_basis jsonb not null check (jsonb_typeof(authority_basis)='object'),
  authority_proof_hash text not null check (authority_proof_hash ~ '^[0-9a-f]{64}$'),
  request_key text not null check (length(btrim(request_key)) between 12 and 160),
  created_at timestamptz not null default now(),
  constraint universal_program_invitation_exact_origin_v1 check (
    (atlas_program_id is not null and atlas_program_version_id is not null
     and titus_program_id is null and titus_curriculum_version_id is null)
    or
    (atlas_program_id is null and atlas_program_version_id is null
     and titus_program_id is not null and titus_curriculum_version_id is not null)
  ),
  constraint universal_program_invitation_time_v1 check (expires_at > issued_at),
  constraint universal_program_invitation_response_v1 check (
    (state='pending_acceptance' and responded_at is null) or
    (state<>'pending_acceptance' and responded_at is not null)
  )
);

-- These partial constraints prevent accidental duplicate pending invitations
-- for the same Person and original. They do NOT create permission to issue any.
create unique index universal_program_invite_atlas_pending_once_v1
 on atlas.universal_program_invitations_v1(invitee_person_id,atlas_program_id)
 where state='pending_acceptance' and atlas_program_id is not null;
create unique index universal_program_invite_titus_pending_once_v1
 on atlas.universal_program_invitations_v1(invitee_person_id,titus_program_id)
 where state='pending_acceptance' and titus_program_id is not null;
create unique index universal_program_invite_issuer_request_v1
 on atlas.universal_program_invitations_v1(invited_by_person_id,request_key);

-- Exact original-version continuity is independently checked here, rather
-- than relying on two individually valid but unrelated foreign keys.
-- This guard does NOT attest issuer authority, content-license or acceptance.
create function atlas.universal_program_invitation_origin_guard_v1()
returns trigger language plpgsql set search_path=pg_catalog as $guard$
begin
  if tg_op='UPDATE' then
    if (
    old.invitee_person_id, old.invited_by_person_id,
    old.atlas_program_id, old.atlas_program_version_id,
    old.titus_program_id, old.titus_curriculum_version_id,
    old.issued_at, old.expires_at, old.authority_basis,
    old.authority_proof_hash, old.request_key
  ) is distinct from (
    new.invitee_person_id, new.invited_by_person_id,
    new.atlas_program_id, new.atlas_program_version_id,
    new.titus_program_id, new.titus_curriculum_version_id,
    new.issued_at, new.expires_at, new.authority_basis,
    new.authority_proof_hash, new.request_key
  ) then
    raise exception 'Invitation original and provenance immutable'
      using errcode='23514';
    end if;
  end if;
  if new.atlas_program_id is not null and not exists (
    select 1 from atlas.personal_training_program_versions v
    where v.id=new.atlas_program_version_id
      and v.program_id=new.atlas_program_id
      and v.approved_at is not null
  ) then
    raise exception 'Program version unavailable' using errcode='23514';
  end if;
  if new.titus_program_id is not null and not exists (
    select 1 from titus.curriculum_versions v
    where v.curriculum_version_id=new.titus_curriculum_version_id
      and v.program_id=new.titus_program_id
  ) then
    raise exception 'Program version unavailable' using errcode='23514';
  end if;
  return new;
end;
$guard$;
create trigger universal_program_invitation_origin_guard_v1
 before insert or update
 on atlas.universal_program_invitations_v1
 for each row execute function atlas.universal_program_invitation_origin_guard_v1();

-- Consent/participation is a distinct original and is neither automatic
-- on invitation creation nor a replacement for the approved Program version.
create table atlas.universal_program_participations_v1 (
  participation_id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null unique
    references atlas.universal_program_invitations_v1(invitation_id) on delete restrict,
  participant_person_id uuid not null references atlas.people(id) on delete restrict,
  consented_at timestamptz not null,
  consent_proof_hash text not null check (consent_proof_hash ~ '^[0-9a-f]{64}$'),
  state text not null default 'active' check (state in ('active','withdrawn','closed')),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint universal_program_participation_state_v1 check (
    (state='active' and ended_at is null) or
    (state<>'active' and ended_at is not null)
  )
);

-- Reject fabricated participation and an invitation for another Person.
-- Issuer-side authority and actual invitee consent still require separately
-- governed signed writers. No caller can insert this table in this candidate.
create function atlas.universal_program_participation_guard_v1()
returns trigger language plpgsql set search_path=pg_catalog as $guard$
begin
  if tg_op='UPDATE' then
    if (
    old.invitation_id, old.participant_person_id, old.consented_at,
    old.consent_proof_hash, old.created_at
  ) is distinct from (
    new.invitation_id, new.participant_person_id, new.consented_at,
    new.consent_proof_hash, new.created_at
  ) then
    raise exception 'Participant consent original immutable'
      using errcode='23514';
    end if;
  end if;
  if not exists (
    select 1 from atlas.universal_program_invitations_v1 i
    where i.invitation_id=new.invitation_id
      and i.invitee_person_id=new.participant_person_id
      and i.state='accepted'
      and i.responded_at is not null
      and i.responded_at <= new.consented_at
      and i.responded_at <= i.expires_at
  ) then
    raise exception 'Accepted source-bound invitation required' using errcode='23514';
  end if;
  return new;
end;
$guard$;
create trigger universal_program_participation_guard_v1
 before insert or update
 on atlas.universal_program_participations_v1
 for each row execute function atlas.universal_program_participation_guard_v1();

alter table atlas.universal_program_invitations_v1 enable row level security;
alter table atlas.universal_program_invitations_v1 force row level security;
alter table atlas.universal_program_participations_v1 enable row level security;
alter table atlas.universal_program_participations_v1 force row level security;

-- Intentionally no RLS policies, self APIs, INSERT/UPDATE rights, REST
-- exposure, source text, or auto-granted curriculum role in this package.
revoke all on atlas.universal_program_invitations_v1
  from public, anon, authenticated, service_role;
revoke all on atlas.universal_program_participations_v1
  from public, anon, authenticated, service_role;
revoke all on function atlas.universal_program_invitation_origin_guard_v1()
  from public, anon, authenticated, service_role;
revoke all on function atlas.universal_program_participation_guard_v1()
  from public, anon, authenticated, service_role;
