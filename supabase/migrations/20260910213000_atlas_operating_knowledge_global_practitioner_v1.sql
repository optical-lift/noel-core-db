-- Atlas global practitioner Operating Knowledge workbench v1
-- Lets authorized implementation practitioners work with existing Ledgers/units even when no implementation case is attached.

BEGIN;

create or replace function atlas.operating_knowledge_workbench_self_api_v1()
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

  select jsonb_build_object(
    'ok',true,
    'contractVersion','operating_knowledge_workbench_self_api_v1',
    'scopes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationName',o.name,
        'organizationUnitId',ou.id,
        'organizationUnitName',ou.name,
        'knowledgeCount',(select count(*) from atlas.company_operating_knowledge k where k.organization_id=o.id and k.organization_unit_id is not distinct from ou.id),
        'establishedCount',(select count(*) from atlas.company_operating_knowledge k where k.organization_id=o.id and k.organization_unit_id is not distinct from ou.id and k.status='established')
      ) order by o.name,ou.name nulls first)
      from atlas.organizations o
      left join atlas.organization_units ou on ou.organization_id=o.id
    ),'[]'::jsonb),
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',k.id,'organizationId',k.organization_id,'organizationName',o.name,
        'organizationUnitId',k.organization_unit_id,'organizationUnitName',ou.name,
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
      ) order by o.name,ou.name nulls first,k.family_key,k.stable_key,k.version desc)
      from atlas.company_operating_knowledge k
      join atlas.organizations o on o.id=k.organization_id
      left join atlas.organization_units ou on ou.id=k.organization_unit_id
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function atlas.propose_operating_knowledge_practitioner_self_api_v1(
  p_organization_id uuid,p_organization_unit_id uuid,p_family_key text,p_stable_key text,p_knowledge_kind text,
  p_title text,p_statement text,p_scope_match jsonb,p_effect jsonb,p_precedence integer default 0,p_confidence numeric default null,
  p_evidence_kind text default null,p_evidence_note text default null
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units u where u.id=p_organization_unit_id and u.organization_id=p_organization_id) then raise exception 'Organization unit does not belong to organization.' using errcode='23503'; end if;
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id) then raise exception 'Organization not found.' using errcode='23503'; end if;
  v_id:=atlas.company_operating_knowledge_propose_internal_v1(p_organization_id,p_organization_unit_id,p_family_key,p_stable_key,p_knowledge_kind,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,null,auth.uid(),'implementation practitioner','implementation_global_workbench');
  if nullif(btrim(p_evidence_kind),'') is not null then
    perform atlas.company_operating_knowledge_add_evidence_internal_v1(v_id,p_evidence_kind,'originates',jsonb_build_object('surface','implementation_global_operating_knowledge'),jsonb_build_object('statement',p_statement),p_evidence_note,now(),auth.uid());
  end if;
  return jsonb_build_object('ok',true,'knowledgeId',v_id);
end;
$$;

create or replace function atlas.revise_operating_knowledge_candidate_practitioner_self_v1(
  p_knowledge_id uuid,p_title text,p_statement text,p_scope_match jsonb,p_effect jsonb,p_precedence integer default 0,p_confidence numeric default null
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $$
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.company_operating_knowledge k where k.id=p_knowledge_id and k.established_at is null and k.status in ('candidate','disputed')) then raise exception 'Editable Operating Knowledge candidate not found.' using errcode='23503'; end if;
  if p_scope_match is null or jsonb_typeof(p_scope_match)<>'object' or p_effect is null or jsonb_typeof(p_effect)<>'object' then raise exception 'scope and effect must be JSON objects' using errcode='22023'; end if;
  update atlas.company_operating_knowledge set title=btrim(p_title),statement=btrim(p_statement),scope_match=p_scope_match,effect=p_effect,precedence=coalesce(p_precedence,0),confidence=p_confidence,updated_at=now() where id=p_knowledge_id;
  return jsonb_build_object('ok',true,'knowledgeId',p_knowledge_id);
end;
$$;

create or replace function atlas.add_operating_knowledge_evidence_practitioner_self_v1(
  p_knowledge_id uuid,p_evidence_kind text,p_interpretation_kind text,p_source_locator jsonb default '{}'::jsonb,p_evidence_snapshot jsonb default '{}'::jsonb,p_note text default null,p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.company_operating_knowledge where id=p_knowledge_id) then raise exception 'Operating Knowledge not found.' using errcode='23503'; end if;
  v_id:=atlas.company_operating_knowledge_add_evidence_internal_v1(p_knowledge_id,p_evidence_kind,p_interpretation_kind,p_source_locator,p_evidence_snapshot,p_note,p_observed_at,auth.uid());
  return jsonb_build_object('ok',true,'evidenceId',v_id);
end;
$$;

create or replace function atlas.adjudicate_operating_knowledge_practitioner_self_v1(
  p_knowledge_id uuid,p_decision_kind text,p_basis text,p_authority_label text,p_effective_from timestamptz default null
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $$
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.company_operating_knowledge where id=p_knowledge_id) then raise exception 'Operating Knowledge not found.' using errcode='23503'; end if;
  return atlas.company_operating_knowledge_adjudicate_internal_v1(p_knowledge_id,p_decision_kind,p_basis,p_authority_label,auth.uid(),'implementation practitioner',p_effective_from);
end;
$$;

create or replace function atlas.replace_operating_knowledge_practitioner_self_api_v1(
  p_organization_id uuid,p_organization_unit_id uuid,p_knowledge_id uuid,p_title text,p_statement text,p_scope_match jsonb,p_effect jsonb,
  p_precedence integer default 0,p_confidence numeric default null,p_evidence_kind text default null,p_evidence_note text default null
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $$
declare v_prior atlas.company_operating_knowledge%rowtype; v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  select * into v_prior from atlas.company_operating_knowledge where id=p_knowledge_id and organization_id=p_organization_id and organization_unit_id is not distinct from p_organization_unit_id;
  if not found then raise exception 'Replacement source knowledge not found in requested scope.' using errcode='23503'; end if;
  v_id:=atlas.company_operating_knowledge_propose_internal_v1(p_organization_id,p_organization_unit_id,v_prior.family_key,v_prior.stable_key,v_prior.knowledge_kind,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,v_prior.id,auth.uid(),'implementation practitioner','implementation_global_workbench_replacement');
  if nullif(btrim(p_evidence_kind),'') is not null then
    perform atlas.company_operating_knowledge_add_evidence_internal_v1(v_id,p_evidence_kind,'originates',jsonb_build_object('surface','implementation_global_operating_knowledge','replacesKnowledgeId',p_knowledge_id),jsonb_build_object('statement',p_statement),p_evidence_note,now(),auth.uid());
  end if;
  return jsonb_build_object('ok',true,'knowledgeId',v_id,'replacesKnowledgeId',p_knowledge_id);
end;
$$;

revoke all on function atlas.operating_knowledge_workbench_self_api_v1() from public,anon;
revoke all on function atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) from public,anon;
revoke all on function atlas.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric) from public,anon;
revoke all on function atlas.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) from public,anon;
revoke all on function atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz) from public,anon;
revoke all on function atlas.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) from public,anon;

grant execute on function atlas.operating_knowledge_workbench_self_api_v1() to authenticated;
grant execute on function atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;
grant execute on function atlas.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric) to authenticated;
grant execute on function atlas.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) to authenticated;
grant execute on function atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz) to authenticated;
grant execute on function atlas.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;

COMMIT;
