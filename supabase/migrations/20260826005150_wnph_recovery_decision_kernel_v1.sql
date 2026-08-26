create table wnph.recovery_decisions (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  decision_outcome text not null check (decision_outcome in ('qualify','defer','decline','more_evidence_needed')),
  decision_scope text not null constraint recovery_decisions_scope_nonblank check (btrim(decision_scope) <> ''),
  decision_summary text not null constraint recovery_decisions_summary_nonblank check (btrim(decision_summary) <> ''),
  supersedes_decision_id uuid references wnph.recovery_decisions(id),
  created_at timestamptz not null default now(),
  constraint recovery_decisions_supersedes_not_self check (supersedes_decision_id is null or supersedes_decision_id <> id)
);

create table wnph.recovery_decision_bases (
  id uuid primary key default gen_random_uuid(),
  recovery_decision_id uuid not null references wnph.recovery_decisions(id),
  basis_role text not null check (basis_role in ('supports','limits','contradicts','context')),
  recovery_condition_observation_id uuid references wnph.recovery_condition_observations(id),
  source_sufficiency_assessment_id uuid references wnph.source_sufficiency_assessments(id),
  rights_determination_id uuid references wnph.rights_determinations(id),
  existing_recovery_audit_id uuid references wnph.existing_recovery_audits(id),
  evidence_source_id uuid references wnph.evidence_sources(id),
  basis_note text,
  created_at timestamptz not null default now(),
  constraint recovery_decision_bases_one_basis check (num_nonnulls(recovery_condition_observation_id, source_sufficiency_assessment_id, rights_determination_id, existing_recovery_audit_id, evidence_source_id)=1)
);

create table wnph.recovery_decision_plan_members (
  id uuid primary key default gen_random_uuid(),
  recovery_decision_id uuid not null references wnph.recovery_decisions(id),
  member_role text not null check (member_role in ('scope','mode','output','source_target')),
  recovery_case_brief_id uuid references wnph.recovery_case_briefs(id),
  recovery_case_mode_id uuid references wnph.recovery_case_modes(id),
  recovery_case_output_id uuid references wnph.recovery_case_outputs(id),
  recovery_case_target_id uuid references wnph.recovery_case_targets(id),
  created_at timestamptz not null default now(),
  constraint recovery_decision_plan_members_one_member check (num_nonnulls(recovery_case_brief_id,recovery_case_mode_id,recovery_case_output_id,recovery_case_target_id)=1),
  constraint recovery_decision_plan_members_role_match check (
    (member_role='scope' and recovery_case_brief_id is not null) or
    (member_role='mode' and recovery_case_mode_id is not null) or
    (member_role='output' and recovery_case_output_id is not null) or
    (member_role='source_target' and recovery_case_target_id is not null)
  )
);

create index recovery_decisions_recovery_case_id_idx on wnph.recovery_decisions(recovery_case_id);
create index recovery_decisions_supersedes_decision_id_idx on wnph.recovery_decisions(supersedes_decision_id) where supersedes_decision_id is not null;
create index recovery_decision_bases_decision_idx on wnph.recovery_decision_bases(recovery_decision_id);
create index recovery_decision_bases_condition_idx on wnph.recovery_decision_bases(recovery_condition_observation_id) where recovery_condition_observation_id is not null;
create index recovery_decision_bases_source_sufficiency_idx on wnph.recovery_decision_bases(source_sufficiency_assessment_id) where source_sufficiency_assessment_id is not null;
create index recovery_decision_bases_rights_idx on wnph.recovery_decision_bases(rights_determination_id) where rights_determination_id is not null;
create index recovery_decision_bases_audit_idx on wnph.recovery_decision_bases(existing_recovery_audit_id) where existing_recovery_audit_id is not null;
create index recovery_decision_bases_evidence_source_idx on wnph.recovery_decision_bases(evidence_source_id) where evidence_source_id is not null;
create index recovery_decision_plan_members_decision_idx on wnph.recovery_decision_plan_members(recovery_decision_id);
create index recovery_decision_plan_members_brief_idx on wnph.recovery_decision_plan_members(recovery_case_brief_id) where recovery_case_brief_id is not null;
create index recovery_decision_plan_members_mode_idx on wnph.recovery_decision_plan_members(recovery_case_mode_id) where recovery_case_mode_id is not null;
create index recovery_decision_plan_members_output_idx on wnph.recovery_decision_plan_members(recovery_case_output_id) where recovery_case_output_id is not null;
create index recovery_decision_plan_members_target_idx on wnph.recovery_decision_plan_members(recovery_case_target_id) where recovery_case_target_id is not null;

create trigger recovery_decisions_append_only before update or delete on wnph.recovery_decisions for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_decision_bases_append_only before update or delete on wnph.recovery_decision_bases for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_decision_plan_members_append_only before update or delete on wnph.recovery_decision_plan_members for each row execute function wnph.reject_append_only_mutation();

alter table wnph.recovery_decisions enable row level security;
alter table wnph.recovery_decision_bases enable row level security;
alter table wnph.recovery_decision_plan_members enable row level security;
revoke all on wnph.recovery_decisions, wnph.recovery_decision_bases, wnph.recovery_decision_plan_members from public, anon, authenticated, service_role;

alter table wnph.recovery_case_events drop constraint recovery_case_events_from_state_check;
alter table wnph.recovery_case_events drop constraint recovery_case_events_to_state_check;
alter table wnph.recovery_case_events drop constraint recovery_case_events_event_kind_check;
alter table wnph.recovery_case_events add constraint recovery_case_events_from_state_check check (from_state is null or from_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','CONDITION_ASSESSED','DECISION_REVIEW','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED','REOPENED'));
alter table wnph.recovery_case_events add constraint recovery_case_events_to_state_check check (to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','CONDITION_ASSESSED','DECISION_REVIEW','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED','REOPENED'));
alter table wnph.recovery_case_events add constraint recovery_case_events_event_kind_check check (event_kind in ('state_transition','reject','defer','reopen','selection','decision'));

create or replace function wnph.validate_recovery_decision()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  v_state text;
  v_current uuid;
begin
  select e.to_state into v_state
  from wnph.recovery_case_events e
  where e.recovery_case_id=new.recovery_case_id
    and not exists (select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
  order by e.created_at desc limit 1;
  if v_state is distinct from 'DECISION_REVIEW' then
    raise exception 'WNPH Recovery custody: Recovery Decision may only be recorded while case is in DECISION_REVIEW';
  end if;
  select d.id into v_current from wnph.recovery_decisions d
  where d.recovery_case_id=new.recovery_case_id
    and not exists (select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;
  if v_current is not null and new.supersedes_decision_id is distinct from v_current then
    raise exception 'WNPH Recovery custody: new Recovery Decision must supersede the current decision';
  end if;
  if v_current is null and new.supersedes_decision_id is not null then
    raise exception 'WNPH Recovery custody: initial Recovery Decision may not supersede a non-current decision';
  end if;
  return new;
end $$;
create trigger recovery_decisions_insert_guard before insert on wnph.recovery_decisions for each row execute function wnph.validate_recovery_decision();

create or replace function wnph.validate_recovery_case_event()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  p wnph.recovery_case_events%rowtype;
  allowed boolean := false;
  gate_ok boolean := false;
  expected_outcome text;
begin
  if new.prior_event_id is null then
    if new.from_state is not null or new.to_state <> 'IDENTITY_ESTABLISHED' or new.event_kind <> 'state_transition' then raise exception 'WNPH Recovery custody: first event must establish inherited IDENTITY_ESTABLISHED state'; end if;
    select exists (select 1 from wnph.recovery_cases c join wnph.historical_works w on w.id=c.work_id where c.id=new.recovery_case_id and w.status='established' and exists (select 1 from wnph.work_identity_adjudications a where a.result_work_id=w.id and a.result in ('ESTABLISHES_WORK','SAME_WORK'))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: initial IDENTITY_ESTABLISHED requires an established Work with identity adjudication'; end if;
    return new;
  end if;
  select * into p from wnph.recovery_case_events where id=new.prior_event_id;
  if not found then raise exception 'WNPH Recovery custody: prior event % does not exist',new.prior_event_id; end if;
  if p.recovery_case_id<>new.recovery_case_id then raise exception 'WNPH Recovery custody: prior event belongs to a different Recovery Case'; end if;
  if new.from_state is distinct from p.to_state then raise exception 'WNPH Recovery custody: from_state % must equal prior to_state %',new.from_state,p.to_state; end if;
  if exists(select 1 from wnph.recovery_case_events e where e.prior_event_id=p.id) then raise exception 'WNPH Recovery custody: event history may not fork'; end if;

  allowed :=
    (new.from_state='IDENTITY_ESTABLISHED' and new.to_state='SOURCE_RESEARCH') or
    (new.from_state='SOURCE_RESEARCH' and new.to_state in ('SOURCE_SUFFICIENT','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_RESEARCH')) or
    (new.from_state='SOURCE_SUFFICIENT' and new.to_state='RIGHTS_RESEARCH') or
    (new.from_state='RIGHTS_RESEARCH' and new.to_state in ('RIGHTS_CLEARED','REJECTED_RIGHTS','DEFERRED_RIGHTS','DEFERRED_RESEARCH')) or
    (new.from_state='RIGHTS_CLEARED' and new.to_state='RECOVERY_AUDIT') or
    (new.from_state='RECOVERY_AUDIT' and new.to_state in ('CONDITION_ASSESSED','DEFERRED_RESEARCH')) or
    (new.from_state='CONDITION_ASSESSED' and new.to_state='DECISION_REVIEW') or
    (new.from_state='DECISION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED')) or
    (new.from_state='QUALIFIED' and new.to_state in ('SELECTED_FOR_RECOVERY','DEFERRED_CAPACITY','DEFERRED_LOW_VALUE')) or
    (new.from_state in ('SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.to_state='REOPENED') or
    (new.from_state='REOPENED' and new.to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','RIGHTS_RESEARCH','RECOVERY_AUDIT','CONDITION_ASSESSED','DECISION_REVIEW','QUALIFIED'));
  if not allowed then raise exception 'WNPH Recovery custody: forbidden transition % -> %',new.from_state,new.to_state; end if;

  if new.to_state like 'REJECTED_%' and new.event_kind<>'reject' then raise exception 'WNPH Recovery custody: rejected states require event_kind=reject'; end if;
  if new.to_state in ('DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH') and new.event_kind<>'defer' then raise exception 'WNPH Recovery custody: deferred states require event_kind=defer'; end if;
  if new.to_state='REOPENED' and new.event_kind<>'reopen' then raise exception 'WNPH Recovery custody: REOPENED requires event_kind=reopen'; end if;
  if new.to_state='SELECTED_FOR_RECOVERY' and new.event_kind<>'selection' then raise exception 'WNPH Recovery custody: selection requires event_kind=selection'; end if;
  if new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.from_state='DECISION_REVIEW' and new.event_kind<>'decision' then raise exception 'WNPH Recovery custody: Recovery Decision outcomes require event_kind=decision'; end if;
  if new.to_state not like 'REJECTED_%' and new.to_state not in ('DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED','SELECTED_FOR_RECOVERY','QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.event_kind<>'state_transition' then raise exception 'WNPH Recovery custody: ordinary progression requires event_kind=state_transition'; end if;

  if new.to_state='SOURCE_SUFFICIENT' then
    select exists (select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id) and exists(select 1 from wnph.source_sufficiency_members m where m.assessment_id=a.id and m.member_result='usable' and not exists(select 1 from wnph.source_sufficiency_members mn where mn.supersedes_member_id=m.id))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: SOURCE_SUFFICIENT requires a current sufficient assessment with a usable source member'; end if;
  end if;
  if new.to_state='RIGHTS_CLEARED' then
    select exists (select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id) and exists(select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_type='underlying_work' and c.component_status in ('public_domain','reuse_permitted','licensed')) and not exists(select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_status not in ('public_domain','reuse_permitted','licensed','not_applicable'))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: RIGHTS_CLEARED requires a current cleared determination with resolved components'; end if;
  end if;
  if new.to_state in ('CONDITION_ASSESSED','DECISION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (select 1 from wnph.recovery_condition_assessments a where a.recovery_case_id=new.recovery_case_id and a.assessment_status='bounded_complete' and not exists(select 1 from wnph.recovery_condition_assessments n where n.supersedes_assessment_id=a.id) and exists(select 1 from wnph.recovery_condition_observations o where o.assessment_id=a.id and not exists(select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id=o.id)) and not exists(select 1 from wnph.recovery_condition_observations o where o.assessment_id=a.id and o.epistemic_status='evidence' and not exists(select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id=o.id) and not exists(select 1 from wnph.evidence_links el where el.recovery_condition_observation_id=o.id and el.support_role in ('supports','contradicts','context') and not exists(select 1 from wnph.evidence_links eln where eln.supersedes_evidence_link_id=el.id)))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: condition progression requires a current bounded-complete condition assessment with observations and evidence links for evidence-status observations'; end if;
  end if;

  if new.from_state='DECISION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') then
    expected_outcome := case new.to_state when 'QUALIFIED' then 'qualify' when 'DEFERRED_RECOVERY' then 'defer' when 'DECLINED_RECOVERY' then 'decline' when 'MORE_EVIDENCE_NEEDED' then 'more_evidence_needed' end;
    select exists(
      select 1 from wnph.recovery_decisions d
      where d.recovery_case_id=new.recovery_case_id and d.decision_outcome=expected_outcome
        and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
        and exists(select 1 from wnph.recovery_decision_bases b where b.recovery_decision_id=d.id)
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: decision outcome requires a current Recovery Decision with matching outcome and relational basis'; end if;
  end if;

  if new.to_state='QUALIFIED' then
    select exists(
      select 1 from wnph.recovery_decisions d
      where d.recovery_case_id=new.recovery_case_id and d.decision_outcome='qualify'
        and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
        and exists(select 1 from wnph.recovery_decision_plan_members p where p.recovery_decision_id=d.id and p.member_role='scope')
        and exists(select 1 from wnph.recovery_decision_plan_members p where p.recovery_decision_id=d.id and p.member_role='mode')
        and exists(select 1 from wnph.recovery_decision_plan_members p where p.recovery_decision_id=d.id and p.member_role='output')
    ) and exists(select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id))
      and exists(select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: QUALIFIED requires a current qualifying Recovery Decision bound to scope, mode, output, source sufficiency and cleared rights'; end if;
  end if;

  if new.to_state='SELECTED_FOR_RECOVERY' then
    select new.selection_authorized and exists(select 1 from wnph.recovery_case_targets t where t.recovery_case_id=new.recovery_case_id and t.target_role='preferred_source' and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id)) and exists(select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id and o.plan_role='first_target' and not exists(select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id)) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: selection requires explicit authorization, a preferred source, and a first target manifestation'; end if;
  end if;
  return new;
end $$;