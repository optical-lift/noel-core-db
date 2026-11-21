-- HELD CUTOVER CANDIDATE. Owner's native-only history decision #2392.
-- Legacy self-adopted original Work and any previously accepted Results remain
-- intact as historical source evidence. They may be linked to a current Person
-- only by a separate current-Ledger governor decision; this old Result writer
-- is NOT an independent historical reviewer or a path to a new Done.
-- Unfinished historical Work is not reactivated: a present Need must qualify
-- a separate new native original Work with exact source lineage.
-- No legacy membership, employee-seat, or self-adoption record grants modern
-- Work/Done permission, even if its old membership record remains active.
-- Future signed pending evidence and owner-reviewed historical close are
-- different governed APIs, not impersonations of this writer.
CREATE OR REPLACE FUNCTION atlas.report_self_responsible_company_work_self_api_v1(
 p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
 p_payload jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
BEGIN
 IF v_uid IS NULL OR v_person IS NULL THEN
   RAISE EXCEPTION 'Signed current native Person required'
     USING ERRCODE='42501';
 END IF;
 IF p_work_item_id IS NULL
   OR p_result_kind NOT IN ('completed','partial','blocked','unable')
   OR nullif(btrim(coalesce(p_idempotency_key,'')),'') IS NULL
   OR length(p_idempotency_key)>160
   OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
 THEN RAISE EXCEPTION 'Exact original Work and action required'
   USING ERRCODE='22023'; END IF;
 -- Deliberately no historic membership query, Result/Acceptance mutation,
 -- modern completion, receipt replay, or assignment transfer. Replaying
 -- old accepted source Results via this entrypoint is also not a new Done.
 RAISE EXCEPTION 'Historical self-adopted Work is reference only; current governor reconciliation required'
   USING ERRCODE='42501';
END;
$function$;
