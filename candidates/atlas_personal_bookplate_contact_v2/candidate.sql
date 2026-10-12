-- SOURCE CANDIDATE ONLY: do not execute on live noel-core.
-- Named user correction 2026-10-12: one Person, multiple labeled contact methods,
-- optional date of birth and sex, *no* modification of Auth credential or residence.
BEGIN;
ALTER TABLE atlas.personal_atlas_bookplate_events
  ADD COLUMN contact_emails jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN contact_phones jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN contact_addresses jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN date_of_birth date,
  ADD COLUMN sex text;
ALTER TABLE atlas.personal_atlas_bookplate_events
 ADD CONSTRAINT personal_atlas_bookplate_contacts_shape_v2 CHECK (
   jsonb_typeof(contact_emails)='array' AND jsonb_array_length(contact_emails)<=8
   AND jsonb_typeof(contact_phones)='array' AND jsonb_array_length(contact_phones)<=8
   AND jsonb_typeof(contact_addresses)='array' AND jsonb_array_length(contact_addresses)<=8
   AND (sex IS NULL OR sex IN ('female','male','intersex','prefer_not_to_say'))
 );

CREATE OR REPLACE FUNCTION atlas.personal_atlas_bookplate_self_api_v2()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','atlas','auth'
AS $$
DECLARE
  v_base jsonb;
  v_user uuid := auth.uid();
  v_event atlas.personal_atlas_bookplate_events%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  v_base := atlas.personal_atlas_bookplate_self_api_v1();
  SELECT b.* INTO v_event FROM atlas.personal_atlas_bookplate_events b
  JOIN atlas.principals p ON p.id=b.principal_id AND p.user_id=v_user AND p.status='active'
  WHERE b.owner_user_id=v_user
  ORDER BY b.occurred_at DESC,b.id DESC LIMIT 1;
  RETURN v_base || jsonb_build_object(
   'contractVersion','personal_atlas_bookplate_self_api_v2',
   'contactEmails',CASE WHEN v_event.id IS NOT NULL AND jsonb_array_length(v_event.contact_emails)>0
      THEN v_event.contact_emails
      WHEN nullif(v_base->>'email','') IS NOT NULL THEN jsonb_build_array(jsonb_build_object('label','primary','value',v_base->>'email'))
      ELSE '[]'::jsonb END,
   'contactPhones',CASE WHEN v_event.id IS NOT NULL AND jsonb_array_length(v_event.contact_phones)>0
      THEN v_event.contact_phones
      WHEN nullif(v_base->>'phone','') IS NOT NULL THEN jsonb_build_array(jsonb_build_object('label','mobile','value',v_base->>'phone'))
      ELSE '[]'::jsonb END,
   'contactAddresses',CASE WHEN v_event.id IS NOT NULL AND jsonb_array_length(v_event.contact_addresses)>0
      THEN v_event.contact_addresses
      WHEN v_base->'address' IS NOT NULL AND v_base->'address'<>'null'::jsonb
       THEN jsonb_build_array(jsonb_build_object('label','billing_candidate','value',v_base->'address'))
      ELSE '[]'::jsonb END,
   'dateOfBirth',v_event.date_of_birth,
   'sex',v_event.sex,
   'contactTruthBoundary',jsonb_build_object('additionalEmailDoesNotAuthenticate',true,'listedMailboxIsNotConnected',true,'addressIsNotResidence',true,'birthAndSexAreOptionalHumanSuppliedEvidence',true)
  );
END; $;

CREATE OR REPLACE FUNCTION atlas.set_personal_atlas_bookplate_self_api_v2(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','atlas','auth'
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_email_arr jsonb := coalesce(p_input->'contactEmails','[]'::jsonb);
  v_phone_arr jsonb := coalesce(p_input->'contactPhones','[]'::jsonb);
  v_address_arr jsonb := coalesce(p_input->'contactAddresses','[]'::jsonb);
  v_birth date;
  v_sex text := nullif(trim(p_input->>'sex'),'');
  v_email text := nullif(lower(trim(p_input->>'email')),'');
  v_phone text := nullif(trim(p_input->>'phone'),'');
  v_result jsonb;
  v_event atlas.personal_atlas_bookplate_events%ROWTYPE;
  v_item jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input)<>'object' THEN
    RAISE EXCEPTION 'Bookplate input must be an object' USING ERRCODE='22023';
  END IF;
  IF jsonb_typeof(v_email_arr)<>'array' OR jsonb_array_length(v_email_arr)>8
   OR jsonb_typeof(v_phone_arr)<>'array' OR jsonb_array_length(v_phone_arr)>8
   OR jsonb_typeof(v_address_arr)<>'array' OR jsonb_array_length(v_address_arr)>8 THEN
    RAISE EXCEPTION 'Invalid number or type of contact values' USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_email_arr) LOOP
    IF jsonb_typeof(v_item)<>'object'
       OR length(coalesce(v_item->>'label','')) NOT BETWEEN 1 AND 50
       OR coalesce(v_item->>'value','') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    THEN RAISE EXCEPTION 'Invalid labeled email' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_phone_arr) LOOP
    IF jsonb_typeof(v_item)<>'object' OR length(coalesce(v_item->>'label','')) NOT BETWEEN 1 AND 50
       OR length(coalesce(v_item->>'value','')) NOT BETWEEN 3 AND 40
    THEN RAISE EXCEPTION 'Invalid labeled phone' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_address_arr) LOOP
    IF jsonb_typeof(v_item)<>'object' OR length(coalesce(v_item->>'label','')) NOT BETWEEN 1 AND 50
       OR coalesce(jsonb_typeof(v_item->'value'),'null')<>'object' OR length(v_item::text)>2000
    THEN RAISE EXCEPTION 'Invalid labeled address' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF v_email IS NOT NULL AND jsonb_array_length(v_email_arr)>0 AND lower(trim(v_email_arr->0->>'value')) IS DISTINCT FROM v_email
   OR v_phone IS NOT NULL AND jsonb_array_length(v_phone_arr)>0 AND trim(v_phone_arr->0->>'value') IS DISTINCT FROM v_phone
   OR p_input->'contactAddress' IS NOT NULL AND p_input->'contactAddress'<>'null'::jsonb
      AND jsonb_array_length(v_address_arr)>0 AND (v_address_arr->0->'value') IS DISTINCT FROM
      p_input->'contactAddress'
  THEN RAISE EXCEPTION 'Primary contact and first labeled contact differ' USING ERRCODE='22023'; END IF;
  IF nullif(trim(p_input->>'dateOfBirth'),'') IS NOT NULL THEN
    v_birth := (p_input->>'dateOfBirth')::date;
    IF v_birth > current_date OR v_birth < DATE '1880-01-01' THEN RAISE EXCEPTION 'Birth date invalid' USING ERRCODE='22023'; END IF;
  END IF;
  IF v_sex IS NOT NULL AND v_sex NOT IN ('female','male','intersex','prefer_not_to_say') THEN
    RAISE EXCEPTION 'Sex choice invalid' USING ERRCODE='22023';
  END IF;
  -- v1 remains the sole canonical Principal/Home/Person promotion writer.
  v_result := atlas.set_personal_atlas_bookplate_self_api_v1(p_input);
  SELECT * INTO v_event FROM atlas.personal_atlas_bookplate_events
    WHERE owner_user_id=v_uid AND source_action_id=nullif(trim(p_input->>'sourceActionId'),'')
    LIMIT 1;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'Bookplate event missing' USING ERRCODE='P0002'; END IF;
  IF v_result->>'idempotentReplay'='true' AND
     (v_event.contact_emails IS DISTINCT FROM v_email_arr OR
      v_event.contact_phones IS DISTINCT FROM v_phone_arr OR
      v_event.contact_addresses IS DISTINCT FROM v_address_arr OR
      v_event.date_of_birth IS DISTINCT FROM v_birth OR v_event.sex IS DISTINCT FROM v_sex)
  THEN RAISE EXCEPTION 'Bookplate action replay conflicts with details' USING ERRCODE='23505'; END IF;
  UPDATE atlas.personal_atlas_bookplate_events
    SET contact_emails=v_email_arr,contact_phones=v_phone_arr,contact_addresses=v_address_arr,
        date_of_birth=v_birth,sex=v_sex
    WHERE id=v_event.id AND owner_user_id=v_uid;
  RETURN (v_result - 'bookplate') || jsonb_build_object(
    'contractVersion','set_personal_atlas_bookplate_self_api_v2',
    'bookplate',atlas.personal_atlas_bookplate_self_api_v2()
  );
END; $;

-- Mirror existing governed public RPC gateway; atlas internals are not Data API grants.
-- The Auth JWT flows through the public wrapper; atlas internal functions retain uid checks.
CREATE OR REPLACE FUNCTION public.personal_atlas_bookplate_self_api_v2()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.personal_atlas_bookplate_self_api_v2(); $$;
CREATE OR REPLACE FUNCTION public.set_personal_atlas_bookplate_self_api_v2(p_input jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.set_personal_atlas_bookplate_self_api_v2(p_input); $$;

REVOKE ALL ON FUNCTION atlas.personal_atlas_bookplate_self_api_v2() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.set_personal_atlas_bookplate_self_api_v2(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.personal_atlas_bookplate_self_api_v2() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.set_personal_atlas_bookplate_self_api_v2(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.personal_atlas_bookplate_self_api_v2() TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_personal_atlas_bookplate_self_api_v2(jsonb) TO authenticated,service_role;

INSERT INTO atlas.authenticated_rpc_registry(
 signature,classification,confidence,review_status,
 authenticated_execute_expected,security_definer_expected,service_execute_expected,
 caller_count,policy_reference_count,evidence,anonymous_execute_expected
) VALUES
 ('atlas.personal_atlas_bookplate_self_api_v2()','app_endpoint','verified','active',
  true,true,true,1,0,
  '{"purpose":"Read one canonical Bookplate and repeat labeled contacts, birth and sex as human-owned evidence","truthBoundary":"No newly listed email becomes Auth identity or mailbox access; billing address is not residence."}'::jsonb,false),
 ('atlas.set_personal_atlas_bookplate_self_api_v2(p_input jsonb)','app_endpoint','verified','active',
  true,true,true,1,0,
  '{"purpose":"Persist Bookplate corrections and optional repeated contacts after validating ownership","truthBoundary":"Delegates Person/Principal/Home establishment to v1; no Auth, payment or residence rewrite."}'::jsonb,false)
ON CONFLICT(signature) DO NOTHING;

COMMIT;
