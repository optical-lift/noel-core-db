-- HELD SIGNED-HTTP ENTRYPOINT. NOT A PRODUCTION RELEASE OR ROUTE GRANT.
-- Public PostgREST function is the only executable browser care-report entry.
-- Its SECURITY DEFINER owner bridges the deliberately private domain writer.
-- Source permission is rechecked inside the domain writer for EVERY call,
-- including repeated action IDs. No user-supplied ledger, Person, or Subject
-- may override the original Work's governed allocation and context.
CREATE OR REPLACE FUNCTION public.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $signed_care$
BEGIN
  IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL THEN
    RAISE EXCEPTION 'A current signed Person is required'
      USING ERRCODE='42501';
  END IF;
  RETURN atlas.record_continuing_care_actual_self_api_v1(
    p_work_item_id,p_action_id,p_actual_kind,p_condition_after,
    p_minutes,p_note,p_recheck_on);
END;
$signed_care$;
-- PostgreSQL defaults grant EXECUTE to PUBLIC. Revoke both inherited and
-- direct anonymous privileges, then admit only genuine signed clients.
REVOKE ALL ON FUNCTION public.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) TO authenticated;
-- Invalidate PostgREST's function-signature cache inside this disposable
-- clone when the new public RPC becomes available.
SELECT pg_catalog.pg_notify('pgrst','reload schema');
-- The private writer must remain unreached even by signed or service clients.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC,anon,authenticated,service_role;
