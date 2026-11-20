BEGIN;
-- HELD source-only correction, not a migration or activation authorization.
-- Current-schema guard must match the reviewed historical source exactly.
-- Do not replay the historical integrated bundle over installed tables.
DO $source_guard$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p
      WHERE p.oid=to_regprocedure('atlas.guard_work_growing_object_context_v1()'))
      IS DISTINCT FROM '0278360920a2d26a301ceda4591b9994'
  THEN
    RAISE EXCEPTION 'current physical-context guard source drift';
  END IF;
END;
$source_guard$;

CREATE OR REPLACE FUNCTION atlas.guard_work_growing_object_context_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE
  v_ledger uuid;
BEGIN
  IF NEW.subject_domain<>'spatial'
     OR NEW.subject_kind<>'growing_object'
  THEN
    RETURN NEW;
  END IF;

  -- An established work link does not automatically authorize reading it.
  -- This source-owned path requires a current exact-Ledger governor and
  -- separately verified real Work/farm/physical source at every creation.
  IF auth.uid() IS NULL
     OR atlas.current_principal_id_v1() IS NULL
     OR coalesce(NEW.provenance->>'humanConfirmed','false')<>'true'
     OR coalesce(NEW.provenance->>'reviewedObjectKey','')=''
     OR coalesce(NEW.provenance->>'reviewedWorkStableKey','')=''
     OR coalesce(NEW.metadata->>'confersAccess','false')='true'
     OR coalesce(NEW.metadata->>'createsWork','false')='true'
  THEN
    RAISE EXCEPTION 'governed work-context establishment required'
      USING ERRCODE='42501';
  END IF;

  BEGIN
    v_ledger := (NEW.provenance->>'nativeLedgerId')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'invalid native Ledger proof'
      USING ERRCODE='42501';
  END;
  IF v_ledger IS NULL
     OR NOT atlas.principal_has_ledger_authority_v1(
       atlas.current_principal_id_v1(), v_ledger
     )
  THEN
    RAISE EXCEPTION 'exact Ledger governor required'
      USING ERRCODE='42501';
  END IF;

  -- Only the source-owned original decomposition transaction can establish
  -- its exact child's Subject before allocation. This is not a general
  -- governor override of legacy or other Work source checks.
  IF NEW.provenance->>'source'='original_work_decomposition' THEN
    IF TG_OP<>'INSERT'
       OR NEW.relation_kind<>'acts_on'
       OR NEW.provenance->>'decisionKind' IS DISTINCT FROM
          'signed_original_work_decomposition_subject_v1'
       OR NEW.provenance->>'reviewedByPrincipalId' IS DISTINCT FROM
          atlas.current_principal_id_v1()::text
       OR NEW.metadata->>'confersAccess' IS DISTINCT FROM 'false'
       OR NEW.metadata->>'createsWork' IS DISTINCT FROM 'false'
    THEN
      RAISE EXCEPTION 'exact original decomposition Subject evidence required'
        USING ERRCODE='42501';
    END IF;

    -- Use the existing signed owner membrane (not a claim in provenance).
    -- The source group/member must already exist within this transaction.
    IF NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.work_decomposition_members m ON m.child_work_item_id=w.id
      JOIN atlas.work_decomposition_groups d ON d.id=m.group_id
        AND d.parent_work_item_id=w.source_object_id
        AND d.authorized_ledger_id=v_ledger
      JOIN atlas.work_items parent ON parent.id=d.parent_work_item_id
        AND parent.organization_id=w.organization_id
        AND parent.organization_unit_id=w.organization_unit_id
        AND parent.work_state='open'
      JOIN atlas.growing_objects g ON g.id=m.subject_id
      JOIN atlas.farms f ON f.id=g.farm_id
        AND f.organization_id=w.organization_id
        AND f.organization_unit_id=w.organization_unit_id
      JOIN atlas.farm_crop_ledger_custody_v1 custody ON custody.farm_id=f.id
        AND custody.ledger_id=v_ledger AND custody.custody_state='active'
        AND custody.ended_at IS NULL
      JOIN atlas.ledger_organization_participations lop
        ON lop.organization_id=w.organization_id AND lop.ledger_id=v_ledger
        AND lop.status='active' AND lop.ended_at IS NULL
        AND lop.participation_kind IN ('governing','operating')
      JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
        AND nl.ledger_state='active' AND nl.retired_at IS NULL
      WHERE w.id=NEW.work_item_id AND w.organization_id=NEW.organization_id
        AND w.source_object_type='work_decomposition' AND w.work_state='open'
        AND g.object_type='bed'
        AND m.subject_domain=NEW.subject_domain
        AND m.subject_kind=NEW.subject_kind AND m.subject_id=NEW.subject_id
        AND d.id::text=NEW.provenance->>'decisionId'
        AND parent.id::text=NEW.provenance->>'parentWorkItemId'
        AND g.stable_key=NEW.provenance->>'reviewedObjectKey'
        AND w.stable_key=NEW.provenance->>'reviewedWorkStableKey'
        AND d.decided_by_person_id=atlas.company_work_native_ledger_owner_self_v1(
          w.organization_id,v_ledger)
        AND atlas.work_prerequisite_ledger_scope_v1(
          w.organization_id,v_ledger,parent.id)
        AND atlas.work_prerequisite_ledger_scope_v1(
          w.organization_id,v_ledger,w.id)
        AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_relevance r
          WHERE r.work_item_id=w.id AND r.organization_id=w.organization_id
            AND r.ledger_id=v_ledger AND r.attribution_state='active'
            AND r.evidence_kind='owner_attested'
            AND r.established_by_person_id=d.decided_by_person_id
            AND r.attestation_source_ref='original-canonical-work:'||parent.id::text
            AND r.attestation_reason=d.decision_reason
        )
    ) THEN
      RAISE EXCEPTION 'native original Work Subject and exact Ledger custody unproven'
        USING ERRCODE='42501';
    END IF;
    -- Context is neither allocation nor disclosure. The original child may
    -- still be unassigned. No change to the historical path below.
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atlas.work_items w
    JOIN atlas.tasks t
      ON t.id=w.source_object_id
     AND w.source_object_type IN ('legacy_task','legacy_task_slice')
    JOIN atlas.growing_objects g
      ON g.id=NEW.subject_id
    JOIN atlas.farms f
      ON f.id=g.farm_id AND f.id=t.farm_id
    JOIN atlas.farm_crop_ledger_custody_v1 custody
      ON custody.farm_id=f.id
     AND custody.ledger_id=v_ledger
     AND custody.custody_state='active'
     AND custody.ended_at IS NULL
    JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=w.organization_id
     AND lop.organization_id=f.organization_id
     AND lop.ledger_id=v_ledger
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
    JOIN ledger.ledgers nl
      ON nl.id=lop.ledger_id
     AND nl.ledger_state='active' AND nl.retired_at IS NULL
    WHERE w.id=NEW.work_item_id
      AND w.organization_id=NEW.organization_id
      AND f.organization_unit_id=w.organization_unit_id
      AND t.zone_id=g.zone_id
      AND g.object_type='bed'
      AND w.work_state IN ('open','in_progress')
      AND g.stable_key=NEW.provenance->>'reviewedObjectKey'
      AND w.stable_key=NEW.provenance->>'reviewedWorkStableKey'
      AND t.id::text=NEW.provenance->>'originalTaskId'
      AND EXISTS (
        SELECT 1 FROM atlas.work_allocations a
        WHERE a.work_item_id=w.id AND a.state='active'
      )
      AND (
        w.source_object_type<>'legacy_task_slice'
        OR EXISTS (
          SELECT 1
          FROM atlas.company_work_legacy_slice_contract_provenance_v1 src
          WHERE src.work_item_id=w.id AND src.source_task_id=t.id
        )
      )
  ) THEN
    RAISE EXCEPTION 'physical Work source and exact Ledger custody unproven'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$body$;
COMMIT;
