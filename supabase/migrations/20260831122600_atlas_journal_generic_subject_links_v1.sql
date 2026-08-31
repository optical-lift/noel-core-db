-- Atlas Journal Generic Subject Links v1
-- Adds a provenance-preserving many-to-many subject graph beside the existing
-- journal_event_index. Existing typed pointer columns remain intact for compatibility.

begin;

create table atlas.journal_event_subjects (
  id uuid primary key default gen_random_uuid(),
  journal_event_id uuid not null references atlas.journal_event_index(id) on delete cascade,
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  relation_kind text not null default 'about',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint journal_event_subjects_domain_not_blank check (btrim(subject_domain) <> ''),
  constraint journal_event_subjects_kind_not_blank check (btrim(subject_kind) <> ''),
  constraint journal_event_subjects_id_not_blank check (btrim(subject_id) <> ''),
  constraint journal_event_subjects_relation_not_blank check (btrim(relation_kind) <> ''),
  constraint journal_event_subjects_identity_key
    unique (journal_event_id, subject_domain, subject_kind, subject_id, relation_kind)
);

comment on table atlas.journal_event_subjects is
  'Generic subject relationships for one canonical Journal event. A link relates an indexed event to any domain subject without copying or replacing the event or its source record.';
comment on column atlas.journal_event_subjects.subject_domain is
  'Owning semantic domain for the related subject; domains add vocabulary but do not change Journal event identity.';
comment on column atlas.journal_event_subjects.relation_kind is
  'How the event relates to the subject, such as about, evidence_for, result_of, actor, or participant. Relation labels do not create causal truth.';
comment on column atlas.journal_event_subjects.provenance is
  'Custody for the relationship itself. Journal subject linkage is separate from provenance of the canonical event.';

create index journal_event_subjects_event_idx
  on atlas.journal_event_subjects(journal_event_id, created_at, id);

create index journal_event_subjects_subject_idx
  on atlas.journal_event_subjects(subject_domain, subject_kind, subject_id, journal_event_id);

alter table atlas.journal_event_subjects enable row level security;

create policy journal_event_subjects_parent_event_read
on atlas.journal_event_subjects
for select
to authenticated
using (atlas.can_read_journal_event_v1(journal_event_id));

grant select on atlas.journal_event_subjects to authenticated;
grant select, insert, update, delete on atlas.journal_event_subjects to service_role;

-- Preserve the old Journal pointer vocabulary as explicit compatibility links.
-- These labels identify the inherited Atlas relation only; they do not reinterpret
-- the underlying domain object.
insert into atlas.journal_event_subjects (
  journal_event_id,
  subject_domain,
  subject_kind,
  subject_id,
  relation_kind,
  provenance
)
select
  j.id,
  'atlas',
  'task',
  j.task_id::text,
  'legacy_pointer',
  jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'task_id')
from atlas.journal_event_index j
where j.task_id is not null
on conflict do nothing;

insert into atlas.journal_event_subjects (
  journal_event_id,
  subject_domain,
  subject_kind,
  subject_id,
  relation_kind,
  provenance
)
select
  j.id,
  'atlas',
  'object',
  j.object_id::text,
  'legacy_pointer',
  jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'object_id')
from atlas.journal_event_index j
where j.object_id is not null
on conflict do nothing;

insert into atlas.journal_event_subjects (
  journal_event_id,
  subject_domain,
  subject_kind,
  subject_id,
  relation_kind,
  provenance
)
select
  j.id,
  'atlas',
  'crop_cycle',
  j.crop_cycle_id::text,
  'legacy_pointer',
  jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'crop_cycle_id')
from atlas.journal_event_index j
where j.crop_cycle_id is not null
on conflict do nothing;

insert into atlas.journal_event_subjects (
  journal_event_id,
  subject_domain,
  subject_kind,
  subject_id,
  relation_kind,
  provenance
)
select
  j.id,
  'atlas',
  'project',
  j.project_id::text,
  'legacy_pointer',
  jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'project_id')
from atlas.journal_event_index j
where j.project_id is not null
on conflict do nothing;

insert into atlas.journal_event_subjects (
  journal_event_id,
  subject_domain,
  subject_kind,
  subject_id,
  relation_kind,
  provenance
)
select
  j.id,
  'atlas',
  'trail_binding',
  j.trail_binding_id::text,
  'legacy_pointer',
  jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'trail_binding_id')
from atlas.journal_event_index j
where j.trail_binding_id is not null
on conflict do nothing;

create or replace function atlas.mirror_legacy_journal_subjects_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  if new.task_id is not null then
    insert into atlas.journal_event_subjects (
      journal_event_id, subject_domain, subject_kind, subject_id, relation_kind, provenance
    ) values (
      new.id, 'atlas', 'task', new.task_id::text, 'legacy_pointer',
      jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'task_id')
    ) on conflict do nothing;
  end if;

  if new.object_id is not null then
    insert into atlas.journal_event_subjects (
      journal_event_id, subject_domain, subject_kind, subject_id, relation_kind, provenance
    ) values (
      new.id, 'atlas', 'object', new.object_id::text, 'legacy_pointer',
      jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'object_id')
    ) on conflict do nothing;
  end if;

  if new.crop_cycle_id is not null then
    insert into atlas.journal_event_subjects (
      journal_event_id, subject_domain, subject_kind, subject_id, relation_kind, provenance
    ) values (
      new.id, 'atlas', 'crop_cycle', new.crop_cycle_id::text, 'legacy_pointer',
      jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'crop_cycle_id')
    ) on conflict do nothing;
  end if;

  if new.project_id is not null then
    insert into atlas.journal_event_subjects (
      journal_event_id, subject_domain, subject_kind, subject_id, relation_kind, provenance
    ) values (
      new.id, 'atlas', 'project', new.project_id::text, 'legacy_pointer',
      jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'project_id')
    ) on conflict do nothing;
  end if;

  if new.trail_binding_id is not null then
    insert into atlas.journal_event_subjects (
      journal_event_id, subject_domain, subject_kind, subject_id, relation_kind, provenance
    ) values (
      new.id, 'atlas', 'trail_binding', new.trail_binding_id::text, 'legacy_pointer',
      jsonb_build_object('adapter', 'journal_legacy_pointer_v1', 'column', 'trail_binding_id')
    ) on conflict do nothing;
  end if;

  return new;
end;
$$;

revoke all on function atlas.mirror_legacy_journal_subjects_v1() from public, anon, authenticated;
grant execute on function atlas.mirror_legacy_journal_subjects_v1() to service_role;

create trigger journal_event_index_mirror_generic_subjects_v1
after insert on atlas.journal_event_index
for each row execute function atlas.mirror_legacy_journal_subjects_v1();

commit;
