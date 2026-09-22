begin;

-- Atlas Implementation Finding Adjudication v1
--
-- Establish immutable review evidence for IMP-04 without allowing a Finding
-- status update to masquerade as owning-domain truth.
--
-- This tranche does not publish a Client Operating Model and does not execute
-- any domain mutation.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_findings') is null
     or to_regclass('atlas.implementation_threads') is null
     or to_regclass('atlas.implementation_cases') is null then
    raise exception 'Implementation Case/Thread/Finding custody must be live before Finding adjudication.'
      using errcode='0A000';
  end if;

  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Implementation Reality Candidate custody must be live before Finding adjudication.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null then
    raise exception 'Case-assigned practitioner authority is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;


create table if not exists atlas.implementation_finding_adjudications (
  id uuid primary key default gen_random_uuid(),
  implementation_finding_id uuid not null
    references atlas.implementation_findings(id) on delete restrict,
  implementation_thread_id uuid not null
    references atlas.implementation_threads(id) on delete restrict,
  implementation_case_id uuid not null
    references atlas.implementation_cases(id) on delete restrict,

  request_id uuid not null unique,
  adjudication_number integer not null check (adjudication_number > 0),

  finding_statement_snapshot text not null
    check (char_length(btrim(finding_statement_snapshot)) between 1 and 4000),

  finding_class text not null
    check (finding_class in (
      'configuration_crosswalk',
      'existing_domain_fact',
      'proposed_repair',
      'decision_authority_fact',
      'privacy_custody_boundary',
      'activation_risk_acceptance',
      'unresolved_structure'
    )),

  decision text not null
    check (decision in (
      'govern_for_model',
      'keep_proposed',
      'mark_unresolved',
      'reject',
      'supersede'
    )),

  prior_status text not null
    check (prior_status in (
      'proposed',
      'governed',
      'rejected',
      'superseded',
      'unresolved'
    )),

  resulting_status text not null
    check (resulting_status in (
      'proposed',
      'governed',
      'rejected',
      'superseded',
      'unresolved'
    )),

  model_eligible boolean not null default false,

  linked_reality_candidate_id uuid
    references atlas.implementation_reality_candidates(id) on delete restrict,

  superseding_finding_id uuid
    references atlas.implementation_findings(id) on delete restrict,

  basis text not null
    check (char_length(btrim(basis)) between 1 and 4000),

  evidence_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence_snapshot)='object'),

  governing_policy text not null
    check (char_length(btrim(governing_policy)) between 1 and 240),

  reviewed_by_user_id uuid not null
    references auth.users(id) on delete restrict,

  previous_adjudication_id uuid
    references atlas.implementation_finding_adjudications(id) on delete restrict,

  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),

  created_at timestamptz not null default now(),

  constraint implementation_finding_adjudications_model_shape
    check (
      (model_eligible and decision='govern_for_model')
      or (not model_eligible)
    ),

  constraint implementation_finding_adjudications_govern_class
    check (
      decision<>'govern_for_model'
      or finding_class in ('configuration_crosswalk','existing_domain_fact')
    ),

  constraint implementation_finding_adjudications_domain_fact_shape
    check (
      (
        decision='govern_for_model'
        and finding_class='existing_domain_fact'
        and linked_reality_candidate_id is not null
      )
      or
      (
        not (decision='govern_for_model' and finding_class='existing_domain_fact')
        and linked_reality_candidate_id is null
      )
    ),

  constraint implementation_finding_adjudications_supersede_shape
    check (
      (decision='supersede' and superseding_finding_id is not null)
      or
      (decision<>'supersede' and superseding_finding_id is null)
    ),

  constraint implementation_finding_adjudications_status_mapping
    check (
      (decision='govern_for_model' and resulting_status='governed')
      or (decision='keep_proposed' and resulting_status='proposed')
      or (decision='mark_unresolved' and resulting_status='unresolved')
      or (decision='reject' and resulting_status='rejected')
      or (decision='supersede' and resulting_status='superseded')
    )
);

comment on table atlas.implementation_finding_adjudications is
  'Append-only Implementation Finding review evidence. Governing a Finding for model use does not establish owning-domain truth; existing-domain facts require a separately promoted same-case Reality Candidate.';

comment on column atlas.implementation_finding_adjudications.model_eligible is
  'Whether this exact adjudication may be consumed by a future Client Operating Model. This is implementation-configuration eligibility, not domain establishment authority.';

comment on column atlas.implementation_finding_adjudications.linked_reality_candidate_id is
  'Required only when an existing-domain fact is governed for model use. The linked Reality Candidate must already be promoted through its owning-domain consequence.';

create unique index if not exists implementation_finding_adjudications_number_uq
  on atlas.implementation_finding_adjudications(
    implementation_finding_id,
    adjudication_number
  );

create index if not exists implementation_finding_adjudications_finding_idx
  on atlas.implementation_finding_adjudications(
    implementation_finding_id,
    adjudication_number
  );

create index if not exists implementation_finding_adjudications_case_idx
  on atlas.implementation_finding_adjudications(
    implementation_case_id,
    created_at,
    id
  );

create index if not exists implementation_finding_adjudications_model_idx
  on atlas.implementation_finding_adjudications(
    implementation_case_id,
    model_eligible,
    created_at,
    id
  )
  where model_eligible;

alter table atlas.implementation_finding_adjudications enable row level security;

revoke all on table atlas.implementation_finding_adjudications
  from public, anon, authenticated, service_role;


create or replace function atlas.reject_implementation_finding_adjudication_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Implementation Finding adjudications are append-only.'
    using errcode='42501';
end;
$function$;

revoke all on function atlas.reject_implementation_finding_adjudication_mutation_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists implementation_finding_adjudications_immutable_v1
  on atlas.implementation_finding_adjudications;

create trigger implementation_finding_adjudications_immutable_v1
before update or delete on atlas.implementation_finding_adjudications
for each row
execute function atlas.reject_implementation_finding_adjudication_mutation_v1();


create or replace function atlas.implementation_finding_model_eligible_v1(
  p_implementation_finding_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select coalesce((
    select
      f.status='governed'
      and a.model_eligible
      and a.resulting_status='governed'
    from atlas.implementation_findings f
    join lateral (
      select a.*
      from atlas.implementation_finding_adjudications a
      where a.implementation_finding_id=f.id
      order by a.adjudication_number desc
      limit 1
    ) a on true
    where f.id=p_implementation_finding_id
  ),false);
$function$;

revoke all on function atlas.implementation_finding_model_eligible_v1(uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.adjudicate_implementation_finding_self_api_v1(
  p_implementation_finding_id uuid,
  p_finding_class text,
  p_decision text,
  p_basis text,
  p_evidence_snapshot jsonb,
  p_governing_policy text,
  p_linked_reality_candidate_id uuid,
  p_superseding_finding_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_existing atlas.implementation_finding_adjudications%rowtype;
  v_finding atlas.implementation_findings%rowtype;
  v_case_id uuid;
  v_previous_adjudication_id uuid;
  v_previous_adjudication_number integer;
  v_adjudication_number integer;
  v_reality atlas.implementation_reality_candidates%rowtype;
  v_resulting_status text;
  v_model_eligible boolean := false;
  v_adjudication_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_request_id is null then
    raise exception 'Adjudication request id required.' using errcode='22023';
  end if;

  if p_finding_class is null
     or p_finding_class not in (
    'configuration_crosswalk',
    'existing_domain_fact',
    'proposed_repair',
    'decision_authority_fact',
    'privacy_custody_boundary',
    'activation_risk_acceptance',
    'unresolved_structure'
  ) then
    raise exception 'Unsupported Implementation Finding class.'
      using errcode='22023';
  end if;

  if p_decision is null
     or p_decision not in (
    'govern_for_model',
    'keep_proposed',
    'mark_unresolved',
    'reject',
    'supersede'
  ) then
    raise exception 'Unsupported Implementation Finding adjudication decision.'
      using errcode='22023';
  end if;

  if char_length(btrim(coalesce(p_basis,''))) not between 1 and 4000 then
    raise exception 'Adjudication basis must be between 1 and 4000 characters.'
      using errcode='22023';
  end if;

  if p_evidence_snapshot is null
     or jsonb_typeof(p_evidence_snapshot)<>'object' then
    raise exception 'Adjudication evidence snapshot must be a JSON object.'
      using errcode='22023';
  end if;

  if char_length(btrim(coalesce(p_governing_policy,''))) not between 1 and 240 then
    raise exception 'Governing policy is required.'
      using errcode='22023';
  end if;

  -- Resolve exact Case custody and authority before even an idempotent replay
  -- may disclose an earlier adjudication receipt.
  select f.*
  into v_finding
  from atlas.implementation_findings f
  where f.id=p_implementation_finding_id;

  if v_finding.id is null then
    raise exception 'Implementation Finding not found.'
      using errcode='23503';
  end if;

  select t.implementation_case_id
  into v_case_id
  from atlas.implementation_threads t
  where t.id=v_finding.implementation_thread_id;

  if v_case_id is null
     or not exists (
       select 1
       from atlas.implementation_cases c
       where c.id=v_case_id
         and c.state not in ('closed','cancelled')
     ) then
    raise exception 'Open Implementation Case required.'
      using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_case_id) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  select a.*
  into v_existing
  from atlas.implementation_finding_adjudications a
  where a.request_id=p_request_id;

  if v_existing.id is not null then
    if v_existing.implementation_finding_id is distinct from p_implementation_finding_id
       or v_existing.finding_class is distinct from p_finding_class
       or v_existing.decision is distinct from p_decision
       or v_existing.basis is distinct from btrim(p_basis)
       or v_existing.evidence_snapshot is distinct from p_evidence_snapshot
       or v_existing.governing_policy is distinct from btrim(p_governing_policy)
       or v_existing.linked_reality_candidate_id is distinct from p_linked_reality_candidate_id
       or v_existing.superseding_finding_id is distinct from p_superseding_finding_id
       or v_existing.reviewed_by_user_id is distinct from v_uid then
      raise exception 'Adjudication request id was already used with different semantics.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_finding_adjudication_v1',
      'alreadyAdjudicated',true,
      'adjudicationId',v_existing.id,
      'adjudicationNumber',v_existing.adjudication_number,
      'findingId',v_existing.implementation_finding_id,
      'findingStatus',v_existing.resulting_status,
      'modelEligible',v_existing.model_eligible,
      'canonicalDomainMutation',false
    );
  end if;

  -- Serialize new adjudications for one Finding so adjudication_number and the
  -- previous-adjudication chain remain deterministic.
  select f.*
  into v_finding
  from atlas.implementation_findings f
  where f.id=p_implementation_finding_id
  for update;

  if v_finding.status in ('rejected','superseded') then
    raise exception 'Rejected or superseded Findings are terminal for this adjudication seam.'
      using errcode='23514';
  end if;

  if v_finding.status='governed' and p_decision='keep_proposed' then
    raise exception 'A governed Finding may not be silently downgraded to proposed.'
      using errcode='23514';
  end if;

  if p_decision='govern_for_model'
     and p_finding_class not in ('configuration_crosswalk','existing_domain_fact') then
    raise exception 'This Finding class requires a stronger authority path before model use.'
      using errcode='42501';
  end if;

  if p_finding_class='configuration_crosswalk'
     and p_linked_reality_candidate_id is not null then
    raise exception 'Configuration crosswalk adjudication must not borrow a domain consequence.'
      using errcode='23514';
  end if;

  if p_decision='govern_for_model'
     and p_finding_class='existing_domain_fact' then

    if p_linked_reality_candidate_id is null then
      raise exception 'Existing-domain fact requires a promoted Reality Candidate.'
        using errcode='23514';
    end if;

    select rc.*
    into v_reality
    from atlas.implementation_reality_candidates rc
    where rc.id=p_linked_reality_candidate_id
      and rc.implementation_case_id=v_case_id
      and (
        rc.implementation_thread_id is null
        or rc.implementation_thread_id=v_finding.implementation_thread_id
      )
      and rc.candidate_state='promoted'
      and nullif(btrim(coalesce(rc.canonical_consequence_kind,'')),'') is not null
      and nullif(btrim(coalesce(rc.canonical_consequence_ref,'')),'') is not null;

    if v_reality.id is null then
      raise exception 'Promoted same-case Reality Candidate with canonical consequence required.'
        using errcode='23514';
    end if;
  elsif p_linked_reality_candidate_id is not null then
    raise exception 'Linked Reality Candidate is only valid for governed existing-domain facts.'
      using errcode='23514';
  end if;

  if p_decision='supersede' then
    if p_superseding_finding_id is null
       or p_superseding_finding_id=p_implementation_finding_id
       or not exists (
         select 1
         from atlas.implementation_findings sf
         join atlas.implementation_threads st
           on st.id=sf.implementation_thread_id
         where sf.id=p_superseding_finding_id
           and st.implementation_case_id=v_case_id
           and sf.status not in ('rejected','superseded')
       ) then
      raise exception 'Supersede requires a distinct live Finding in the same Implementation Case.'
        using errcode='23514';
    end if;
  elsif p_superseding_finding_id is not null then
    raise exception 'Superseding Finding is valid only for supersede decisions.'
      using errcode='23514';
  end if;

  select a.id,a.adjudication_number
  into v_previous_adjudication_id,v_previous_adjudication_number
  from atlas.implementation_finding_adjudications a
  where a.implementation_finding_id=v_finding.id
  order by a.adjudication_number desc
  limit 1;

  v_adjudication_number := coalesce(v_previous_adjudication_number,0)+1;

  v_resulting_status := case p_decision
    when 'govern_for_model' then 'governed'
    when 'keep_proposed' then 'proposed'
    when 'mark_unresolved' then 'unresolved'
    when 'reject' then 'rejected'
    when 'supersede' then 'superseded'
  end;

  v_model_eligible := p_decision='govern_for_model';

  insert into atlas.implementation_finding_adjudications(
    implementation_finding_id,
    implementation_thread_id,
    implementation_case_id,
    request_id,
    adjudication_number,
    finding_statement_snapshot,
    finding_class,
    decision,
    prior_status,
    resulting_status,
    model_eligible,
    linked_reality_candidate_id,
    superseding_finding_id,
    basis,
    evidence_snapshot,
    governing_policy,
    reviewed_by_user_id,
    previous_adjudication_id,
    provenance
  ) values (
    v_finding.id,
    v_finding.implementation_thread_id,
    v_case_id,
    p_request_id,
    v_adjudication_number,
    v_finding.statement,
    p_finding_class,
    p_decision,
    v_finding.status,
    v_resulting_status,
    v_model_eligible,
    p_linked_reality_candidate_id,
    p_superseding_finding_id,
    btrim(p_basis),
    p_evidence_snapshot,
    btrim(p_governing_policy),
    v_uid,
    v_previous_adjudication_id,
    jsonb_build_object(
      'source','adjudicate_implementation_finding_self_api_v1',
      'contractVersion','implementation_finding_adjudication_v1',
      'canonicalDomainMutation',false,
      'createdAt',now()
    )
  )
  returning id into v_adjudication_id;

  update atlas.implementation_findings
  set status=v_resulting_status,
      updated_at=now()
  where id=v_finding.id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_finding_adjudication_v1',
    'alreadyAdjudicated',false,
    'adjudicationId',v_adjudication_id,
    'adjudicationNumber',v_adjudication_number,
    'findingId',v_finding.id,
    'findingStatus',v_resulting_status,
    'modelEligible',v_model_eligible,
    'linkedRealityCandidateId',p_linked_reality_candidate_id,
    'canonicalDomainMutation',false
  );
end;
$function$;

revoke all on function atlas.adjudicate_implementation_finding_self_api_v1(
  uuid,text,text,text,jsonb,text,uuid,uuid,uuid
) from public, anon, authenticated, service_role;


create or replace function atlas.implementation_finding_review_self_api_v1(
  p_implementation_finding_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_finding atlas.implementation_findings%rowtype;
  v_case_id uuid;
  v_thread_title text;
  v_work_area text;
begin
  select f.*
  into v_finding
  from atlas.implementation_findings f
  where f.id=p_implementation_finding_id;

  if v_finding.id is null then
    return jsonb_build_object(
      'ok',false,
      'code','finding_not_found'
    );
  end if;

  select t.implementation_case_id,t.title,t.work_area
  into v_case_id,v_thread_title,v_work_area
  from atlas.implementation_threads t
  where t.id=v_finding.implementation_thread_id;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_case_id) then
    return jsonb_build_object(
      'ok',false,
      'code','assigned_practitioner_authority_required'
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_finding_adjudication_v1',
    'finding',jsonb_build_object(
      'id',v_finding.id,
      'implementationCaseId',v_case_id,
      'implementationThreadId',v_finding.implementation_thread_id,
      'threadTitle',v_thread_title,
      'workArea',v_work_area,
      'statement',v_finding.statement,
      'status',v_finding.status,
      'authorUserId',v_finding.author_user_id,
      'createdAt',v_finding.created_at,
      'updatedAt',v_finding.updated_at,
      'modelEligible',atlas.implementation_finding_model_eligible_v1(v_finding.id)
    ),
    'adjudications',coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id',a.id,
          'requestId',a.request_id,
          'adjudicationNumber',a.adjudication_number,
          'findingClass',a.finding_class,
          'decision',a.decision,
          'priorStatus',a.prior_status,
          'resultingStatus',a.resulting_status,
          'modelEligible',a.model_eligible,
          'linkedRealityCandidateId',a.linked_reality_candidate_id,
          'supersedingFindingId',a.superseding_finding_id,
          'basis',a.basis,
          'evidenceSnapshot',a.evidence_snapshot,
          'governingPolicy',a.governing_policy,
          'reviewedByUserId',a.reviewed_by_user_id,
          'previousAdjudicationId',a.previous_adjudication_id,
          'provenance',a.provenance,
          'createdAt',a.created_at
        ))
        order by a.adjudication_number
      )
      from atlas.implementation_finding_adjudications a
      where a.implementation_finding_id=v_finding.id
    ),'[]'::jsonb)
  );
end;
$function$;

revoke all on function atlas.implementation_finding_review_self_api_v1(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.adjudicate_implementation_finding_self_api_v1(
  p_implementation_finding_id uuid,
  p_finding_class text,
  p_decision text,
  p_basis text,
  p_evidence_snapshot jsonb,
  p_governing_policy text,
  p_linked_reality_candidate_id uuid,
  p_superseding_finding_id uuid,
  p_request_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.adjudicate_implementation_finding_self_api_v1(
    p_implementation_finding_id,
    p_finding_class,
    p_decision,
    p_basis,
    p_evidence_snapshot,
    p_governing_policy,
    p_linked_reality_candidate_id,
    p_superseding_finding_id,
    p_request_id
  );
$function$;

create or replace function public.implementation_finding_review_self_api_v1(
  p_implementation_finding_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_finding_review_self_api_v1(
    p_implementation_finding_id
  );
$function$;

revoke all on function public.adjudicate_implementation_finding_self_api_v1(
  uuid,text,text,text,jsonb,text,uuid,uuid,uuid
) from public, anon, service_role;

revoke all on function public.implementation_finding_review_self_api_v1(uuid)
  from public, anon, service_role;

grant execute on function public.adjudicate_implementation_finding_self_api_v1(
  uuid,text,text,text,jsonb,text,uuid,uuid,uuid
) to authenticated;

grant execute on function public.implementation_finding_review_self_api_v1(uuid)
  to authenticated;

comment on function public.adjudicate_implementation_finding_self_api_v1(
  uuid,text,text,text,jsonb,text,uuid,uuid,uuid
) is
  'Case-assigned practitioner IMP-04 adjudication. Creates append-only review evidence and updates Finding status projection. It never establishes owning-domain truth; existing-domain facts require an already-promoted same-case Reality Candidate.';

comment on function public.implementation_finding_review_self_api_v1(uuid) is
  'Case-assigned practitioner read membrane for one Implementation Finding and its immutable adjudication history.';

commit;
