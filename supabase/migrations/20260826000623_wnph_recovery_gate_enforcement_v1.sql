-- WNPH Recovery gate enforcement v1
-- Keep Recovery Case identity stable while evolving rationale/plan lives in append-only briefs.
-- State transitions must prove their evidence gates rather than merely matching an allowed pair.

drop index wnph.recovery_cases_supersedes_idx;
alter table wnph.recovery_cases
  rename column case_scope to initial_scope;
alter table wnph.recovery_cases
  drop column why_recover,
  drop column proposed_expression_type,
  drop column priority,
  drop column supersedes_case_id;

create table wnph.recovery_case_briefs (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  scope_note text not null,
  why_recover text,
  proposed_expression_type text,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  supersedes_brief_id uuid references wnph.recovery_case_briefs(id),
  created_at timestamptz not null default now(),
  constraint recovery_case_briefs_scope_nonblank check (btrim(scope_note) <> ''),
  constraint recovery_case_briefs_supersedes_not_self check (supersedes_brief_id is null or supersedes_brief_id <> id)
);

alter table wnph.recovery_case_events add column selection_authorized boolean not null default false;
alter table wnph.recovery_case_events add constraint recovery_case_events_selection_authorized_check check (
  (to_state = 'SELECTED_FOR_RECOVERY' and selection_authorized)
  or (to_state <> 'SELECTED_FOR_RECOVERY' and not selection_authorized)
);

create unique index recovery_case_briefs_one_root_uq on wnph.recovery_case_briefs(recovery_case_id) where supersedes_brief_id is null;
create unique index recovery_case_briefs_one_child_uq on wnph.recovery_case_briefs(supersedes_brief_id) where supersedes_brief_id is not null;
create index recovery_case_briefs_case_idx on wnph.recovery_case_briefs(recovery_case_id);

create unique index source_sufficiency_one_root_uq on wnph.source_sufficiency_assessments(recovery_case_id) where supersedes_assessment_id is null;
create unique index source_sufficiency_one_child_uq on wnph.source_sufficiency_assessments(supersedes_assessment_id) where supersedes_assessment_id is not null;
create unique index rights_determinations_one_root_uq on wnph.rights_determinations(recovery_case_id, jurisdiction) where supersedes_determination_id is null;
create unique index rights_determinations_one_child_uq on wnph.rights_determinations(supersedes_determination_id) where supersedes_determination_id is not null;
create unique index existing_recovery_audits_one_root_uq on wnph.existing_recovery_audits(recovery_case_id) where supersedes_audit_id is null;
create unique index existing_recovery_audits_one_child_uq on wnph.existing_recovery_audits(supersedes_audit_id) where supersedes_audit_id is not null;
create unique index recovery_gap_assessments_one_root_uq on wnph.recovery_gap_assessments(recovery_case_id) where supersedes_assessment_id is null;
create unique index recovery_gap_assessments_one_child_uq on wnph.recovery_gap_assessments(supersedes_assessment_id) where supersedes_assessment_id is not null;

alter table wnph.recovery_case_briefs enable row level security;
revoke all on table wnph.recovery_case_briefs from public, anon, authenticated, service_role;
create trigger recovery_case_briefs_append_only before update or delete on wnph.recovery_case_briefs for each row execute function wnph.reject_append_only_mutation();

create or replace function wnph.validate_recovery_case_event()
returns trigger
language plpgsql
set search_path = 'pg_catalog'
as $$
declare
  p wnph.recovery_case_events%rowtype;
  allowed boolean := false;
  gate_ok boolean := false;
begin
  if new.prior_event_id is null then
    if new.from_state is not null or new.to_state <> 'IDENTITY_ESTABLISHED' or new.event_kind <> 'state_transition' then
      raise exception 'WNPH Recovery custody: first event must establish inherited IDENTITY_ESTABLISHED state';
    end if;
    select exists (
      select 1
      from wnph.recovery_cases c
      join wnph.historical_works w on w.id = c.work_id
      where c.id = new.recovery_case_id
        and w.status = 'established'
        and exists (
          select 1 from wnph.work_identity_adjudications a
          where a.result_work_id = w.id
            and a.result in ('ESTABLISHES_WORK','SAME_WORK')
        )
    ) into gate_ok;
    if not gate_ok then
      raise exception 'WNPH Recovery custody: initial IDENTITY_ESTABLISHED requires an established Work with identity adjudication';
    end if;
    return new;
  end if;

  select * into p from wnph.recovery_case_events where id = new.prior_event_id;
  if not found then raise exception 'WNPH Recovery custody: prior event % does not exist', new.prior_event_id; end if;
  if p.recovery_case_id <> new.recovery_case_id then raise exception 'WNPH Recovery custody: prior event belongs to a different Recovery Case'; end if;
  if new.from_state is distinct from p.to_state then raise exception 'WNPH Recovery custody: from_state % must equal prior to_state %', new.from_state, p.to_state; end if;
  if exists (select 1 from wnph.recovery_case_events e where e.prior_event_id = p.id) then raise exception 'WNPH Recovery custody: event history may not fork'; end if;

  allowed :=
    (new.from_state = 'IDENTITY_ESTABLISHED' and new.to_state = 'SOURCE_RESEARCH') or
    (new.from_state = 'SOURCE_RESEARCH' and new.to_state in ('SOURCE_SUFFICIENT','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_RESEARCH')) or
    (new.from_state = 'SOURCE_SUFFICIENT' and new.to_state = 'RIGHTS_RESEARCH') or
    (new.from_state = 'RIGHTS_RESEARCH' and new.to_state in ('RIGHTS_CLEARED','REJECTED_RIGHTS','DEFERRED_RIGHTS','DEFERRED_RESEARCH')) or
    (new.from_state = 'RIGHTS_CLEARED' and new.to_state = 'RECOVERY_AUDIT') or
    (new.from_state = 'RECOVERY_AUDIT' and new.to_state in ('GAP_ESTABLISHED','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RESEARCH')) or
    (new.from_state = 'GAP_ESTABLISHED' and new.to_state = 'QUALIFICATION_REVIEW') or
    (new.from_state = 'QUALIFICATION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_LOW_VALUE','DEFERRED_RESEARCH')) or
    (new.from_state = 'QUALIFIED' and new.to_state in ('SELECTED_FOR_RECOVERY','DEFERRED_CAPACITY','DEFERRED_LOW_VALUE')) or
    (new.from_state in ('SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH') and new.to_state = 'REOPENED') or
    (new.from_state = 'REOPENED' and new.to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','RIGHTS_RESEARCH','RECOVERY_AUDIT','QUALIFICATION_REVIEW','QUALIFIED'));
  if not allowed then raise exception 'WNPH Recovery custody: forbidden transition % -> %', new.from_state, new.to_state; end if;

  if new.to_state like 'REJECTED_%' and new.event_kind <> 'reject' then raise exception 'WNPH Recovery custody: rejected states require event_kind=reject'; end if;
  if new.to_state like 'DEFERRED_%' and new.event_kind <> 'defer' then raise exception 'WNPH Recovery custody: deferred states require event_kind=defer'; end if;
  if new.to_state = 'REOPENED' and new.event_kind <> 'reopen' then raise exception 'WNPH Recovery custody: REOPENED requires event_kind=reopen'; end if;
  if new.to_state = 'SELECTED_FOR_RECOVERY' and new.event_kind <> 'selection' then raise exception 'WNPH Recovery custody: selection requires event_kind=selection'; end if;
  if new.to_state not like 'REJECTED_%' and new.to_state not like 'DEFERRED_%' and new.to_state not in ('REOPENED','SELECTED_FOR_RECOVERY') and new.event_kind <> 'state_transition' then raise exception 'WNPH Recovery custody: ordinary progression requires event_kind=state_transition'; end if;

  if new.to_state = 'SOURCE_SUFFICIENT' then
    select exists (
      select 1 from wnph.source_sufficiency_assessments a
      where a.recovery_case_id = new.recovery_case_id
        and a.result = 'sufficient'
        and not exists (select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id = a.id)
        and exists (
          select 1 from wnph.source_sufficiency_members m
          where m.assessment_id = a.id and m.member_result = 'usable'
            and not exists (select 1 from wnph.source_sufficiency_members mn where mn.supersedes_member_id = m.id)
        )
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: SOURCE_SUFFICIENT requires a current sufficient assessment with a usable source member'; end if;
  end if;

  if new.to_state = 'RIGHTS_CLEARED' then
    select exists (
      select 1 from wnph.rights_determinations d
      where d.recovery_case_id = new.recovery_case_id
        and d.overall_status = 'cleared'
        and not exists (select 1 from wnph.rights_determinations n where n.supersedes_determination_id = d.id)
        and exists (select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_type='underlying_work' and c.component_status in ('public_domain','reuse_permitted','licensed'))
        and not exists (select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_status not in ('public_domain','reuse_permitted','licensed','not_applicable'))
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: RIGHTS_CLEARED requires a current cleared determination with resolved components'; end if;
  end if;

  if new.to_state = 'GAP_ESTABLISHED' then
    select exists (
      select 1 from wnph.existing_recovery_audits a
      where a.recovery_case_id=new.recovery_case_id and a.audit_status='complete'
        and not exists (select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id)
    ) and exists (
      select 1 from wnph.recovery_gap_assessments g
      where g.recovery_case_id=new.recovery_case_id and g.assessment_status='complete'
        and not exists (select 1 from wnph.recovery_gap_assessments n where n.supersedes_assessment_id=g.id)
        and exists (select 1 from wnph.recovery_gap_dimensions d where d.assessment_id=g.id and d.gap_state='meaningful_gap' and not exists (select 1 from wnph.recovery_gap_dimensions dn where dn.supersedes_dimension_id=d.id))
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: GAP_ESTABLISHED requires a complete recovery audit and complete gap assessment with a meaningful gap'; end if;
  end if;

  if new.to_state in ('QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (
      select 1 from wnph.recovery_case_briefs b
      where b.recovery_case_id=new.recovery_case_id
        and b.why_recover is not null and btrim(b.why_recover)<>''
        and b.proposed_expression_type is not null and btrim(b.proposed_expression_type)<>''
        and not exists (select 1 from wnph.recovery_case_briefs n where n.supersedes_brief_id=b.id)
    )
    and exists (
      select 1 from wnph.recovery_case_modes m where m.recovery_case_id=new.recovery_case_id and m.intent_status in ('proposed','committed')
        and not exists (select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
    )
    and exists (
      select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id
        and not exists (select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id)
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: qualification requires current recovery rationale, proposed Expression type, recovery mode, and output plan'; end if;
  end if;

  if new.to_state in ('QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (
      select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists (select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id)
    ) and exists (
      select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists (select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)
    ) and exists (
      select 1 from wnph.recovery_gap_assessments g where g.recovery_case_id=new.recovery_case_id and g.assessment_status='complete' and not exists (select 1 from wnph.recovery_gap_assessments n where n.supersedes_assessment_id=g.id)
        and exists (select 1 from wnph.recovery_gap_dimensions d where d.assessment_id=g.id and d.gap_state='meaningful_gap' and not exists (select 1 from wnph.recovery_gap_dimensions dn where dn.supersedes_dimension_id=d.id))
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: qualification gates are no longer currently satisfied'; end if;
  end if;

  if new.to_state = 'SELECTED_FOR_RECOVERY' then
    select new.selection_authorized
      and exists (select 1 from wnph.recovery_case_targets t where t.recovery_case_id=new.recovery_case_id and t.target_role='preferred_source' and not exists (select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id))
      and exists (select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id and o.plan_role='first_target' and not exists (select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id))
    into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: selection requires explicit authorization, a preferred source, and a first target manifestation'; end if;
  end if;

  return new;
end
$$;
