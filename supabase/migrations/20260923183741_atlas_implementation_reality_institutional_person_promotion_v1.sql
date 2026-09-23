begin;

-- Atlas Implementation Reality Institutional Person Promotion Command v1
--
-- MUTATION-ONLY command tranche for the first Reality Candidate promotion.
--
-- The read-only readiness membrane must already be live:
--   atlas.render_institutional_person_reality_consequence_v1(uuid)
--   atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
--   public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
--
-- This package does not define or replace preview. It adds only the owning
-- Institutional Person establishment helper and the governed promotion writer.
-- The public preview detects this command dynamically and sets
-- promotionCommandAvailable/canExecutePromotion accordingly.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Reality Candidate custody must be live before Institutional Person promotion.'
      using errcode='0A000';
  end if;

  if to_regclass('atlas.institutional_person_records') is null then
    raise exception 'Institutional Person Record must be live before Reality Candidate promotion.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'atlas.render_institutional_person_reality_consequence_v1(uuid)'
  ) is null then
    raise exception 'Canonical Institutional Person consequence renderer must be live before promotion.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Read-only Reality Candidate promotion preview must be live before promotion.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Reality Candidate promotion preview membrane must be live before promotion.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null then
    raise exception 'Implementation practitioner case authority is unavailable.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.principal_has_ledger_authority_v1(uuid,uuid)') is null then
    raise exception 'Principal Ledger authority resolver is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

create or replace function atlas.establish_institutional_person_from_reality_internal_v1(
  p_organization_id uuid,
  p_person_id uuid,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_record atlas.institutional_person_records%rowtype;
begin
  if p_organization_id is null or p_person_id is null then
    raise exception 'Canonical Organization and Person are required.'
      using errcode='22023';
  end if;

  if p_establishment_basis is null
     or jsonb_typeof(p_establishment_basis)<>'object' then
    raise exception 'Institutional Person establishment basis must be a JSON object.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.organizations o
    where o.id=p_organization_id
      and o.status='active'
  ) then
    raise exception 'Active canonical Organization required.'
      using errcode='23503';
  end if;

  if not exists(
    select 1
    from atlas.people p
    where p.id=p_person_id
      and p.status='active'
  ) then
    raise exception 'Active canonical Person required.'
      using errcode='23503';
  end if;

  select *
  into v_record
  from atlas.institutional_person_records ipr
  where ipr.organization_id=p_organization_id
    and ipr.person_id=p_person_id
  for update;

  if v_record.id is not null then
    if v_record.status<>'active' then
      raise exception 'Institutional Person Record exists but is not active.'
        using errcode='23514';
    end if;

    return jsonb_build_object(
      'state','unchanged',
      'consequenceKind','institutional_person_record',
      'institutionalPersonRecordId',v_record.id,
      'organizationId',p_organization_id,
      'personId',p_person_id
    );
  end if;

  insert into atlas.institutional_person_records(
    organization_id,
    person_id,
    status,
    establishment_basis
  ) values (
    p_organization_id,
    p_person_id,
    'active',
    p_establishment_basis || jsonb_build_object(
      'source','establish_institutional_person_from_reality_internal_v1',
      'contractVersion','institutional_person_reality_promotion_v1'
    )
  )
  on conflict (organization_id,person_id) do nothing
  returning * into v_record;

  if v_record.id is null then
    select *
    into v_record
    from atlas.institutional_person_records ipr
    where ipr.organization_id=p_organization_id
      and ipr.person_id=p_person_id;

    if v_record.id is null or v_record.status<>'active' then
      raise exception 'Concurrent Institutional Person establishment did not resolve to an active canonical record.'
        using errcode='23514';
    end if;

    return jsonb_build_object(
      'state','unchanged',
      'consequenceKind','institutional_person_record',
      'institutionalPersonRecordId',v_record.id,
      'organizationId',p_organization_id,
      'personId',p_person_id
    );
  end if;

  return jsonb_build_object(
    'state','established',
    'consequenceKind','institutional_person_record',
    'institutionalPersonRecordId',v_record.id,
    'organizationId',p_organization_id,
    'personId',p_person_id
  );
end;
$function$;

revoke all on function atlas.establish_institutional_person_from_reality_internal_v1(
  uuid,uuid,jsonb
) from public, anon, authenticated, service_role;



create or replace function atlas.promote_implementation_reality_candidate_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_person_id uuid;
  v_organization_id uuid;
  v_receipt jsonb;
  v_record_id uuid;
  v_basis jsonb;
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
    raise exception 'Open Implementation Reality Candidate not found.'
      using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    v_candidate.implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  if v_candidate.candidate_state='promoted' then
    if v_candidate.canonical_consequence_kind='institutional_person_record' then
      begin
        v_record_id:=v_candidate.canonical_consequence_ref::uuid;
      exception when invalid_text_representation then
        v_record_id:=null;
      end;
    end if;

    if v_record_id is not null then
      v_render:=atlas.render_institutional_person_reality_consequence_v1(v_record_id);
    end if;

    return jsonb_build_object(
      'ok',true,
      'promoted',true,
      'alreadyPromoted',true,
      'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref,
      'realityEntry',v_render
    );
  end if;

  v_preview:=atlas.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate.id
  );

  if v_preview->>'state'<>'ready' then
    if v_preview->>'state' in (
      'identity_resolution_required',
      'canonical_binding_invalid',
      'canonical_person_unavailable',
      'canonical_organization_unavailable',
      'outside_implementation_scope',
      'canonical_scope_conflict',
      'setup_sponsor_authority_required',
      'establishment_basis_required',
      'canonical_conflict'
    ) then
      update atlas.implementation_reality_candidates
      set candidate_state='unresolved',
          updated_at=now()
      where id=v_candidate.id;
    end if;

    return jsonb_build_object(
      'ok',false,
      'promoted',false,
      'candidateId',v_candidate.id,
      'preview',v_preview
    );
  end if;

  v_person_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
  v_organization_id:=(v_candidate.object_binding->>'canonicalId')::uuid;

  v_basis:=v_candidate.establishment_basis
    || jsonb_build_object(
      'contractVersion','institutional_person_reality_promotion_v1',
      'source','implementation_reality_candidate',
      'implementationCaseId',v_candidate.implementation_case_id,
      'realityCandidateId',v_candidate.id,
      'candidateOrigin',v_candidate.origin_kind,
      'candidateAuthorUserId',v_candidate.author_user_id,
      'promotedByUserId',v_uid,
      'evidenceRefs',v_candidate.evidence_refs,
      'scope',v_preview->'scope'
    );

  v_receipt:=atlas.establish_institutional_person_from_reality_internal_v1(
    v_organization_id,
    v_person_id,
    v_basis
  );

  v_record_id:=(v_receipt->>'institutionalPersonRecordId')::uuid;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',
      canonical_consequence_kind='institutional_person_record',
      canonical_consequence_ref=v_record_id::text,
      promoted_at=now(),
      promoted_by_user_id=v_uid,
      provenance=provenance || jsonb_build_object(
        'promotionContract','institutional_person_reality_promotion_v1',
        'promotionReceipt',v_receipt
      ),
      updated_at=now()
  where id=v_candidate.id;

  v_render:=atlas.render_institutional_person_reality_consequence_v1(v_record_id);

  return jsonb_build_object(
    'ok',true,
    'promoted',true,
    'alreadyPromoted',false,
    'candidateId',v_candidate.id,
    'receipt',v_receipt,
    'canonicalConsequenceKind','institutional_person_record',
    'canonicalConsequenceRef',v_record_id::text,
    'realityEntry',v_render
  );
end;
$function$;

revoke all on function atlas.promote_implementation_reality_candidate_self_api_v1(uuid)
  from public, anon, authenticated, service_role;



create or replace function public.promote_implementation_reality_candidate_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.promote_implementation_reality_candidate_self_api_v1(
    p_candidate_id
  );
$function$;



revoke all on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
  from public, anon, service_role;

grant execute on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
  to authenticated;

comment on function public.promote_implementation_reality_candidate_self_api_v1(uuid) is
  'First executable Reality Candidate promotion path. An assigned practitioner may promote only an institutional_person_record.establish candidate within sponsor-governed Implementation scope. Readiness is delegated to the separately released read-only preview membrane. The owning Identity-domain command establishes/reuses the Institutional Person Record; candidate text itself never becomes canonical truth.';

commit;
