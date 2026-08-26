create table wnph.recovery_decision_requirements (
  id uuid primary key default gen_random_uuid(),
  recovery_decision_id uuid not null references wnph.recovery_decisions(id),
  canonical_key text not null constraint recovery_decision_requirements_key_nonblank check (btrim(canonical_key) <> ''),
  requirement_authority text not null check (requirement_authority in ('evidence','publishing_judgment')),
  requirement_scope text not null check (requirement_scope in ('mode','plan')),
  recovery_case_mode_id uuid references wnph.recovery_case_modes(id),
  question_text text not null constraint recovery_decision_requirements_question_nonblank check (btrim(question_text) <> ''),
  completion_criterion text not null constraint recovery_decision_requirements_completion_nonblank check (btrim(completion_criterion) <> ''),
  requirement_status text not null default 'open' check (requirement_status in ('open','satisfied','withdrawn')),
  supersedes_requirement_id uuid references wnph.recovery_decision_requirements(id),
  created_at timestamptz not null default now(),
  constraint recovery_decision_requirements_scope_match check (
    (requirement_scope='mode' and recovery_case_mode_id is not null) or
    (requirement_scope='plan' and recovery_case_mode_id is null)
  ),
  constraint recovery_decision_requirements_judgment_not_evidence_satisfied check (
    not (requirement_authority='publishing_judgment' and requirement_status='satisfied')
  ),
  constraint recovery_decision_requirements_supersedes_not_self check (supersedes_requirement_id is null or supersedes_requirement_id <> id)
);

comment on table wnph.recovery_decision_requirements is 'Append-only unresolved requirements exposed by a Recovery Decision. Evidence-authority requirements are empirically satisfiable; publishing_judgment requirements are resolved by a later governed decision, not by accumulating evidence.';
comment on column wnph.recovery_decision_requirements.requirement_scope is 'mode targets one proposed recovery mode; plan is cross-mode publishing scope. A combined text-plus-illustration recovery is a plan binding multiple modes, not a third recovery mode.';

create table wnph.recovery_decision_requirement_bases (
  id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null references wnph.recovery_decision_requirements(id),
  basis_role text not null check (basis_role in ('motivates','constrains','satisfies','context')),
  recovery_condition_observation_id uuid references wnph.recovery_condition_observations(id),
  source_sufficiency_assessment_id uuid references wnph.source_sufficiency_assessments(id),
  rights_determination_id uuid references wnph.rights_determinations(id),
  existing_recovery_audit_id uuid references wnph.existing_recovery_audits(id),
  evidence_source_id uuid references wnph.evidence_sources(id),
  basis_note text,
  created_at timestamptz not null default now(),
  constraint recovery_decision_requirement_bases_one_basis check (
    num_nonnulls(recovery_condition_observation_id,source_sufficiency_assessment_id,rights_determination_id,existing_recovery_audit_id,evidence_source_id)=1
  )
);

comment on table wnph.recovery_decision_requirement_bases is 'Relational provenance for why a Recovery Decision requirement exists or has been empirically satisfied. Evidence may constrain a publishing judgment but may not satisfy it.';

create index recovery_decision_requirements_decision_idx on wnph.recovery_decision_requirements(recovery_decision_id);
create index recovery_decision_requirements_mode_idx on wnph.recovery_decision_requirements(recovery_case_mode_id) where recovery_case_mode_id is not null;
create index recovery_decision_requirements_supersedes_idx on wnph.recovery_decision_requirements(supersedes_requirement_id) where supersedes_requirement_id is not null;
create index recovery_decision_requirement_bases_requirement_idx on wnph.recovery_decision_requirement_bases(requirement_id);
create index recovery_decision_requirement_bases_condition_idx on wnph.recovery_decision_requirement_bases(recovery_condition_observation_id) where recovery_condition_observation_id is not null;
create index recovery_decision_requirement_bases_source_sufficiency_idx on wnph.recovery_decision_requirement_bases(source_sufficiency_assessment_id) where source_sufficiency_assessment_id is not null;
create index recovery_decision_requirement_bases_rights_idx on wnph.recovery_decision_requirement_bases(rights_determination_id) where rights_determination_id is not null;
create index recovery_decision_requirement_bases_audit_idx on wnph.recovery_decision_requirement_bases(existing_recovery_audit_id) where existing_recovery_audit_id is not null;
create index recovery_decision_requirement_bases_evidence_source_idx on wnph.recovery_decision_requirement_bases(evidence_source_id) where evidence_source_id is not null;

create or replace function wnph.validate_recovery_decision_requirement()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  v_case uuid;
  v_outcome text;
  v_current_decision uuid;
  v_case_state text;
  v_mode_case uuid;
  v_current_requirement uuid;
  v_old wnph.recovery_decision_requirements%rowtype;
begin
  select d.recovery_case_id,d.decision_outcome into v_case,v_outcome
  from wnph.recovery_decisions d where d.id=new.recovery_decision_id;
  if not found then raise exception 'WNPH Recovery custody: Recovery Decision Requirement requires an existing Recovery Decision'; end if;

  select d.id into v_current_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;
  if v_current_decision is distinct from new.recovery_decision_id or v_outcome<>'more_evidence_needed' then
    raise exception 'WNPH Recovery custody: requirements may only elaborate the current more_evidence_needed decision';
  end if;

  select e.to_state into v_case_state
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
  order by e.created_at desc limit 1;
  if v_case_state is distinct from 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Recovery custody: requirements may only be recorded while case remains MORE_EVIDENCE_NEEDED';
  end if;

  if new.requirement_scope='mode' then
    select m.recovery_case_id into v_mode_case from wnph.recovery_case_modes m where m.id=new.recovery_case_mode_id;
    if v_mode_case is distinct from v_case then
      raise exception 'WNPH Recovery custody: requirement mode must belong to the same Recovery Case';
    end if;
  end if;

  select r.id into v_current_requirement
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id=new.recovery_decision_id
    and r.canonical_key=new.canonical_key
    and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id)
  order by r.created_at desc limit 1;

  if new.supersedes_requirement_id is null then
    if new.requirement_status<>'open' then
      raise exception 'WNPH Recovery custody: initial decision requirement must begin open';
    end if;
    if v_current_requirement is not null then
      raise exception 'WNPH Recovery custody: duplicate current decision requirement key %',new.canonical_key;
    end if;
  else
    select * into v_old from wnph.recovery_decision_requirements where id=new.supersedes_requirement_id;
    if not found or v_current_requirement is distinct from new.supersedes_requirement_id then
      raise exception 'WNPH Recovery custody: superseding requirement must supersede the current requirement';
    end if;
    if v_old.recovery_decision_id<>new.recovery_decision_id or v_old.canonical_key<>new.canonical_key or v_old.requirement_authority<>new.requirement_authority or v_old.requirement_scope<>new.requirement_scope or v_old.recovery_case_mode_id is distinct from new.recovery_case_mode_id then
      raise exception 'WNPH Recovery custody: requirement identity/authority/scope may not change through supersession';
    end if;
  end if;
  return new;
end $$;

create or replace function wnph.validate_recovery_decision_requirement_basis()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  v_authority text;
  v_case uuid;
  v_basis_case uuid;
begin
  select r.requirement_authority,d.recovery_case_id into v_authority,v_case
  from wnph.recovery_decision_requirements r join wnph.recovery_decisions d on d.id=r.recovery_decision_id
  where r.id=new.requirement_id;
  if not found then raise exception 'WNPH Recovery custody: requirement basis requires an existing requirement'; end if;
  if v_authority='publishing_judgment' and new.basis_role='satisfies' then
    raise exception 'WNPH Recovery custody: evidence may contextualize but may not satisfy a publishing_judgment requirement';
  end if;

  if new.recovery_condition_observation_id is not null then
    select a.recovery_case_id into v_basis_case
    from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id
    where o.id=new.recovery_condition_observation_id;
  elsif new.source_sufficiency_assessment_id is not null then
    select a.recovery_case_id into v_basis_case from wnph.source_sufficiency_assessments a where a.id=new.source_sufficiency_assessment_id;
  elsif new.rights_determination_id is not null then
    select d.recovery_case_id into v_basis_case from wnph.rights_determinations d where d.id=new.rights_determination_id;
  elsif new.existing_recovery_audit_id is not null then
    select a.recovery_case_id into v_basis_case from wnph.existing_recovery_audits a where a.id=new.existing_recovery_audit_id;
  end if;
  if v_basis_case is not null and v_basis_case is distinct from v_case then
    raise exception 'WNPH Recovery custody: requirement basis must belong to the same Recovery Case';
  end if;
  return new;
end $$;

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
  if new.decision_outcome='qualify' and v_current is not null and exists(
    select 1 from wnph.recovery_decision_requirements r
    where r.recovery_decision_id=v_current
      and r.requirement_authority='evidence'
      and r.requirement_status='open'
      and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id)
  ) then
    raise exception 'WNPH Recovery custody: qualify decision blocked by open evidence-authority requirements';
  end if;
  return new;
end $$;

create trigger recovery_decision_requirements_insert_guard before insert on wnph.recovery_decision_requirements for each row execute function wnph.validate_recovery_decision_requirement();
create trigger recovery_decision_requirements_append_only before update or delete on wnph.recovery_decision_requirements for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_decision_requirement_bases_insert_guard before insert on wnph.recovery_decision_requirement_bases for each row execute function wnph.validate_recovery_decision_requirement_basis();
create trigger recovery_decision_requirement_bases_append_only before update or delete on wnph.recovery_decision_requirement_bases for each row execute function wnph.reject_append_only_mutation();

alter table wnph.recovery_decision_requirements enable row level security;
alter table wnph.recovery_decision_requirement_bases enable row level security;
revoke all on wnph.recovery_decision_requirements, wnph.recovery_decision_requirement_bases from public, anon, authenticated, service_role;