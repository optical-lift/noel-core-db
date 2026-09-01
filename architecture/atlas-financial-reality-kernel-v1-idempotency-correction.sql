-- Atlas Financial Reality Kernel v1 — append-only idempotency correction.
-- Reviewed architecture-source SQL only; assemble after atlas-financial-reality-kernel-v1.sql.
--
-- Append-only evidence tables cannot use ON CONFLICT DO UPDATE, even for a no-op,
-- because the update itself violates the history-mutation fence. Duplicate calls
-- must return the already-recorded row without issuing an UPDATE.

create or replace function atlas.link_financial_observation_to_event_core_v1(
  p_organization_id uuid,
  p_economic_event_id uuid,
  p_observation_id uuid,
  p_evidence_role text,
  p_admission_kind text,
  p_admission_ref text,
  p_confidence numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_event_evidence_links%rowtype;
begin
  if p_evidence_role not in ('establishes','corroborates','documents','classifies','settles','contradicts')
     or nullif(btrim(coalesce(p_admission_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_ref,'')),'') is null then
    raise exception 'Financial evidence link requires a supported role and explicit admission basis.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.financial_event_evidence_links l
  where l.economic_event_id=p_economic_event_id
    and l.observation_id=p_observation_id
    and l.evidence_role=p_evidence_role
    and l.admission_kind=btrim(p_admission_kind)
    and l.admission_ref=btrim(p_admission_ref);

  if v_row.id is not null then
    return jsonb_build_object(
      'contractVersion','link_financial_observation_to_event_core_v1',
      'state','unchanged','evidenceLinkId',v_row.id,'deduplicated',true
    );
  end if;

  begin
    insert into atlas.financial_event_evidence_links(
      organization_id,economic_event_id,observation_id,evidence_role,
      admission_kind,admission_ref,confidence,metadata
    ) values (
      p_organization_id,p_economic_event_id,p_observation_id,p_evidence_role,
      btrim(p_admission_kind),btrim(p_admission_ref),p_confidence,coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_row;
  exception when unique_violation then
    select * into v_row
    from atlas.financial_event_evidence_links l
    where l.economic_event_id=p_economic_event_id
      and l.observation_id=p_observation_id
      and l.evidence_role=p_evidence_role
      and l.admission_kind=btrim(p_admission_kind)
      and l.admission_ref=btrim(p_admission_ref);
  end;

  return jsonb_build_object(
    'contractVersion','link_financial_observation_to_event_core_v1',
    'state','recorded','evidenceLinkId',v_row.id,
    'deduplicated',false
  );
end;
$function$;

create or replace function atlas.relate_financial_economic_events_core_v1(
  p_organization_id uuid,
  p_from_event_id uuid,
  p_to_event_id uuid,
  p_relation_kind text,
  p_admission_kind text,
  p_admission_ref text,
  p_confidence numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_event_relations%rowtype;
begin
  if nullif(btrim(coalesce(p_relation_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_kind,'')),'') is null
     or nullif(btrim(coalesce(p_admission_ref,'')),'') is null then
    raise exception 'Financial event relation requires relation kind and explicit admission basis.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.financial_event_relations r
  where r.from_event_id=p_from_event_id
    and r.to_event_id=p_to_event_id
    and r.relation_kind=btrim(p_relation_kind)
    and r.admission_kind=btrim(p_admission_kind)
    and r.admission_ref=btrim(p_admission_ref);

  if v_row.id is not null then
    return jsonb_build_object(
      'contractVersion','relate_financial_economic_events_core_v1',
      'state','unchanged','relationId',v_row.id,'deduplicated',true
    );
  end if;

  begin
    insert into atlas.financial_event_relations(
      organization_id,from_event_id,to_event_id,relation_kind,
      admission_kind,admission_ref,confidence,metadata
    ) values (
      p_organization_id,p_from_event_id,p_to_event_id,btrim(p_relation_kind),
      btrim(p_admission_kind),btrim(p_admission_ref),p_confidence,coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_row;
  exception when unique_violation then
    select * into v_row
    from atlas.financial_event_relations r
    where r.from_event_id=p_from_event_id
      and r.to_event_id=p_to_event_id
      and r.relation_kind=btrim(p_relation_kind)
      and r.admission_kind=btrim(p_admission_kind)
      and r.admission_ref=btrim(p_admission_ref);
  end;

  return jsonb_build_object(
    'contractVersion','relate_financial_economic_events_core_v1',
    'state','recorded','relationId',v_row.id,'deduplicated',false
  );
end;
$function$;

create or replace function atlas.assert_financial_classification_core_v1(
  p_organization_id uuid,
  p_economic_event_id uuid,
  p_taxonomy_key text,
  p_classification_key text,
  p_classification_label text,
  p_source_kind text,
  p_source_ref text,
  p_authority_rank integer,
  p_confidence numeric,
  p_supersedes_assertion_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.financial_classification_assertions%rowtype;
begin
  if nullif(btrim(coalesce(p_taxonomy_key,'')),'') is null
     or nullif(btrim(coalesce(p_classification_key,'')),'') is null
     or p_source_kind not in ('accounting_system','human','organization_rule','provider_hint','model_suggestion')
     or nullif(btrim(coalesce(p_source_ref,'')),'') is null
     or p_authority_rank is null or p_authority_rank<0 then
    raise exception 'Financial classification requires taxonomy, classification, source, and non-negative authority rank.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.financial_classification_assertions a
  where a.economic_event_id=p_economic_event_id
    and a.taxonomy_key=btrim(p_taxonomy_key)
    and a.classification_key=btrim(p_classification_key)
    and a.source_kind=p_source_kind
    and a.source_ref=btrim(p_source_ref);

  if v_row.id is not null then
    if v_row.organization_id is distinct from p_organization_id
       or v_row.authority_rank is distinct from p_authority_rank
       or v_row.confidence is distinct from p_confidence
       or v_row.supersedes_assertion_id is distinct from p_supersedes_assertion_id then
      raise exception 'Existing financial classification assertion identity cannot be silently rewritten.' using errcode='55000';
    end if;
    return jsonb_build_object(
      'contractVersion','assert_financial_classification_core_v1',
      'state','unchanged','classificationAssertionId',v_row.id,'deduplicated',true
    );
  end if;

  begin
    insert into atlas.financial_classification_assertions(
      organization_id,economic_event_id,taxonomy_key,classification_key,classification_label,
      source_kind,source_ref,authority_rank,confidence,supersedes_assertion_id,metadata
    ) values (
      p_organization_id,p_economic_event_id,btrim(p_taxonomy_key),btrim(p_classification_key),
      nullif(btrim(coalesce(p_classification_label,'')),''),p_source_kind,btrim(p_source_ref),
      p_authority_rank,p_confidence,p_supersedes_assertion_id,coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_row;
  exception when unique_violation then
    select * into v_row
    from atlas.financial_classification_assertions a
    where a.economic_event_id=p_economic_event_id
      and a.taxonomy_key=btrim(p_taxonomy_key)
      and a.classification_key=btrim(p_classification_key)
      and a.source_kind=p_source_kind
      and a.source_ref=btrim(p_source_ref);
  end;

  return jsonb_build_object(
    'contractVersion','assert_financial_classification_core_v1',
    'state','recorded','classificationAssertionId',v_row.id,'deduplicated',false
  );
end;
$function$;
