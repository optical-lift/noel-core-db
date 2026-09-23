begin;

-- Atlas Implementation Reality Responsibility Promotion Command v1.
-- Mutation-only owning-domain tranche for organization_responsibility.establish.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null
     or to_regclass('atlas.organization_responsibilities') is null then
    raise exception 'Reality Candidate and canonical Responsibility custody are required.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.render_organization_responsibility_reality_v1(uuid)') is null
     or to_regprocedure('atlas.preview_implementation_reality_responsibility_v1(uuid)') is null
     or to_regprocedure('public.preview_implementation_reality_responsibility_self_api_v1(uuid)') is null then
    raise exception 'Released Responsibility preview must exist before mutation.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null then
    raise exception 'Implementation practitioner authority is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

create or replace function atlas.establish_organization_responsibility_from_reality_v1(
  p_organization_id uuid,
  p_name text,
  p_responsibility_kind text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_name text:=btrim(coalesce(p_name,''));
  v_kind text:=btrim(coalesce(p_responsibility_kind,''));
  v_id uuid:=gen_random_uuid();
  v_stable_base text;
  v_stable_key text;
  v_existing atlas.organization_responsibilities%rowtype;
  v_record atlas.organization_responsibilities%rowtype;
begin
  if p_organization_id is null then
    raise exception 'Canonical Organization is required.' using errcode='22023';
  end if;
  if v_name='' then
    raise exception 'Responsibility name is required.' using errcode='22023';
  end if;
  if v_kind='' then
    raise exception 'Responsibility kind is required.' using errcode='22023';
  end if;
  if p_establishment_basis is null
     or jsonb_typeof(p_establishment_basis)<>'object' then
    raise exception 'Responsibility establishment basis must be a JSON object.'
      using errcode='22023';
  end if;

  if not exists(
    select 1 from atlas.organizations o
    where o.id=p_organization_id and o.status='active'
  ) then
    raise exception 'Active canonical Organization required.' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || '|' || lower(v_name),0)
  );

  select r.*
  into v_existing
  from atlas.organization_responsibilities r
  where r.organization_id=p_organization_id
    and lower(btrim(r.name))=lower(v_name)
  order by case when r.status='active' then 0 else 1 end,r.created_at,r.id
  limit 1
  for update;

  if v_existing.id is not null then
    if v_existing.status='active'
       and v_existing.responsibility_kind=v_kind then
      return jsonb_build_object(
        'state','unchanged',
        'consequenceKind','organization_responsibility',
        'responsibilityId',v_existing.id,
        'organizationId',v_existing.organization_id,
        'responsibilityKind',v_existing.responsibility_kind
      );
    end if;

    raise exception 'Responsibility identity conflicts with existing canonical structure.'
      using errcode='23514',
            detail='A Responsibility with the same name exists in this Organization with different kind or status.';
  end if;

  v_stable_base:=btrim(regexp_replace(lower(v_name),'[^a-z0-9]+','_','g'),'_');
  if v_stable_base='' then
    v_stable_base:='responsibility';
  end if;
  v_stable_key:=v_stable_base;

  if exists(
    select 1 from atlas.organization_responsibilities r
    where r.organization_id=p_organization_id
      and r.stable_key=v_stable_key
  ) then
    v_stable_key:=v_stable_base || '_' || substr(replace(v_id::text,'-',''),1,8);
  end if;

  insert into atlas.organization_responsibilities(
    id,organization_id,stable_key,name,responsibility_kind,status,metadata
  ) values (
    v_id,p_organization_id,v_stable_key,v_name,v_kind,'active',
    jsonb_build_object(
      'establishedBy','organization_responsibility_reality_promotion_v1',
      'establishmentBasis',p_establishment_basis
    )
  )
  returning * into v_record;

  return jsonb_build_object(
    'state','established',
    'consequenceKind','organization_responsibility',
    'responsibilityId',v_record.id,
    'organizationId',v_record.organization_id,
    'responsibilityKind',v_record.responsibility_kind,
    'stableKey',v_record.stable_key
  );
end;
$function$;

revoke all on function atlas.establish_organization_responsibility_from_reality_v1(uuid,text,text,jsonb)
  from public,anon,authenticated,service_role;

create or replace function atlas.promote_implementation_reality_responsibility_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_org_id uuid;
  v_name text;
  v_kind text;
  v_basis jsonb;
  v_receipt jsonb;
  v_responsibility_id uuid;
  v_render jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select c.*
  into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic
    on ic.id=c.implementation_case_id
   and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id
  for update of c;

  if v_candidate.id is null then
    raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    v_candidate.implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  if v_candidate.candidate_state='promoted' then
    if v_candidate.canonical_consequence_kind='organization_responsibility'
       and nullif(v_candidate.canonical_consequence_ref,'') is not null then
      begin
        v_responsibility_id:=v_candidate.canonical_consequence_ref::uuid;
      exception when invalid_text_representation then
        v_responsibility_id:=null;
      end;
    end if;

    if v_responsibility_id is not null then
      v_render:=atlas.render_organization_responsibility_reality_v1(v_responsibility_id);
    end if;

    return jsonb_build_object(
      'ok',true,'promoted',true,'alreadyPromoted',true,
      'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref,
      'realityEntry',v_render
    );
  end if;

  v_preview:=atlas.preview_implementation_reality_responsibility_v1(v_candidate.id);

  if v_preview->>'state'<>'ready' then
    if v_preview->>'state' in (
      'proposed_identity_required',
      'responsibility_name_required',
      'identity_resolution_required',
      'unexpected_context_binding',
      'canonical_binding_invalid',
      'canonical_organization_unavailable',
      'semantic_payload_invalid',
      'semantic_payload_required',
      'technical_identifier_not_allowed',
      'outside_implementation_scope',
      'canonical_scope_conflict',
      'setup_sponsor_authority_required',
      'canonical_identity_exists',
      'canonical_conflict'
    ) then
      update atlas.implementation_reality_candidates
      set candidate_state='unresolved',updated_at=now()
      where id=v_candidate.id;
    end if;

    return jsonb_build_object(
      'ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview
    );
  end if;

  v_org_id:=(v_candidate.object_binding->>'canonicalId')::uuid;
  v_name:=btrim(v_candidate.subject_binding->>'label');
  v_kind:=btrim(v_candidate.semantic_payload->>'responsibilityKind');

  v_basis:=coalesce(v_candidate.establishment_basis,'{}'::jsonb)
    || jsonb_build_object(
      'contractVersion','organization_responsibility_reality_promotion_v1',
      'source','implementation_reality_candidate',
      'implementationCaseId',v_candidate.implementation_case_id,
      'realityCandidateId',v_candidate.id,
      'candidateOrigin',v_candidate.origin_kind,
      'candidateAuthorUserId',v_candidate.author_user_id,
      'promotedByUserId',v_uid,
      'evidenceRefs',v_candidate.evidence_refs,
      'semanticPayload',v_candidate.semantic_payload,
      'scope',v_preview->'scope'
    );

  v_receipt:=atlas.establish_organization_responsibility_from_reality_v1(
    v_org_id,v_name,v_kind,v_basis
  );
  v_responsibility_id:=(v_receipt->>'responsibilityId')::uuid;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',
      canonical_consequence_kind='organization_responsibility',
      canonical_consequence_ref=v_responsibility_id::text,
      promoted_at=now(),
      promoted_by_user_id=v_uid,
      provenance=provenance || jsonb_build_object(
        'promotionContract','organization_responsibility_reality_promotion_v1',
        'promotionReceipt',v_receipt
      ),
      updated_at=now()
  where id=v_candidate.id;

  v_render:=atlas.render_organization_responsibility_reality_v1(v_responsibility_id);

  return jsonb_build_object(
    'ok',true,'promoted',true,'alreadyPromoted',false,
    'candidateId',v_candidate.id,
    'receipt',v_receipt,
    'canonicalConsequenceKind','organization_responsibility',
    'canonicalConsequenceRef',v_responsibility_id::text,
    'realityEntry',v_render
  );
end;
$function$;

revoke all on function atlas.promote_implementation_reality_responsibility_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.promote_implementation_reality_responsibility_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.promote_implementation_reality_responsibility_v1(p_candidate_id);
$function$;

revoke all on function public.promote_implementation_reality_responsibility_self_api_v1(uuid)
  from public,anon,service_role;
grant execute on function public.promote_implementation_reality_responsibility_self_api_v1(uuid)
  to authenticated;

comment on function public.promote_implementation_reality_responsibility_self_api_v1(uuid) is
  'Owning-domain Responsibility Reality promotion command. Reuses the released read-only preview, establishes Organization-scoped canonical Responsibility truth, records a receipt, and canonical-rerenders.';

commit;
