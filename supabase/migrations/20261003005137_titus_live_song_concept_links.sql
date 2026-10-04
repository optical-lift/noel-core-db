alter table titus.slot_song_scopes add column if not exists song_object_id bigint;
alter table titus.teacher_source_song_scopes add column if not exists song_object_id bigint;
alter table titus.teacher_term_song_scopes add column if not exists song_object_id bigint;

update titus.slot_song_scopes s
set song_object_id = so.song_object_id
from draft.song_objects so
where s.song_object_id is null
  and s.scope_source_schema = 'draft'
  and s.scope_source_table = 'song_objects'
  and s.scope_target_key ~ '^[0-9]+$'
  and so.song_object_id = s.scope_target_key::bigint;

update titus.teacher_source_song_scopes s
set song_object_id = so.song_object_id
from draft.song_objects so
where s.song_object_id is null
  and s.scope_source_schema = 'draft'
  and s.scope_source_table = 'song_objects'
  and s.scope_target_key ~ '^[0-9]+$'
  and so.song_object_id = s.scope_target_key::bigint;

update titus.teacher_term_song_scopes s
set song_object_id = so.song_object_id
from draft.song_objects so
where s.song_object_id is null
  and s.scope_source_schema = 'draft'
  and s.scope_source_table = 'song_objects'
  and s.scope_target_key ~ '^[0-9]+$'
  and so.song_object_id = s.scope_target_key::bigint;

do $$
begin
  if exists (select 1 from titus.slot_song_scopes where song_object_id is null)
     or exists (select 1 from titus.teacher_source_song_scopes where song_object_id is null)
     or exists (select 1 from titus.teacher_term_song_scopes where song_object_id is null) then
    raise exception 'Cannot enforce live Song links: one or more existing scope rows do not resolve to draft.song_objects.song_object_id';
  end if;
end $$;

alter table titus.slot_song_scopes alter column song_object_id set not null;
alter table titus.teacher_source_song_scopes alter column song_object_id set not null;
alter table titus.teacher_term_song_scopes alter column song_object_id set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='slot_song_scopes_song_object_id_fkey' and connamespace='titus'::regnamespace) then
    alter table titus.slot_song_scopes add constraint slot_song_scopes_song_object_id_fkey foreign key (song_object_id) references draft.song_objects(song_object_id) on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='teacher_source_song_scopes_song_object_id_fkey' and connamespace='titus'::regnamespace) then
    alter table titus.teacher_source_song_scopes add constraint teacher_source_song_scopes_song_object_id_fkey foreign key (song_object_id) references draft.song_objects(song_object_id) on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='teacher_term_song_scopes_song_object_id_fkey' and connamespace='titus'::regnamespace) then
    alter table titus.teacher_term_song_scopes add constraint teacher_term_song_scopes_song_object_id_fkey foreign key (song_object_id) references draft.song_objects(song_object_id) on update cascade on delete restrict;
  end if;
end $$;

create or replace function titus.enforce_live_song_object_scope()
returns trigger
language plpgsql
set search_path = titus, draft, pg_temp
as $$
declare
  live_label text;
begin
  select object_name into live_label
  from draft.song_objects
  where song_object_id = new.song_object_id;

  if live_label is null then
    raise exception 'Song object % does not exist', new.song_object_id;
  end if;

  new.scope_source_schema := 'draft';
  new.scope_source_table := 'song_objects';
  new.scope_target_key := new.song_object_id::text;

  if tg_op = 'INSERT' or new.song_object_id is distinct from old.song_object_id then
    new.scope_label_snapshot := live_label;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_slot_song_scopes_live_target on titus.slot_song_scopes;
create trigger trg_slot_song_scopes_live_target
before insert or update on titus.slot_song_scopes
for each row execute function titus.enforce_live_song_object_scope();

drop trigger if exists trg_teacher_source_song_scopes_live_target on titus.teacher_source_song_scopes;
create trigger trg_teacher_source_song_scopes_live_target
before insert or update on titus.teacher_source_song_scopes
for each row execute function titus.enforce_live_song_object_scope();

drop trigger if exists trg_teacher_term_song_scopes_live_target on titus.teacher_term_song_scopes;
create trigger trg_teacher_term_song_scopes_live_target
before insert or update on titus.teacher_term_song_scopes
for each row execute function titus.enforce_live_song_object_scope();

create index if not exists idx_slot_song_scopes_song_object_id on titus.slot_song_scopes(song_object_id);
create index if not exists idx_teacher_source_song_scopes_song_object_id on titus.teacher_source_song_scopes(song_object_id);
create index if not exists idx_teacher_term_song_scopes_song_object_id on titus.teacher_term_song_scopes(song_object_id);

comment on column titus.slot_song_scopes.song_object_id is 'Authoritative live foreign key to the current Song concept in draft.song_objects. Titus must resolve present Song meaning through this key, not through snapshots.';
comment on column titus.teacher_source_song_scopes.song_object_id is 'Authoritative live foreign key from a teacher teaching/source unit to the current Song concept in draft.song_objects.';
comment on column titus.teacher_term_song_scopes.song_object_id is 'Authoritative live foreign key from a teacher term/definition to the current Song concept in draft.song_objects.';
comment on column titus.slot_song_scopes.scope_label_snapshot is 'Audit-only label captured when the link was made or retargeted. Never authoritative for current Song meaning.';
comment on column titus.teacher_source_song_scopes.scope_label_snapshot is 'Audit-only label captured when the link was made or retargeted. Never authoritative for current Song meaning.';
comment on column titus.teacher_term_song_scopes.scope_label_snapshot is 'Audit-only label captured when the link was made or retargeted. Never authoritative for current Song meaning.';

create or replace view titus.song_concept_links_live as
select
  'lesson'::text as target_kind,
  s.slot_song_scope_id as link_id,
  b.canon_brief_id::text as target_id,
  (b.course_slug || ':' || b.slot_key)::text as target_key,
  coalesce(b.brief_title, b.slot_key)::text as target_label,
  s.song_object_id,
  so.object_name as song_current_name,
  so.object_type as song_current_type,
  so.object_status as song_current_status,
  so.one_sentence_claim as song_current_claim,
  so.provisional_function_lane as song_current_function_lane,
  so.updated_at as song_current_updated_at,
  s.scope_role as link_relation,
  s.scope_note as link_note,
  s.scope_label_snapshot as linked_label_snapshot,
  s.confidence,
  s.review_status,
  s.created_at as linked_at,
  s.updated_at as link_updated_at
from titus.slot_song_scopes s
join titus.slot_canon_briefs b on b.canon_brief_id = s.canon_brief_id
join draft.song_objects so on so.song_object_id = s.song_object_id
union all
select
  'teaching'::text,
  s.teacher_source_song_scope_id,
  u.source_unit_id::text,
  u.unit_key,
  coalesce(u.unit_title, u.unit_key),
  s.song_object_id,
  so.object_name,
  so.object_type,
  so.object_status,
  so.one_sentence_claim,
  so.provisional_function_lane,
  so.updated_at,
  s.scope_relation,
  s.scope_note,
  s.scope_label_snapshot,
  s.confidence,
  s.review_status,
  s.created_at,
  s.updated_at
from titus.teacher_source_song_scopes s
join titus.teacher_source_units u on u.source_unit_id = s.source_unit_id
join draft.song_objects so on so.song_object_id = s.song_object_id
union all
select
  'definition'::text,
  s.teacher_term_song_scope_id,
  t.teacher_term_id::text,
  t.normalized_term,
  t.term,
  s.song_object_id,
  so.object_name,
  so.object_type,
  so.object_status,
  so.one_sentence_claim,
  so.provisional_function_lane,
  so.updated_at,
  s.scope_relation,
  s.rationale,
  s.scope_label_snapshot,
  s.confidence,
  s.review_status,
  s.created_at,
  s.updated_at
from titus.teacher_term_song_scopes s
join titus.teacher_terms t on t.teacher_term_id = s.teacher_term_id
join draft.song_objects so on so.song_object_id = s.song_object_id;

comment on view titus.song_concept_links_live is 'Live resolution of Titus lesson, teaching/source-unit, and teacher-definition links to current draft.song_objects values. Semantic fields are joined at read time; linked_label_snapshot is audit provenance only.';