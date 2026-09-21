begin;

-- Atlas Implementation Reality Candidate Custody v1
--
-- Governing boundary:
--   human/source evidence -> typed proposed reality -> adjudication/preview
--   -> owning-domain command -> canonical consequence.
--
-- This migration does not establish Organization, Person, institutional-person,
-- Position, Responsibility, appointment, membership, work, authority, or any
-- other client-domain truth. It gives Implementation one durable typed custody
-- object for proposed Reality Sentences and removes the legacy practitioner
-- shortcut that could label free-text establishment items "established".

create table atlas.implementation_reality_candidates (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null
    references atlas.implementation_cases(id) on delete cascade,
  implementation_thread_id uuid null
    references atlas.implementation_threads(id) on delete restrict,

  contract_version text not null default 'implementation_reality_candidate_v1',
  operation_id text not null,
  origin_kind text not null,
  literal_statement text not null,

  subject_binding jsonb not null,
  object_binding jsonb null,
  context_binding jsonb null,
  evidence_refs jsonb not null default '[]'::jsonb,
  establishment_basis jsonb null,

  source_artifact_candidate_id uuid null
    references atlas.implementation_artifact_candidates(id) on delete restrict,

  candidate_state text not null default 'proposed',
  canonical_consequence_kind text null,
  canonical_consequence_ref text null,
  promoted_at timestamptz null,
  promoted_by_user_id uuid null references auth.users(id) on delete restrict,

  author_user_id uuid null references auth.users(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint implementation_reality_candidates_contract_nonblank
    check (btrim(contract_version) <> ''),

  constraint implementation_reality_candidates_operation_check
    check (operation_id in (
      'organization.establish',
      'person.establish',
      'institutional_person_record.establish',
      'organization_position.establish',
      'organization_responsibility.establish',
      'position_responsibility_definition.establish',
      'person_position_appointment.establish'
    )),

  constraint implementation_reality_candidates_origin_check
    check (origin_kind in (
      'manual_semantic_construction',
      'plain_language_capture',
      'ai_proposal',
      'source_derived'
    )),

  constraint implementation_reality_candidates_statement_check
    check (char_length(btrim(literal_statement)) between 1 and 4000),

  constraint implementation_reality_candidates_subject_binding_check
    check (
      jsonb_typeof(subject_binding) = 'object'
      and nullif(btrim(coalesce(subject_binding->>'kind','')),'') is not null
      and nullif(btrim(coalesce(subject_binding->>'label','')),'') is not null
      and coalesce(subject_binding->>'resolution','') in ('canonical','proposed','unresolved')
      and (
        coalesce(subject_binding->>'resolution','') <> 'canonical'
        or nullif(btrim(coalesce(subject_binding->>'canonicalId','')),'') is not null
      )
    ),

  constraint implementation_reality_candidates_object_binding_check
    check (
      object_binding is null
      or (
        jsonb_typeof(object_binding) = 'object'
        and nullif(btrim(coalesce(object_binding->>'kind','')),'') is not null
        and nullif(btrim(coalesce(object_binding->>'label','')),'') is not null
        and coalesce(object_binding->>'resolution','') in ('canonical','proposed','unresolved')
        and (
          coalesce(object_binding->>'resolution','') <> 'canonical'
          or nullif(btrim(coalesce(object_binding->>'canonicalId','')),'') is not null
        )
      )
    ),

  constraint implementation_reality_candidates_context_binding_check
    check (
      context_binding is null
      or (
        jsonb_typeof(context_binding) = 'object'
        and nullif(btrim(coalesce(context_binding->>'kind','')),'') is not null
        and nullif(btrim(coalesce(context_binding->>'label','')),'') is not null
        and coalesce(context_binding->>'resolution','') in ('canonical','proposed','unresolved')
        and (
          coalesce(context_binding->>'resolution','') <> 'canonical'
          or nullif(btrim(coalesce(context_binding->>'canonicalId','')),'') is not null
        )
      )
    ),

  constraint implementation_reality_candidates_evidence_refs_array
    check (jsonb_typeof(evidence_refs) = 'array'),

  constraint implementation_reality_candidates_basis_object
    check (establishment_basis is null or jsonb_typeof(establishment_basis) = 'object'),

  constraint implementation_reality_candidates_provenance_object
    check (jsonb_typeof(provenance) = 'object'),

  constraint implementation_reality_candidates_state_check
    check (candidate_state in (
      'proposed',
      'unresolved',
      'promoted',
      'rejected',
      'superseded'
    )),

  constraint implementation_reality_candidates_promotion_shape
    check (
      (
        candidate_state = 'promoted'
        and nullif(btrim(coalesce(canonical_consequence_kind,'')),'') is not null
        and nullif(btrim(coalesce(canonical_consequence_ref,'')),'') is not null
        and promoted_at is not null
      )
      or
      (
        candidate_state <> 'promoted'
        and canonical_consequence_kind is null
        and canonical_consequence_ref is null
        and promoted_at is null
        and promoted_by_user_id is null
      )
    ),

  constraint implementation_reality_candidates_operation_shape
    check (
      case operation_id
        when 'organization.establish' then
          subject_binding->>'kind' = 'organization'
          and object_binding is null
          and context_binding is null

        when 'person.establish' then
          subject_binding->>'kind' = 'person'
          and object_binding is null
          and context_binding is null

        when 'institutional_person_record.establish' then
          subject_binding->>'kind' = 'person'
          and object_binding is not null
          and object_binding->>'kind' = 'organization'
          and context_binding is null

        when 'organization_position.establish' then
          subject_binding->>'kind' = 'organization_position'
          and object_binding is not null
          and object_binding->>'kind' = 'organization'
          and context_binding is null

        when 'organization_responsibility.establish' then
          subject_binding->>'kind' = 'organization_responsibility'
          and object_binding is not null
          and object_binding->>'kind' = 'organization'
          and context_binding is null

        when 'position_responsibility_definition.establish' then
          subject_binding->>'kind' = 'organization_position'
          and object_binding is not null
          and object_binding->>'kind' = 'organization_responsibility'
          and context_binding is not null
          and context_binding->>'kind' = 'organization'

        when 'person_position_appointment.establish' then
          subject_binding->>'kind' = 'person'
          and object_binding is not null
          and object_binding->>'kind' = 'organization_position'
          and context_binding is not null
          and context_binding->>'kind' = 'organization'

        else false
      end
    )
);

comment on table atlas.implementation_reality_candidates is
  'Implementation-scoped typed custody for proposed Reality Sentences. Candidate custody is not canonical client-domain truth; only an owning-domain consequence may justify promoted state.';

comment on column atlas.implementation_reality_candidates.operation_id is
  'Typed semantic operation family shared with the Atlas Reality Sentence Establishment Registry. This is not an English-verb ontology.';

comment on column atlas.implementation_reality_candidates.origin_kind is
  'How the candidate entered Implementation. Manual construction, plain-language capture, AI proposal, and source-derived candidates share custody but retain distinct provenance.';

comment on column atlas.implementation_reality_candidates.canonical_consequence_ref is
  'Required only after a separate owning-domain command establishes canonical consequence. Candidate text itself never becomes the truth source.';

create index implementation_reality_candidates_case_state_idx
  on atlas.implementation_reality_candidates(
    implementation_case_id,
    candidate_state,
    created_at,
    id
  );

create index implementation_reality_candidates_thread_idx
  on atlas.implementation_reality_candidates(
    implementation_thread_id,
    created_at,
    id
  )
  where implementation_thread_id is not null;

create index implementation_reality_candidates_artifact_candidate_idx
  on atlas.implementation_reality_candidates(source_artifact_candidate_id)
  where source_artifact_candidate_id is not null;

alter table atlas.implementation_reality_candidates enable row level security;

revoke all on table atlas.implementation_reality_candidates
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_implementation_reality_candidate_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  if new.implementation_thread_id is not null
     and not exists (
       select 1
       from atlas.implementation_threads t
       where t.id = new.implementation_thread_id
         and t.implementation_case_id = new.implementation_case_id
     ) then
    raise exception 'Reality Candidate thread must belong to the same Implementation Case.'
      using errcode='23514';
  end if;

  if new.source_artifact_candidate_id is not null
     and not exists (
       select 1
       from atlas.implementation_artifact_candidates c
       join atlas.implementation_artifact_interpretations i
         on i.id = c.interpretation_id
       join atlas.implementation_artifacts a
         on a.id = i.implementation_artifact_id
       where c.id = new.source_artifact_candidate_id
         and a.implementation_case_id = new.implementation_case_id
     ) then
    raise exception 'Reality Candidate artifact source must belong to the same Implementation Case.'
      using errcode='23514';
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function atlas.guard_implementation_reality_candidate_scope_v1()
  from public, anon, authenticated, service_role;

create trigger implementation_reality_candidate_scope_guard_v1
before insert or update of
  implementation_case_id,
  implementation_thread_id,
  source_artifact_candidate_id
on atlas.implementation_reality_candidates
for each row
execute function atlas.guard_implementation_reality_candidate_scope_v1();


create or replace function atlas.create_implementation_reality_candidate_self_api_v1(
  p_implementation_case_id uuid,
  p_operation_id text,
  p_origin_kind text,
  p_literal_statement text,
  p_subject_binding jsonb,
  p_implementation_thread_id uuid default null,
  p_object_binding jsonb default null,
  p_context_binding jsonb default null,
  p_evidence_refs jsonb default '[]'::jsonb,
  p_establishment_basis jsonb default null,
  p_candidate_state text default 'proposed'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_id uuid;
  v_uid uuid := auth.uid();
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    p_implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.implementation_cases c
    where c.id = p_implementation_case_id
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Open Implementation Case required.'
      using errcode='23503';
  end if;

  if p_origin_kind not in (
    'manual_semantic_construction',
    'plain_language_capture'
  ) then
    raise exception 'Practitioner self authoring may create only manual or plain-language candidates.'
      using errcode='22023';
  end if;

  if p_candidate_state not in ('proposed','unresolved') then
    raise exception 'Practitioner self authoring may create only proposed or unresolved candidates.'
      using errcode='22023';
  end if;

  if p_evidence_refs is null or jsonb_typeof(p_evidence_refs) <> 'array' then
    raise exception 'Evidence references must be a JSON array.'
      using errcode='22023';
  end if;

  insert into atlas.implementation_reality_candidates(
    implementation_case_id,
    implementation_thread_id,
    operation_id,
    origin_kind,
    literal_statement,
    subject_binding,
    object_binding,
    context_binding,
    evidence_refs,
    establishment_basis,
    candidate_state,
    author_user_id,
    provenance
  ) values (
    p_implementation_case_id,
    p_implementation_thread_id,
    p_operation_id,
    p_origin_kind,
    btrim(p_literal_statement),
    p_subject_binding,
    p_object_binding,
    p_context_binding,
    p_evidence_refs,
    p_establishment_basis,
    p_candidate_state,
    v_uid,
    jsonb_build_object(
      'source','create_implementation_reality_candidate_self_api_v1',
      'contractVersion','implementation_reality_candidate_v1',
      'actorKind','assigned_practitioner',
      'createdAt',now()
    )
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_candidate_v1',
    'candidateId',v_id,
    'candidateState',p_candidate_state,
    'canonicalMutation',false
  );
end;
$function$;

revoke all on function atlas.create_implementation_reality_candidate_self_api_v1(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text
) from public, anon, authenticated, service_role;


create or replace function atlas.implementation_reality_candidates_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    p_implementation_case_id
  ) then
    return jsonb_build_object(
      'ok',false,
      'code','assigned_practitioner_authority_required',
      'items','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_candidate_v1',
    'items',
    coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id',c.id,
          'implementationCaseId',c.implementation_case_id,
          'implementationThreadId',c.implementation_thread_id,
          'operationId',c.operation_id,
          'originKind',c.origin_kind,
          'literalStatement',c.literal_statement,
          'subjectBinding',c.subject_binding,
          'objectBinding',c.object_binding,
          'contextBinding',c.context_binding,
          'evidenceRefs',c.evidence_refs,
          'establishmentBasis',c.establishment_basis,
          'sourceArtifactCandidateId',c.source_artifact_candidate_id,
          'candidateState',c.candidate_state,
          'canonicalConsequenceKind',c.canonical_consequence_kind,
          'canonicalConsequenceRef',c.canonical_consequence_ref,
          'promotedAt',c.promoted_at,
          'authorUserId',c.author_user_id,
          'provenance',c.provenance,
          'createdAt',c.created_at,
          'updatedAt',c.updated_at
        ))
        order by c.created_at,c.id
      )
      from atlas.implementation_reality_candidates c
      where c.implementation_case_id = p_implementation_case_id
        and c.candidate_state <> 'superseded'
    ),'[]'::jsonb)
  );
end;
$function$;

revoke all on function atlas.implementation_reality_candidates_self_api_v1(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.create_implementation_reality_candidate_self_api_v1(
  p_implementation_case_id uuid,
  p_operation_id text,
  p_origin_kind text,
  p_literal_statement text,
  p_subject_binding jsonb,
  p_implementation_thread_id uuid default null,
  p_object_binding jsonb default null,
  p_context_binding jsonb default null,
  p_evidence_refs jsonb default '[]'::jsonb,
  p_establishment_basis jsonb default null,
  p_candidate_state text default 'proposed'
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.create_implementation_reality_candidate_self_api_v1(
    p_implementation_case_id,
    p_operation_id,
    p_origin_kind,
    p_literal_statement,
    p_subject_binding,
    p_implementation_thread_id,
    p_object_binding,
    p_context_binding,
    p_evidence_refs,
    p_establishment_basis,
    p_candidate_state
  );
$function$;

create or replace function public.implementation_reality_candidates_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_reality_candidates_self_api_v1(
    p_implementation_case_id
  );
$function$;

revoke all on function public.create_implementation_reality_candidate_self_api_v1(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text
) from public, anon;

revoke all on function public.implementation_reality_candidates_self_api_v1(uuid)
  from public, anon;

grant execute on function public.create_implementation_reality_candidate_self_api_v1(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text
) to authenticated;

grant execute on function public.implementation_reality_candidates_self_api_v1(uuid)
  to authenticated;

comment on function public.create_implementation_reality_candidate_self_api_v1(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text
) is
  'Assigned-practitioner manual Reality Candidate capture. It may persist proposed/unresolved typed reality only and cannot establish canonical domain truth.';

comment on function public.implementation_reality_candidates_self_api_v1(uuid) is
  'Assigned-practitioner read membrane for typed Implementation Reality Candidates.';


-- Repair the pre-Reality-Sentence compatibility writer.
--
-- Historical rows with status=established are preserved. New practitioner
-- self-service writes may no longer manufacture that status from free text.
-- Canonical establishment must instead be represented by an owning-domain
-- consequence and then projected back to Implementation.
create or replace function atlas.save_implementation_establishment_item_self_api_v1(
  p_implementation_case_id uuid,
  p_category text,
  p_title text,
  p_detail text default '',
  p_status text default 'proposed'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.implementation_cases c
    where c.id=p_implementation_case_id
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Open implementation case not found.'
      using errcode='23503';
  end if;

  if p_category not in (
    'institution',
    'ledger_scope',
    'people_authority',
    'implementation_authority',
    'boundary',
    'unresolved'
  ) then
    raise exception 'Invalid establishment category.'
      using errcode='22023';
  end if;

  if p_status not in ('proposed','unresolved') then
    raise exception 'Implementation text may be proposed or unresolved only; established reality requires an owning-domain canonical consequence.'
      using errcode='22023';
  end if;

  insert into atlas.implementation_establishment_items(
    implementation_case_id,
    category,
    title,
    detail,
    status,
    author_user_id,
    basis
  ) values (
    p_implementation_case_id,
    p_category,
    btrim(p_title),
    coalesce(p_detail,''),
    p_status,
    auth.uid(),
    jsonb_build_object(
      'source','practitioner_workbench',
      'authorityBoundary','candidate_only_after_reality_sentence_v1'
    )
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'id',v_id,
    'status',p_status,
    'canonicalMutation',false
  );
end;
$function$;

revoke all on function atlas.save_implementation_establishment_item_self_api_v1(
  uuid,text,text,text,text
) from public, anon, authenticated, service_role;

comment on function atlas.save_implementation_establishment_item_self_api_v1(
  uuid,text,text,text,text
) is
  'Legacy Implementation establishment-item writer retained for compatibility. Practitioner input may persist only proposed/unresolved material; established status is no longer a self-service text authority.';

comment on table atlas.implementation_establishment_items is
  'Legacy Implementation coordination material. Historical established rows are preserved, but new practitioner text cannot become canonical truth through this table; Reality Candidate promotion must resolve through an owning-domain consequence.';

commit;
