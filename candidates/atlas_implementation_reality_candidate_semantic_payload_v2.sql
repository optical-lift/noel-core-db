begin;

-- Atlas Implementation Reality Candidate Semantic Payload v2
--
-- Additive custody extension only.
--
-- Governing separation:
--   bindings          = which canonical/proposed things participate
--   semantic_payload  = operation-specific qualifiers that are part of meaning
--   evidence_refs     = what supports the candidate
--   establishment_basis = why establishment would be lawful
--   provenance        = how/where the candidate entered custody
--
-- This migration does not add a new establishment operation and does not
-- establish Organization, Organization Unit, Person, Position, Responsibility,
-- appointment, Work, authority, or any other client-domain truth.
--
-- v1 browser membranes remain unchanged. v2 is an additive membrane for later
-- structural promotion families that need explicit semantic qualifiers.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Reality Candidate custody v1 must be live before semantic payload v2.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'atlas.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'
  ) is null
     or to_regprocedure(
       'public.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'
     ) is null
     or to_regprocedure(
       'public.implementation_reality_candidates_self_api_v1(uuid)'
     ) is null then
    raise exception 'Reality Candidate v1 membranes must be live before semantic payload v2.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

alter table atlas.implementation_reality_candidates
  add column if not exists semantic_payload jsonb not null default '{}'::jsonb;

alter table atlas.implementation_reality_candidates
  drop constraint if exists implementation_reality_candidates_semantic_payload_object,
  add constraint implementation_reality_candidates_semantic_payload_object
    check (jsonb_typeof(semantic_payload)='object');

comment on column atlas.implementation_reality_candidates.semantic_payload is
  'Operation-specific semantic qualifiers that are part of the proposed reality itself but are not identity bindings, evidence, establishment authority, or provenance. Owning-domain promotion commands must validate any required keys and must never infer missing canonical qualifiers from this column being present.';

create or replace function atlas.guard_implementation_reality_candidate_semantic_payload_v2()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  if old.candidate_state='promoted'
     and new.semantic_payload is distinct from old.semantic_payload then
    raise exception 'Promoted Reality Candidate semantic payload is immutable provenance.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

revoke all on function atlas.guard_implementation_reality_candidate_semantic_payload_v2()
  from public,anon,authenticated,service_role;

drop trigger if exists implementation_reality_candidate_semantic_payload_guard_v2
  on atlas.implementation_reality_candidates;

create trigger implementation_reality_candidate_semantic_payload_guard_v2
before update of semantic_payload
on atlas.implementation_reality_candidates
for each row
execute function atlas.guard_implementation_reality_candidate_semantic_payload_v2();


create or replace function atlas.create_implementation_reality_candidate_self_api_v2(
  p_implementation_case_id uuid,
  p_operation_id text,
  p_origin_kind text,
  p_literal_statement text,
  p_subject_binding jsonb,
  p_implementation_thread_id uuid default null,
  p_object_binding jsonb default null,
  p_context_binding jsonb default null,
  p_semantic_payload jsonb default '{}'::jsonb,
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
  v_uid uuid:=auth.uid();
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    p_implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.implementation_cases c
    where c.id=p_implementation_case_id
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

  if p_semantic_payload is null
     or jsonb_typeof(p_semantic_payload)<>'object' then
    raise exception 'Reality Candidate semantic payload must be a JSON object.'
      using errcode='22023';
  end if;

  if p_evidence_refs is null
     or jsonb_typeof(p_evidence_refs)<>'array' then
    raise exception 'Evidence references must be a JSON array.'
      using errcode='22023';
  end if;

  insert into atlas.implementation_reality_candidates(
    implementation_case_id,
    implementation_thread_id,
    contract_version,
    operation_id,
    origin_kind,
    literal_statement,
    subject_binding,
    object_binding,
    context_binding,
    semantic_payload,
    evidence_refs,
    establishment_basis,
    candidate_state,
    author_user_id,
    provenance
  ) values (
    p_implementation_case_id,
    p_implementation_thread_id,
    'implementation_reality_candidate_v2',
    p_operation_id,
    p_origin_kind,
    btrim(p_literal_statement),
    p_subject_binding,
    p_object_binding,
    p_context_binding,
    p_semantic_payload,
    p_evidence_refs,
    p_establishment_basis,
    p_candidate_state,
    v_uid,
    jsonb_build_object(
      'source','create_implementation_reality_candidate_self_api_v2',
      'contractVersion','implementation_reality_candidate_v2',
      'actorKind','assigned_practitioner',
      'createdAt',now()
    )
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_candidate_v2',
    'candidateId',v_id,
    'candidateState',p_candidate_state,
    'semanticPayload',p_semantic_payload,
    'canonicalMutation',false
  );
end;
$function$;

revoke all on function atlas.create_implementation_reality_candidate_self_api_v2(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text
) from public,anon,authenticated,service_role;


create or replace function atlas.implementation_reality_candidates_self_api_v2(
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
      'contractVersion','implementation_reality_candidate_v2',
      'code','assigned_practitioner_authority_required',
      'items','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_candidate_v2',
    'items',
    coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id',c.id,
          'implementationCaseId',c.implementation_case_id,
          'implementationThreadId',c.implementation_thread_id,
          'candidateContractVersion',c.contract_version,
          'operationId',c.operation_id,
          'originKind',c.origin_kind,
          'literalStatement',c.literal_statement,
          'subjectBinding',c.subject_binding,
          'objectBinding',c.object_binding,
          'contextBinding',c.context_binding,
          'semanticPayload',c.semantic_payload,
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
      where c.implementation_case_id=p_implementation_case_id
        and c.candidate_state<>'superseded'
    ),'[]'::jsonb)
  );
end;
$function$;

revoke all on function atlas.implementation_reality_candidates_self_api_v2(uuid)
  from public,anon,authenticated,service_role;


create or replace function public.create_implementation_reality_candidate_self_api_v2(
  p_implementation_case_id uuid,
  p_operation_id text,
  p_origin_kind text,
  p_literal_statement text,
  p_subject_binding jsonb,
  p_implementation_thread_id uuid default null,
  p_object_binding jsonb default null,
  p_context_binding jsonb default null,
  p_semantic_payload jsonb default '{}'::jsonb,
  p_evidence_refs jsonb default '[]'::jsonb,
  p_establishment_basis jsonb default null,
  p_candidate_state text default 'proposed'
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.create_implementation_reality_candidate_self_api_v2(
    p_implementation_case_id,
    p_operation_id,
    p_origin_kind,
    p_literal_statement,
    p_subject_binding,
    p_implementation_thread_id,
    p_object_binding,
    p_context_binding,
    p_semantic_payload,
    p_evidence_refs,
    p_establishment_basis,
    p_candidate_state
  );
$function$;

create or replace function public.implementation_reality_candidates_self_api_v2(
  p_implementation_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_reality_candidates_self_api_v2(
    p_implementation_case_id
  );
$function$;

revoke all on function public.create_implementation_reality_candidate_self_api_v2(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text
) from public,anon,service_role;

revoke all on function public.implementation_reality_candidates_self_api_v2(uuid)
  from public,anon,service_role;

grant execute on function public.create_implementation_reality_candidate_self_api_v2(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text
) to authenticated;

grant execute on function public.implementation_reality_candidates_self_api_v2(uuid)
  to authenticated;

comment on function public.create_implementation_reality_candidate_self_api_v2(
  uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text
) is
  'Assigned-practitioner Reality Candidate v2 capture. semantic_payload holds operation-specific meaning distinct from identity bindings, evidence, establishment basis, and provenance. The membrane remains candidate-only and cannot establish canonical domain truth.';

comment on function public.implementation_reality_candidates_self_api_v2(uuid) is
  'Assigned-practitioner Reality Candidate v2 reader including semanticPayload. v1 candidates remain readable with the additive default empty semantic payload.';

commit;
