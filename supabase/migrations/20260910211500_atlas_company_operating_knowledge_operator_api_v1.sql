-- Atlas Company Operating Knowledge operator/practitioner API v1
-- Adds governed human and delegated-service interaction seams without granting direct table mutation.

BEGIN;

-- Rejected candidates need an explicit terminal non-governing state.
alter table atlas.company_operating_knowledge
  drop constraint company_operating_knowledge_status_check;

alter table atlas.company_operating_knowledge
  add constraint company_operating_knowledge_status_check
  check (status in ('candidate','established','disputed','rejected','superseded','retired'));

-- Distinguish institutional authority from the person/tool that recorded the adjudication.
alter table atlas.company_operating_knowledge_adjudications
  add column recorded_by_user_id uuid null references auth.users(id),
  add column recorded_by_label text null;

comment on column atlas.company_operating_knowledge_adjudications.adjudicated_by_label is
  'Human/institutional authority whose judgment the adjudication records.';
comment on column atlas.company_operating_knowledge_adjudications.recorded_by_user_id is
  'Authenticated Atlas user who recorded the adjudication, when applicable.';
comment on column atlas.company_operating_knowledge_adjudications.recorded_by_label is
  'Operator, practitioner, delegated agent, or service label that recorded the adjudication.';

-- Once a rule has ever been established, its semantics stay immutable even if it later becomes disputed/retired/superseded.
create or replace function atlas.guard_established_company_operating_knowledge_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
begin
  if old.established_at is not null and (
    new.organization_id is distinct from old.organization_id
    or new.organization_unit_id is distinct from old.organization_unit_id
    or new.family_key is distinct from old.family_key
    or new.stable_key is distinct from old.stable_key
    or new.version is distinct from old.version
    or new.knowledge_kind is distinct from old.knowledge_kind
    or new.title is distinct from old.title
    or new.statement is distinct from old.statement
    or new.scope_match is distinct from old.scope_match
    or new.effect is distinct from old.effect
    or new.precedence is distinct from old.precedence
    or new.effective_from is distinct from old.effective_from
    or new.established_by_user_id is distinct from old.established_by_user_id
    or new.established_by_label is distinct from old.established_by_label
    or new.established_at is distinct from old.established_at
  ) then
    raise exception 'previously established Company Operating Knowledge semantics are immutable; create a replacement version';
  end if;
  return new;
end;
$$;

-- Internal proposal primitive. No client role receives EXECUTE directly.
create or replace function atlas.company_operating_knowledge_propose_internal_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_family_key text,
  p_stable_key text,
  p_knowledge_kind text,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer,
  p_confidence numeric,
  p_supersedes_id uuid,
  p_recorded_by_user_id uuid,
  p_recorded_by_label text,
  p_source text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_id uuid;
  v_stable_key text;
  v_family_key text;
  v_version integer;
  v_prior atlas.company_operating_knowledge%rowtype;
begin
  if p_organization_id is null then raise exception 'organization is required' using errcode='22023'; end if;
  if nullif(btrim(p_family_key),'') is null then raise exception 'family key is required' using errcode='22023'; end if;
  if nullif(btrim(p_title),'') is null or nullif(btrim(p_statement),'') is null then raise exception 'title and statement are required' using errcode='22023'; end if;
  if p_scope_match is null or jsonb_typeof(p_scope_match) <> 'object' then raise exception 'scope_match must be a JSON object' using errcode='22023'; end if;
  if p_effect is null or jsonb_typeof(p_effect) <> 'object' then raise exception 'effect must be a JSON object' using errcode='22023'; end if;
  if p_recorded_by_user_id is null and nullif(btrim(p_recorded_by_label),'') is null then raise exception 'recorder identity is required' using errcode='22023'; end if;

  if p_supersedes_id is not null then
    select * into v_prior
    from atlas.company_operating_knowledge
    where id=p_supersedes_id and organization_id=p_organization_id;
    if not found then raise exception 'replacement source knowledge not found in organization' using errcode='23503'; end if;
    if v_prior.organization_unit_id is distinct from p_organization_unit_id then raise exception 'replacement must keep the same organization-unit jurisdiction' using errcode='22023'; end if;
    v_family_key := v_prior.family_key;
    v_stable_key := v_prior.stable_key;
    select coalesce(max(version),0)+1 into v_version
      from atlas.company_operating_knowledge
      where organization_id=p_organization_id and stable_key=v_stable_key;
  else
    v_family_key := btrim(p_family_key);
    v_stable_key := nullif(btrim(p_stable_key),'');
    if v_stable_key is null then
      v_stable_key := 'knowledge.' || trim(both '_' from regexp_replace(lower(v_family_key),'[^a-z0-9]+','_','g')) || '.' || substr(replace(gen_random_uuid()::text,'-',''),1,12);
    end if;
    if exists(select 1 from atlas.company_operating_knowledge where organization_id=p_organization_id and stable_key=v_stable_key) then
      raise exception 'stable key already exists; create a replacement version instead' using errcode='23505';
    end if;
    v_version := 1;
  end if;

  insert into atlas.company_operating_knowledge(
    organization_id, organization_unit_id, family_key, stable_key, version,
    knowledge_kind, title, statement, scope_match, effect, precedence,
    status, confidence, supersedes_id, provenance, metadata
  ) values (
    p_organization_id, p_organization_unit_id, v_family_key, v_stable_key, v_version,
    p_knowledge_kind, btrim(p_title), btrim(p_statement), p_scope_match, p_effect, coalesce(p_precedence,0),
    'candidate', p_confidence, p_supersedes_id,
    jsonb_build_object('source',coalesce(nullif(btrim(p_source),''),'operator_api'),'recordedBy',coalesce(nullif(btrim(p_recorded_by_label),''),'authenticated_user')),
    jsonb_build_object('operatorApiVersion','v1')
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function atlas.company_operating_knowledge_add_evidence_internal_v1(
  p_knowledge_id uuid,
  p_evidence_kind text,
  p_interpretation_kind text,
  p_source_locator jsonb,
  p_evidence_snapshot jsonb,
  p_note text,
  p_observed_at timestamptz,
  p_recorded_by_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_id uuid;
  v_org uuid;
begin
  select organization_id into v_org from atlas.company_operating_knowledge where id=p_knowledge_id;
  if v_org is null then raise exception 'knowledge item not found' using errcode='23503'; end if;
  if coalesce(jsonb_typeof(p_source_locator),'object') <> 'object' then raise exception 'source locator must be an object' using errcode='22023'; end if;
  if coalesce(jsonb_typeof(p_evidence_snapshot),'object') <> 'object' then raise exception 'evidence snapshot must be an object' using errcode='22023'; end if;

  insert into atlas.company_operating_knowledge_evidence(
    organization_id, knowledge_id, evidence_kind, interpretation_kind,
    source_locator, evidence_snapshot, note, observed_at, created_by_user_id
  ) values (
    v_org, p_knowledge_id, p_evidence_kind, coalesce(nullif(btrim(p_interpretation_kind),''),'supports'),
    coalesce(p_source_locator,'{}'::jsonb), coalesce(p_evidence_snapshot,'{}'::jsonb), nullif(btrim(p_note),''), p_observed_at, p_recorded_by_user_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function atlas.company_operating_knowledge_adjudicate_internal_v1(
  p_knowledge_id uuid,
  p_decision_kind text,
  p_basis text,
  p_authority_label text,
  p_recorded_by_user_id uuid,
  p_recorded_by_label text,
  p_effective_from timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_item atlas.company_operating_knowledge%rowtype;
  v_prior atlas.company_operating_knowledge%rowtype;
  v_now timestamptz := now();
  v_effective timestamptz;
begin
  if nullif(btrim(p_basis),'') is null then raise exception 'adjudication basis is required' using errcode='22023'; end if;
  if nullif(btrim(p_authority_label),'') is null then raise exception 'institutional authority label is required' using errcode='22023'; end if;
  if p_recorded_by_user_id is null and nullif(btrim(p_recorded_by_label),'') is null then raise exception 'recorder identity is required' using errcode='22023'; end if;

  select * into v_item from atlas.company_operating_knowledge where id=p_knowledge_id for update;
  if not found then raise exception 'knowledge item not found' using errcode='23503'; end if;

  if p_decision_kind='establish' then
    if v_item.status not in ('candidate','disputed') or v_item.established_at is not null then
      raise exception 'only never-established candidate/disputed knowledge may be established; create a replacement version for prior live rules' using errcode='22023';
    end if;
    v_effective := coalesce(p_effective_from,v_item.effective_from,v_now);

    if v_item.supersedes_id is not null then
      select * into v_prior from atlas.company_operating_knowledge where id=v_item.supersedes_id for update;
      if not found then raise exception 'replacement source knowledge is missing' using errcode='23503'; end if;
      if v_prior.status='established' then
        update atlas.company_operating_knowledge
          set status='superseded', effective_to=v_effective, updated_at=v_now
          where id=v_prior.id;
        insert into atlas.company_operating_knowledge_adjudications(
          organization_id,knowledge_id,decision_kind,basis,evidence_snapshot,
          adjudicated_by_user_id,adjudicated_by_label,recorded_by_user_id,recorded_by_label
        ) values (
          v_prior.organization_id,v_prior.id,'supersede',p_basis,
          jsonb_build_object('replacementKnowledgeId',v_item.id),
          null,btrim(p_authority_label),p_recorded_by_user_id,nullif(btrim(p_recorded_by_label),'')
        );
      end if;
    end if;

    update atlas.company_operating_knowledge
      set status='established', effective_from=v_effective,
          established_by_user_id=null, established_by_label=btrim(p_authority_label),
          established_at=v_now, updated_at=v_now
      where id=v_item.id;
  elsif p_decision_kind='dispute' then
    if v_item.status not in ('candidate','established') then raise exception 'only candidate or established knowledge may be disputed' using errcode='22023'; end if;
    update atlas.company_operating_knowledge
      set status='disputed', effective_to=case when v_item.status='established' then v_now else effective_to end, updated_at=v_now
      where id=v_item.id;
  elsif p_decision_kind='reject' then
    if v_item.established_at is not null or v_item.status not in ('candidate','disputed') then raise exception 'only never-established candidate/disputed knowledge may be rejected' using errcode='22023'; end if;
    update atlas.company_operating_knowledge set status='rejected', updated_at=v_now where id=v_item.id;
  elsif p_decision_kind='reopen' then
    if v_item.established_at is not null or v_item.status not in ('rejected','disputed') then raise exception 'only never-established rejected/disputed knowledge may be reopened' using errcode='22023'; end if;
    update atlas.company_operating_knowledge set status='candidate', updated_at=v_now where id=v_item.id;
  elsif p_decision_kind='retire' then
    if v_item.status <> 'established' then raise exception 'only established knowledge may be retired' using errcode='22023'; end if;
    update atlas.company_operating_knowledge set status='retired', effective_to=v_now, updated_at=v_now where id=v_item.id;
  else
    raise exception 'unsupported adjudication decision' using errcode='22023';
  end if;

  insert into atlas.company_operating_knowledge_adjudications(
    organization_id,knowledge_id,decision_kind,basis,evidence_snapshot,
    adjudicated_by_user_id,adjudicated_by_label,recorded_by_user_id,recorded_by_label
  ) values (
    v_item.organization_id,v_item.id,p_decision_kind,btrim(p_basis),'{}'::jsonb,
    null,btrim(p_authority_label),p_recorded_by_user_id,nullif(btrim(p_recorded_by_label),'')
  );

  return jsonb_build_object('ok',true,'knowledgeId',v_item.id,'decision',p_decision_kind);
end;
$$;

-- Resolve one exact Ledger entitlement binding inside an implementation case.
create or replace function atlas.implementation_operating_scope_internal_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid
)
returns table(organization_id uuid, organization_unit_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $$
  select b.organization_id,b.organization_unit_id
  from atlas.ledger_entitlement_bindings b
  join atlas.ledger_entitlements le on le.id=b.ledger_entitlement_id
  join atlas.implementation_cases c on c.id=le.implementation_case_id
  where c.id=p_implementation_case_id
    and le.id=p_ledger_entitlement_id
    and b.ended_at is null
  limit 1;
$$;

-- Practitioner read surface: all knowledge relevant to active Ledger bindings in one implementation case.
create or replace function atlas.implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;
  if not exists(select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id) then
    return jsonb_build_object('ok',false,'code','case_not_found');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_operating_knowledge_self_api_v1',
    'bindings',coalesce((
      select jsonb_agg(jsonb_build_object(
        'ledgerEntitlementId',le.id,'entitlementNumber',le.entitlement_number,
        'organizationId',b.organization_id,'organizationName',o.name,
        'organizationUnitId',b.organization_unit_id,'organizationUnitName',ou.name
      ) order by le.entitlement_number)
      from atlas.ledger_entitlements le
      join atlas.ledger_entitlement_bindings b on b.ledger_entitlement_id=le.id and b.ended_at is null
      join atlas.organizations o on o.id=b.organization_id
      left join atlas.organization_units ou on ou.id=b.organization_unit_id
      where le.implementation_case_id=p_implementation_case_id
    ),'[]'::jsonb),
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',k.id,'organizationId',k.organization_id,'organizationUnitId',k.organization_unit_id,
        'familyKey',k.family_key,'stableKey',k.stable_key,'version',k.version,
        'knowledgeKind',k.knowledge_kind,'title',k.title,'statement',k.statement,
        'scopeMatch',k.scope_match,'effect',k.effect,'precedence',k.precedence,
        'status',k.status,'confidence',k.confidence,'effectiveFrom',k.effective_from,
        'effectiveTo',k.effective_to,'supersedesId',k.supersedes_id,
        'establishedByLabel',k.established_by_label,'establishedAt',k.established_at,
        'reviewAfter',k.review_after,'provenance',k.provenance,'metadata',k.metadata,
        'createdAt',k.created_at,'updatedAt',k.updated_at,
        'evidence',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'evidenceKind',e.evidence_kind,'interpretationKind',e.interpretation_kind,
          'sourceLocator',e.source_locator,'evidenceSnapshot',e.evidence_snapshot,'note',e.note,
          'observedAt',e.observed_at,'createdAt',e.created_at
        ) order by e.created_at,e.id) from atlas.company_operating_knowledge_evidence e where e.knowledge_id=k.id),'[]'::jsonb),
        'adjudications',coalesce((select jsonb_agg(jsonb_build_object(
          'id',a.id,'decisionKind',a.decision_kind,'basis',a.basis,
          'authorityLabel',a.adjudicated_by_label,'recordedByLabel',a.recorded_by_label,
          'createdAt',a.created_at
        ) order by a.created_at,a.id) from atlas.company_operating_knowledge_adjudications a where a.knowledge_id=k.id),'[]'::jsonb)
      ) order by k.family_key,k.stable_key,k.version desc)
      from atlas.company_operating_knowledge k
      where exists(
        select 1
        from atlas.ledger_entitlements le
        join atlas.ledger_entitlement_bindings b on b.ledger_entitlement_id=le.id and b.ended_at is null
        where le.implementation_case_id=p_implementation_case_id
          and b.organization_id=k.organization_id
          and (k.organization_unit_id is null or k.organization_unit_id=b.organization_unit_id)
      )
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function atlas.propose_implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_family_key text,
  p_stable_key text,
  p_knowledge_kind text,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null,
  p_evidence_kind text default null,
  p_evidence_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org uuid; v_unit uuid; v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id and c.state not in ('closed','cancelled')) then raise exception 'Open implementation case not found.' using errcode='23503'; end if;
  select organization_id,organization_unit_id into v_org,v_unit from atlas.implementation_operating_scope_internal_v1(p_implementation_case_id,p_ledger_entitlement_id);
  if v_org is null then raise exception 'Active Ledger binding not found for implementation case.' using errcode='23503'; end if;

  v_id := atlas.company_operating_knowledge_propose_internal_v1(
    v_org,v_unit,p_family_key,p_stable_key,p_knowledge_kind,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,null,
    auth.uid(),'implementation practitioner','implementation_portal'
  );
  if nullif(btrim(p_evidence_kind),'') is not null then
    perform atlas.company_operating_knowledge_add_evidence_internal_v1(
      v_id,p_evidence_kind,'originates',jsonb_build_object('implementationCaseId',p_implementation_case_id,'ledgerEntitlementId',p_ledger_entitlement_id),
      jsonb_build_object('statement',p_statement),p_evidence_note,now(),auth.uid()
    );
  end if;
  return jsonb_build_object('ok',true,'knowledgeId',v_id);
end;
$$;

create or replace function atlas.revise_implementation_operating_knowledge_candidate_self_v1(
  p_implementation_case_id uuid,
  p_knowledge_id uuid,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(
    select 1 from atlas.company_operating_knowledge k
    where k.id=p_knowledge_id and k.established_at is null and k.status in ('candidate','disputed')
      and exists(select 1 from atlas.ledger_entitlements le join atlas.ledger_entitlement_bindings b on b.ledger_entitlement_id=le.id and b.ended_at is null where le.implementation_case_id=p_implementation_case_id and b.organization_id=k.organization_id and (k.organization_unit_id is null or k.organization_unit_id=b.organization_unit_id))
  ) then raise exception 'Editable operating-knowledge candidate not found in implementation scope.' using errcode='23503'; end if;
  if p_scope_match is null or jsonb_typeof(p_scope_match)<>'object' or p_effect is null or jsonb_typeof(p_effect)<>'object' then raise exception 'scope and effect must be JSON objects' using errcode='22023'; end if;
  update atlas.company_operating_knowledge set title=btrim(p_title),statement=btrim(p_statement),scope_match=p_scope_match,effect=p_effect,precedence=coalesce(p_precedence,0),confidence=p_confidence,updated_at=now() where id=p_knowledge_id;
  return jsonb_build_object('ok',true,'knowledgeId',p_knowledge_id);
end;
$$;

create or replace function atlas.add_implementation_operating_knowledge_evidence_self_v1(
  p_implementation_case_id uuid,
  p_knowledge_id uuid,
  p_evidence_kind text,
  p_interpretation_kind text,
  p_source_locator jsonb default '{}'::jsonb,
  p_evidence_snapshot jsonb default '{}'::jsonb,
  p_note text default null,
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(
    select 1 from atlas.company_operating_knowledge k
    where k.id=p_knowledge_id and exists(select 1 from atlas.ledger_entitlements le join atlas.ledger_entitlement_bindings b on b.ledger_entitlement_id=le.id and b.ended_at is null where le.implementation_case_id=p_implementation_case_id and b.organization_id=k.organization_id and (k.organization_unit_id is null or k.organization_unit_id=b.organization_unit_id))
  ) then raise exception 'Operating knowledge not found in implementation scope.' using errcode='23503'; end if;
  v_id := atlas.company_operating_knowledge_add_evidence_internal_v1(p_knowledge_id,p_evidence_kind,p_interpretation_kind,p_source_locator,p_evidence_snapshot,p_note,p_observed_at,auth.uid());
  return jsonb_build_object('ok',true,'evidenceId',v_id);
end;
$$;

create or replace function atlas.adjudicate_implementation_operating_knowledge_self_v1(
  p_implementation_case_id uuid,
  p_knowledge_id uuid,
  p_decision_kind text,
  p_basis text,
  p_authority_label text,
  p_effective_from timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(
    select 1 from atlas.company_operating_knowledge k
    where k.id=p_knowledge_id and exists(select 1 from atlas.ledger_entitlements le join atlas.ledger_entitlement_bindings b on b.ledger_entitlement_id=le.id and b.ended_at is null where le.implementation_case_id=p_implementation_case_id and b.organization_id=k.organization_id and (k.organization_unit_id is null or k.organization_unit_id=b.organization_unit_id))
  ) then raise exception 'Operating knowledge not found in implementation scope.' using errcode='23503'; end if;
  return atlas.company_operating_knowledge_adjudicate_internal_v1(p_knowledge_id,p_decision_kind,p_basis,p_authority_label,auth.uid(),'implementation practitioner',p_effective_from);
end;
$$;

create or replace function atlas.replace_implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_knowledge_id uuid,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null,
  p_evidence_kind text default null,
  p_evidence_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_org uuid; v_unit uuid; v_prior atlas.company_operating_knowledge%rowtype; v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  select organization_id,organization_unit_id into v_org,v_unit from atlas.implementation_operating_scope_internal_v1(p_implementation_case_id,p_ledger_entitlement_id);
  if v_org is null then raise exception 'Active Ledger binding not found for implementation case.' using errcode='23503'; end if;
  select * into v_prior from atlas.company_operating_knowledge where id=p_knowledge_id and organization_id=v_org and organization_unit_id is not distinct from v_unit;
  if not found then raise exception 'Replacement source knowledge not found in Ledger scope.' using errcode='23503'; end if;
  v_id := atlas.company_operating_knowledge_propose_internal_v1(v_org,v_unit,v_prior.family_key,v_prior.stable_key,v_prior.knowledge_kind,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,v_prior.id,auth.uid(),'implementation practitioner','implementation_portal_replacement');
  if nullif(btrim(p_evidence_kind),'') is not null then
    perform atlas.company_operating_knowledge_add_evidence_internal_v1(v_id,p_evidence_kind,'originates',jsonb_build_object('implementationCaseId',p_implementation_case_id,'replacesKnowledgeId',p_knowledge_id),jsonb_build_object('statement',p_statement),p_evidence_note,now(),auth.uid());
  end if;
  return jsonb_build_object('ok',true,'knowledgeId',v_id,'replacesKnowledgeId',p_knowledge_id);
end;
$$;

-- Service/delegated-agent read and mutation seams. EXECUTE is service_role-only.
create or replace function atlas.company_operating_knowledge_service_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid default null,
  p_include_inherited boolean default true
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $$
  select jsonb_build_object('ok',true,'contractVersion','company_operating_knowledge_service_api_v1','items',coalesce(jsonb_agg(jsonb_build_object(
    'id',k.id,'organizationId',k.organization_id,'organizationUnitId',k.organization_unit_id,'familyKey',k.family_key,'stableKey',k.stable_key,'version',k.version,
    'knowledgeKind',k.knowledge_kind,'title',k.title,'statement',k.statement,'scopeMatch',k.scope_match,'effect',k.effect,'precedence',k.precedence,'status',k.status,
    'confidence',k.confidence,'effectiveFrom',k.effective_from,'effectiveTo',k.effective_to,'supersedesId',k.supersedes_id,'establishedByLabel',k.established_by_label,'establishedAt',k.established_at,
    'reviewAfter',k.review_after,'provenance',k.provenance,'metadata',k.metadata,'createdAt',k.created_at,'updatedAt',k.updated_at,
    'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'evidenceKind',e.evidence_kind,'interpretationKind',e.interpretation_kind,'sourceLocator',e.source_locator,'evidenceSnapshot',e.evidence_snapshot,'note',e.note,'observedAt',e.observed_at,'createdAt',e.created_at) order by e.created_at,e.id) from atlas.company_operating_knowledge_evidence e where e.knowledge_id=k.id),'[]'::jsonb),
    'adjudications',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'decisionKind',a.decision_kind,'basis',a.basis,'authorityLabel',a.adjudicated_by_label,'recordedByLabel',a.recorded_by_label,'createdAt',a.created_at) order by a.created_at,a.id) from atlas.company_operating_knowledge_adjudications a where a.knowledge_id=k.id),'[]'::jsonb)
  ) order by k.family_key,k.stable_key,k.version desc),'[]'::jsonb))
  from atlas.company_operating_knowledge k
  where k.organization_id=p_organization_id
    and ((p_organization_unit_id is null and k.organization_unit_id is null)
      or (p_organization_unit_id is not null and (k.organization_unit_id=p_organization_unit_id or (p_include_inherited and k.organization_unit_id is null))));
$$;

create or replace function atlas.propose_company_operating_knowledge_service_v1(
  p_organization_id uuid,p_organization_unit_id uuid,p_family_key text,p_stable_key text,p_knowledge_kind text,p_title text,p_statement text,p_scope_match jsonb,p_effect jsonb,
  p_recorded_by_label text,p_precedence integer default 0,p_confidence numeric default null,p_supersedes_id uuid default null,p_source text default 'delegated_service'
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $$
declare v_id uuid;
begin
  v_id:=atlas.company_operating_knowledge_propose_internal_v1(p_organization_id,p_organization_unit_id,p_family_key,p_stable_key,p_knowledge_kind,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,p_supersedes_id,null,p_recorded_by_label,p_source);
  return jsonb_build_object('ok',true,'knowledgeId',v_id);
end; $$;

create or replace function atlas.add_company_operating_knowledge_evidence_service_v1(
  p_knowledge_id uuid,p_evidence_kind text,p_interpretation_kind text,p_source_locator jsonb,p_evidence_snapshot jsonb,p_note text,p_observed_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $$
declare v_id uuid;
begin
  v_id:=atlas.company_operating_knowledge_add_evidence_internal_v1(p_knowledge_id,p_evidence_kind,p_interpretation_kind,p_source_locator,p_evidence_snapshot,p_note,p_observed_at,null);
  return jsonb_build_object('ok',true,'evidenceId',v_id);
end; $$;

create or replace function atlas.adjudicate_company_operating_knowledge_service_v1(
  p_knowledge_id uuid,p_decision_kind text,p_basis text,p_authority_label text,p_recorded_by_label text,p_effective_from timestamptz default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $$
begin
  return atlas.company_operating_knowledge_adjudicate_internal_v1(p_knowledge_id,p_decision_kind,p_basis,p_authority_label,null,p_recorded_by_label,p_effective_from);
end; $$;

-- Direct table access remains closed. Only the governed wrappers are granted.
revoke all on function atlas.company_operating_knowledge_propose_internal_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,uuid,uuid,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.company_operating_knowledge_add_evidence_internal_v1(uuid,text,text,jsonb,jsonb,text,timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.company_operating_knowledge_adjudicate_internal_v1(uuid,text,text,text,uuid,text,timestamptz) from public,anon,authenticated,service_role;
revoke all on function atlas.implementation_operating_scope_internal_v1(uuid,uuid) from public,anon,authenticated,service_role;

revoke all on function atlas.implementation_operating_knowledge_self_api_v1(uuid) from public,anon;
revoke all on function atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) from public,anon;
revoke all on function atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric) from public,anon;
revoke all on function atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz) from public,anon;
revoke all on function atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz) from public,anon;
revoke all on function atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) from public,anon;

grant execute on function atlas.implementation_operating_knowledge_self_api_v1(uuid) to authenticated;
grant execute on function atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;
grant execute on function atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric) to authenticated;
grant execute on function atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz) to authenticated;
grant execute on function atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz) to authenticated;
grant execute on function atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;

revoke all on function atlas.company_operating_knowledge_service_api_v1(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function atlas.propose_company_operating_knowledge_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,text,integer,numeric,uuid,text) from public,anon,authenticated;
revoke all on function atlas.add_company_operating_knowledge_evidence_service_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) from public,anon,authenticated;
revoke all on function atlas.adjudicate_company_operating_knowledge_service_v1(uuid,text,text,text,text,timestamptz) from public,anon,authenticated;

grant execute on function atlas.company_operating_knowledge_service_api_v1(uuid,uuid,boolean) to service_role;
grant execute on function atlas.propose_company_operating_knowledge_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,text,integer,numeric,uuid,text) to service_role;
grant execute on function atlas.add_company_operating_knowledge_evidence_service_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) to service_role;
grant execute on function atlas.adjudicate_company_operating_knowledge_service_v1(uuid,text,text,text,text,timestamptz) to service_role;

COMMIT;
