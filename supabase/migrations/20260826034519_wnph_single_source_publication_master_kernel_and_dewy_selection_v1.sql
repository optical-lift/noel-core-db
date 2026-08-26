-- WNPH single-source publication master kernel + Dewy selection v1
--
-- A Publication Source Package is WNPH production apparatus, not a fifth IFLA LRM entity.
-- It is the governed, format-neutral source representation of one recovered Expression.
-- Downstream render profiles may derive any number of Manifestations from the same package
-- without editing the canonical content separately for each format.

create table wnph.publication_source_packages (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique constraint publication_source_packages_key_nonblank check (btrim(canonical_key) <> ''),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  expression_id uuid not null references wnph.expressions(id),
  qualifying_decision_id uuid not null references wnph.recovery_decisions(id),
  package_role text not null constraint publication_source_packages_role_nonblank check (btrim(package_role) <> ''),
  source_model text not null constraint publication_source_packages_model_nonblank check (btrim(source_model) <> ''),
  model_version text not null constraint publication_source_packages_version_nonblank check (btrim(model_version) <> ''),
  package_status text not null check (package_status in ('planned','building','ready','frozen','retired')),
  render_contract jsonb not null default '{}'::jsonb,
  notes text,
  supersedes_package_id uuid references wnph.publication_source_packages(id),
  created_at timestamptz not null default now(),
  constraint publication_source_packages_supersedes_not_self check (supersedes_package_id is null or supersedes_package_id <> id)
);

comment on table wnph.publication_source_packages is
  'Format-neutral WNPH production master for one governed recovered Expression. It is internal production apparatus between Expression custody and downstream Manifestation generation, not an additional bibliographic entity.';
comment on column wnph.publication_source_packages.render_contract is
  'Machine-readable single-source publishing contract. Renderers consume the same semantic text, assets, ordering, metadata and provenance to derive web, EPUB, print PDF, paperback, hardcover or future Manifestations without format-specific canonical forks.';

create table wnph.publication_source_blocks (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  block_key text not null constraint publication_source_blocks_key_nonblank check (btrim(block_key) <> ''),
  parent_block_id uuid references wnph.publication_source_blocks(id),
  ordinal integer not null default 0 check (ordinal >= 0),
  block_type text not null constraint publication_source_blocks_type_nonblank check (btrim(block_type) <> ''),
  semantic_role text,
  text_content text,
  properties jsonb not null default '{}'::jsonb,
  source_provenance jsonb not null default '{}'::jsonb,
  supersedes_block_id uuid references wnph.publication_source_blocks(id),
  created_at timestamptz not null default now(),
  constraint publication_source_blocks_supersedes_not_self check (supersedes_block_id is null or supersedes_block_id <> id)
);

comment on table wnph.publication_source_blocks is
  'Format-neutral semantic content tree for a Publication Source Package. block_type and semantic_role are intentionally open vocabularies so future renderers are not constrained to today''s output formats.';

create table wnph.publication_source_assets (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  asset_key text not null constraint publication_source_assets_key_nonblank check (btrim(asset_key) <> ''),
  asset_role text not null constraint publication_source_assets_role_nonblank check (btrim(asset_role) <> ''),
  source_surrogate_id uuid references wnph.surrogates(id),
  evidence_source_id uuid references wnph.evidence_sources(id),
  source_locator jsonb not null default '{}'::jsonb,
  storage_uri text,
  media_type text,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_asset_id uuid references wnph.publication_source_assets(id),
  created_at timestamptz not null default now(),
  constraint publication_source_assets_supersedes_not_self check (supersedes_asset_id is null or supersedes_asset_id <> id),
  constraint publication_source_assets_has_custody check (
    source_surrogate_id is not null or evidence_source_id is not null or storage_uri is not null
  )
);

comment on table wnph.publication_source_assets is
  'Canonical asset registry for a Publication Source Package. Historical source provenance and recovered asset storage remain explicit; renderers reference assets rather than embedding format-specific copies into the canonical text.';

create table wnph.publication_render_profiles (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique constraint publication_render_profiles_key_nonblank check (btrim(canonical_key) <> ''),
  output_family text not null constraint publication_render_profiles_family_nonblank check (btrim(output_family) <> ''),
  profile_version text not null constraint publication_render_profiles_version_nonblank check (btrim(profile_version) <> ''),
  rules jsonb not null default '{}'::jsonb,
  profile_status text not null check (profile_status in ('draft','active','deprecated')),
  notes text,
  supersedes_profile_id uuid references wnph.publication_render_profiles(id),
  created_at timestamptz not null default now(),
  constraint publication_render_profiles_supersedes_not_self check (supersedes_profile_id is null or supersedes_profile_id <> id)
);

comment on table wnph.publication_render_profiles is
  'Open-ended renderer contracts. output_family is deliberately not an enum: current and future Manifestation families may be added without changing the canonical Publication Source Package.';

create table wnph.publication_manifestation_derivations (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  render_profile_id uuid not null references wnph.publication_render_profiles(id),
  manifestation_id uuid not null references wnph.manifestations(id),
  derivation_status text not null check (derivation_status in ('planned','generated','verified','released')),
  build_metadata jsonb not null default '{}'::jsonb,
  supersedes_derivation_id uuid references wnph.publication_manifestation_derivations(id),
  created_at timestamptz not null default now(),
  constraint publication_manifestation_derivations_supersedes_not_self check (supersedes_derivation_id is null or supersedes_derivation_id <> id)
);

comment on table wnph.publication_manifestation_derivations is
  'Provenance bridge from one canonical Publication Source Package through a renderer profile to a concrete Manifestation. Multiple Manifestations may derive from the same package without creating parallel canonical editorial sources.';

create index publication_source_packages_case_idx on wnph.publication_source_packages(recovery_case_id);
create index publication_source_packages_expression_idx on wnph.publication_source_packages(expression_id);
create index publication_source_packages_decision_idx on wnph.publication_source_packages(qualifying_decision_id);
create index publication_source_packages_supersedes_idx on wnph.publication_source_packages(supersedes_package_id) where supersedes_package_id is not null;
create index publication_source_blocks_package_idx on wnph.publication_source_blocks(source_package_id);
create index publication_source_blocks_parent_idx on wnph.publication_source_blocks(parent_block_id) where parent_block_id is not null;
create index publication_source_blocks_supersedes_idx on wnph.publication_source_blocks(supersedes_block_id) where supersedes_block_id is not null;
create index publication_source_assets_package_idx on wnph.publication_source_assets(source_package_id);
create index publication_source_assets_surrogate_idx on wnph.publication_source_assets(source_surrogate_id) where source_surrogate_id is not null;
create index publication_source_assets_evidence_idx on wnph.publication_source_assets(evidence_source_id) where evidence_source_id is not null;
create index publication_source_assets_supersedes_idx on wnph.publication_source_assets(supersedes_asset_id) where supersedes_asset_id is not null;
create index publication_render_profiles_supersedes_idx on wnph.publication_render_profiles(supersedes_profile_id) where supersedes_profile_id is not null;
create index publication_manifestation_derivations_package_idx on wnph.publication_manifestation_derivations(source_package_id);
create index publication_manifestation_derivations_profile_idx on wnph.publication_manifestation_derivations(render_profile_id);
create index publication_manifestation_derivations_manifestation_idx on wnph.publication_manifestation_derivations(manifestation_id);
create index publication_manifestation_derivations_supersedes_idx on wnph.publication_manifestation_derivations(supersedes_derivation_id) where supersedes_derivation_id is not null;

create or replace function wnph.validate_publication_source_package()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  v_case_work uuid;
  v_expression_work uuid;
  v_decision_case uuid;
  v_decision_outcome text;
  v_current_decision uuid;
  v_current_package uuid;
begin
  select c.work_id into v_case_work from wnph.recovery_cases c where c.id=new.recovery_case_id;
  select e.work_id into v_expression_work from wnph.expressions e where e.id=new.expression_id;
  if v_case_work is null or v_expression_work is null or v_case_work is distinct from v_expression_work then
    raise exception 'WNPH publication source custody: package Expression must belong to the Recovery Case Work';
  end if;

  select d.recovery_case_id,d.decision_outcome into v_decision_case,v_decision_outcome
  from wnph.recovery_decisions d where d.id=new.qualifying_decision_id;
  if v_decision_case is distinct from new.recovery_case_id or v_decision_outcome<>'qualify' then
    raise exception 'WNPH publication source custody: package requires a qualifying Recovery Decision from the same case';
  end if;

  select d.id into v_current_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=new.recovery_case_id
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;
  if v_current_decision is distinct from new.qualifying_decision_id then
    raise exception 'WNPH publication source custody: package must bind the current qualifying Recovery Decision';
  end if;

  if not exists(
    select 1
    from wnph.recovery_decision_plan_members pm
    join wnph.recovery_case_targets t on t.id=pm.recovery_case_target_id
    where pm.recovery_decision_id=new.qualifying_decision_id
      and pm.member_role='source_target'
      and t.expression_id=new.expression_id
  ) then
    raise exception 'WNPH publication source custody: package Expression must be the Expression target bound by the qualifying plan';
  end if;

  select p.id into v_current_package
  from wnph.publication_source_packages p
  where p.recovery_case_id=new.recovery_case_id
    and p.package_role='canonical_master'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id)
  order by p.created_at desc limit 1;

  if new.supersedes_package_id is null then
    if v_current_package is not null then
      raise exception 'WNPH publication source custody: Recovery Case already has a current canonical master package';
    end if;
  elsif v_current_package is distinct from new.supersedes_package_id then
    raise exception 'WNPH publication source custody: package supersession must supersede the current canonical master package';
  end if;

  return new;
end $$;

create trigger publication_source_packages_insert_guard
before insert on wnph.publication_source_packages
for each row execute function wnph.validate_publication_source_package();

create trigger publication_source_packages_append_only before update or delete on wnph.publication_source_packages for each row execute function wnph.reject_append_only_mutation();
create trigger publication_source_blocks_append_only before update or delete on wnph.publication_source_blocks for each row execute function wnph.reject_append_only_mutation();
create trigger publication_source_assets_append_only before update or delete on wnph.publication_source_assets for each row execute function wnph.reject_append_only_mutation();
create trigger publication_render_profiles_append_only before update or delete on wnph.publication_render_profiles for each row execute function wnph.reject_append_only_mutation();
create trigger publication_manifestation_derivations_append_only before update or delete on wnph.publication_manifestation_derivations for each row execute function wnph.reject_append_only_mutation();

alter table wnph.publication_source_packages enable row level security;
alter table wnph.publication_source_blocks enable row level security;
alter table wnph.publication_source_assets enable row level security;
alter table wnph.publication_render_profiles enable row level security;
alter table wnph.publication_manifestation_derivations enable row level security;
revoke all on wnph.publication_source_packages, wnph.publication_source_blocks, wnph.publication_source_assets, wnph.publication_render_profiles, wnph.publication_manifestation_derivations from public, anon, authenticated, service_role;

-- Selection now chooses the canonical master, not one arbitrary Manifestation.
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
        and exists(select 1 from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=d.id and pm.member_role='scope')
        and exists(select 1 from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=d.id and pm.member_role='mode')
    ) and exists(select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id))
      and exists(select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: QUALIFIED requires a current qualifying Recovery Decision bound to scope and mode, source sufficiency and cleared rights; Manifestation output remains a downstream selection decision'; end if;
  end if;

  if new.to_state='SELECTED_FOR_RECOVERY' then
    select new.selection_authorized
      and exists(
        select 1 from wnph.recovery_case_targets t
        where t.recovery_case_id=new.recovery_case_id
          and t.target_role='preferred_source'
          and t.surrogate_id is not null
          and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id)
      )
      and exists(
        select 1 from wnph.publication_source_packages sp
        where sp.recovery_case_id=new.recovery_case_id
          and sp.package_role='canonical_master'
          and sp.package_status in ('planned','building','ready','frozen')
          and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=sp.id)
      )
    into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: selection requires explicit authorization, a preferred historical source, and a current canonical Publication Source Package; Manifestation choice is downstream'; end if;
  end if;
  return new;
end $$;

comment on function wnph.validate_recovery_case_event() is
  'Recovery state transition guard. QUALIFIED binds the Expression-level recovery plan. SELECTED_FOR_RECOVERY selects a format-neutral canonical Publication Source Package plus preferred historical source; concrete Manifestations are downstream derivations.';

-- Dewy: bind the approved LOC/IA source, instantiate the single-source master, and select that master for recovery.
do $$
declare
  v_case uuid;
  v_current_event uuid;
  v_decision uuid;
  v_expression uuid;
  v_primary_source_target uuid;
  v_surrogate uuid;
  v_package uuid;
begin
  select c.id into v_case
  from wnph.recovery_cases c
  where c.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';
  if v_case is null then raise exception 'WNPH Dewy single-source selection: Recovery Case not found'; end if;

  select e.id into v_current_event
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and e.to_state='QUALIFIED'
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
  order by e.created_at desc limit 1;
  if v_current_event is null then raise exception 'WNPH Dewy single-source selection: case must currently be QUALIFIED'; end if;

  select d.id into v_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and d.decision_outcome='qualify'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;
  if v_decision is null then raise exception 'WNPH Dewy single-source selection: current qualifying decision not found'; end if;

  select t.id,t.expression_id into v_primary_source_target,v_expression
  from wnph.recovery_decision_plan_members pm
  join wnph.recovery_case_targets t on t.id=pm.recovery_case_target_id
  where pm.recovery_decision_id=v_decision
    and pm.member_role='source_target'
    and t.expression_id is not null
  limit 1;
  if v_expression is null then raise exception 'WNPH Dewy single-source selection: qualifying Expression target not found'; end if;

  select t.id,t.surrogate_id into v_primary_source_target,v_surrogate
  from wnph.recovery_case_targets t
  join wnph.surrogates s on s.id=t.surrogate_id
  join wnph.evidence_sources es on es.id=s.source_id
  where t.recovery_case_id=v_case
    and t.target_role='primary_source'
    and s.canonical_key='wish-fairy-dewy-dear:loc-digital'
    and es.canonical_key='loc:item:22008427'
    and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id)
  order by t.created_at desc limit 1;
  if v_surrogate is null then raise exception 'WNPH Dewy single-source selection: governed LOC surrogate not found'; end if;

  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,surrogate_id,rationale
  ) values(
    v_case,'preferred_source',v_surrogate,
    'Selected production recovery source: the governed Library of Congress 72-image digital surrogate, corroborated by the Internet Archive/Wikimedia access mirror under IA identifier wishfairydewydea00colv. Mirrors do not add a second historical witness.'
  );

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,package_role,source_model,model_version,package_status,render_contract,notes
  ) values(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    v_case,v_expression,v_decision,'canonical_master','semantic_single_source','1','planned',
    jsonb_build_object(
      'single_source_publishing',true,
      'manifestation_agnostic',true,
      'canonical_layers',jsonb_build_array('semantic_structure','verified_text','illustration_assets','metadata','provenance'),
      'renderer_rule','Downstream renderers may transform presentation and packaging but may not fork or silently alter canonical content.',
      'supported_by_design',jsonb_build_array('responsive_web','reflowable_epub','fixed_layout_epub','print_pdf','paperback','hardcover','future_output_families'),
      'output_family_vocab_open',true
    ),
    'One governed source is created once. Every publication format is a derived Manifestation of this package, never a separately edited canonical edition.'
  ) returning id into v_package;

  insert into wnph.publication_source_assets(
    source_package_id,asset_key,asset_role,source_surrogate_id,evidence_source_id,source_locator,media_type,metadata
  )
  select v_package,'historical-source-surrogate','preferred_historical_source',v_surrogate,s.source_id,
         jsonb_build_object('image_count',s.image_count,'formats',to_jsonb(s.formats)),
         'application/x-source-surrogate',
         jsonb_build_object('custody_role','recovery_basis','historical_witness_count_delta',0)
  from wnph.surrogates s where s.id=v_surrogate;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized
  ) values(
    v_case,v_current_event,'QUALIFIED','SELECTED_FOR_RECOVERY','selection',
    'Explicitly select the format-neutral canonical Publication Source Package for recovery using the governed LOC/IA source basis. This authorizes building the single canonical master, not any one paperback, EPUB, web, PDF or other Manifestation.',true
  );

  if exists(
    select 1 from wnph.recovery_case_outputs o
    where o.recovery_case_id=v_case and o.plan_role='first_target'
      and not exists(select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id)
  ) then raise exception 'WNPH Dewy single-source selection: selection must not require or create a first-target Manifestation'; end if;

  if (select e.to_state from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id) order by e.created_at desc limit 1) is distinct from 'SELECTED_FOR_RECOVERY' then
    raise exception 'WNPH Dewy single-source selection: case did not reach SELECTED_FOR_RECOVERY';
  end if;
end $$;