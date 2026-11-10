-- HELD validation-only postconditions for a separately generated atlas_ migration.
-- Does not write data, grant permissions, or create a production release.
DO $uniops_c2_postconditions$
DECLARE
  v_source text;
  v_prosecdef boolean;
  v_volatility "char";
  v_search_path text[];
BEGIN
  IF to_regprocedure('atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)') IS NULL THEN
    RAISE EXCEPTION 'UNI-OPS C2 owner Case reader absent after candidate'
      USING ERRCODE='23514';
  END IF;

  SELECT pg_get_functiondef(p.oid),p.prosecdef,p.provolatile,p.proconfig
  INTO v_source,v_prosecdef,v_volatility,v_search_path
  FROM pg_proc p
  WHERE p.oid='atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure;

  IF NOT coalesce(v_prosecdef,false) OR v_volatility <> 's'
     OR NOT ('search_path=' = ANY(v_search_path)) THEN
    RAISE EXCEPTION 'UNI-OPS C2 signed owner guard, volatility or search path drift'
      USING ERRCODE='23514';
  END IF;

  -- Exact tested new canonical_work relevance predicate, not the older
  -- legacyLinkedRequirements clause that already existed before this release.
  IF position($uniops_c2_guard$          and exists (
            select 1
            from atlas.company_work_native_ledger_relevance rel
            where rel.organization_id=i.organization_id
              and rel.work_item_id=i.id
              and rel.ledger_id=p_ledger_id
              and rel.attribution_state='active'
              and (
                rel.evidence_kind='owner_attested'
                or (
                  rel.evidence_kind='source_verified'
                  and exists (
                    select 1
                    from atlas.company_work_native_ledger_exact_source_v1(
                      rel.work_item_id,rel.ledger_id
                    ) proof
                    where proof.source_schema=rel.source_schema
                      and proof.source_table=rel.source_table
                      and proof.source_id=rel.source_id
                  )
                )
              )
          )$uniops_c2_guard$ IN v_source)=0 THEN
    RAISE EXCEPTION 'UNI-OPS C2 exact selected Ledger Work predicate absent'
      USING ERRCODE='23514';
  END IF;

  IF position('company_work_native_ledger_owner_self_v1' IN v_source)=0
     OR position('current_person_id_v1' IN v_source)=0
     OR position('recurrenceRuleDoesNotMaterializeWorkHere' IN v_source)=0 THEN
    RAISE EXCEPTION 'UNI-OPS C2 existing owner or no-auto-Work contract changed'
      USING ERRCODE='23514';
  END IF;
END;
$uniops_c2_postconditions$;
