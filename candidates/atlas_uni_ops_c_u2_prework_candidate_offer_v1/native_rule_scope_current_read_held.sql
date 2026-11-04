-- U1B exact scope current-version root-only reader (HELD SOURCE).
-- Fetches ONE known property/class/Subject approval. Subject read requires
-- current independent identity and condition disclosure. Latest paused/
-- retired version is returned as such; never fall back to an older active.
CREATE FUNCTION atlas.read_governed_native_farm_rule_scope_current_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_scope_kind text,p_scope_ref text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $current$
DECLARE v_root record;v_ref text:=btrim(coalesce(p_scope_ref,''));
 v_key text;v_subject uuid;
 v_version atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF coalesce(p_scope_kind,'') NOT IN ('property','class','subject')
    OR length(v_ref) NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'Exact native policy scope required'
   USING ERRCODE='22023';
 END IF;
 CASE p_scope_kind
 WHEN 'property' THEN
  IF v_ref<>'property' THEN
   RAISE EXCEPTION 'Invalid property scope' USING ERRCODE='42501';
  END IF;
  v_key:='property';
 WHEN 'class' THEN
  IF NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
      JOIN atlas.rhythm_state s ON s.subject_id=g.id
       AND s.farm_id=g.farm_id AND s.organization_id=p_organization_id
       AND s.rhythm_rule_id=p_source_rule_id
      WHERE g.farm_id=p_farm_id AND g.object_type=v_ref) THEN
   RAISE EXCEPTION 'Native class unavailable' USING ERRCODE='42501';
  END IF;
  v_key:='class:'||v_ref;
 WHEN 'subject' THEN
  IF v_ref !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'Canonical Subject required' USING ERRCODE='42501';
  END IF;
  v_subject:=v_ref::uuid;
  IF NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
    JOIN reality.entities e ON e.id=g.id AND e.identity_state='canonical'
     AND e.entity_kind='growing_object'
     AND e.metadata->>'subjectDomain'='spatial'
    WHERE g.id=v_subject AND g.farm_id=p_farm_id)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',v_subject,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',v_subject,'condition'),false)
  THEN RAISE EXCEPTION 'Exact Subject scope unavailable'
    USING ERRCODE='42501'; END IF;
  v_key:='subject:'||v_subject::text;
 END CASE;
 SELECT * INTO v_version FROM atlas.governed_farm_rulebook_scope_versions_v1 v
 WHERE v.organization_id=p_organization_id AND v.ledger_id=p_ledger_id
  AND v.farm_id=p_farm_id AND v.source_rule_id=p_source_rule_id
  AND v.scope_key=v_key
 ORDER BY v.rule_version DESC LIMIT 1;
 IF v_version.id IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_native_rule_scope_current_v1',
   'state','not_established','scopeKey',v_key,
   'policyExecutable',false);
 END IF;
 RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_native_rule_scope_current_v1',
   'state','established','scopeKey',v_key,'ruleStatus',v_version.rule_status,
   'ruleVersionId',v_version.id,'ruleVersion',v_version.rule_version,
   'policy',v_version.policy,'sourceBasis',v_version.source_basis,
   'recordedAt',v_version.recorded_at,'policyExecutable',false,
   'workCreated',false);
END;
$current$;
REVOKE ALL ON FUNCTION atlas.read_governed_native_farm_rule_scope_current_self_api_v1(
 uuid,uuid,uuid,uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_governed_native_farm_rule_scope_current_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_scope_kind text,p_scope_ref text
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.read_governed_native_farm_rule_scope_current_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,p_scope_kind,p_scope_ref);
$transport$;
REVOKE ALL ON FUNCTION public.read_governed_native_farm_rule_scope_current_self_api_v1(
 uuid,uuid,uuid,uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_native_farm_rule_scope_current_self_api_v1(
 uuid,uuid,uuid,uuid,text,text) TO authenticated;
