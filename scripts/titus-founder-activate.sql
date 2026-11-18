-- Protected DATA transaction, not a migration. Inputs: owner-approved
-- fingerprint of confirmed Auth + canonical Person + existing original Course;
-- issue number is validated by the protected workflow before execution.
\set QUIET 1
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='20s';
SELECT set_config('app.titus_owner_binding', :'owner_binding', true) AS binding,
       set_config('app.titus_owner_approval', :'owner_receipt', true) AS receipt \gset
DO $activate$
DECLARE v_person uuid; v_matches bigint; v_receipt text:=current_setting('app.titus_owner_approval');
 v_binding text:=current_setting('app.titus_owner_binding'); v_existing reality.responsibility_relations%ROWTYPE;
 v_ops text[]:=ARRAY['author_course_as_owner','issue_pilot_code','revoke_pilot_code','end_pilot_access'];
BEGIN
 IF v_binding !~ '^[a-f0-9]{64}$' OR v_receipt !~ '^github:optical-lift/noel-core-db/issues/[1-9][0-9]*#titus-founder-v1$'
 OR to_regprocedure('public.shared_teaching_course_adopt_self_api_v1(uuid)') IS NULL THEN
 RAISE EXCEPTION 'invalid founder activation package'; END IF;
 LOCK TABLE reality.responsibility_relations IN SHARE ROW EXCLUSIVE MODE;
 SELECT count(*),min(b.person_entity_id::text)::uuid INTO v_matches,v_person
 FROM auth.users u
 JOIN reality.auth_person_bindings b ON b.auth_user_id=u.id AND b.binding_state='active' AND b.retired_at IS NULL
 JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
 JOIN titus.customer_course_drafts_v1 d ON d.created_by_auth_user_id=u.id AND d.state='draft'
 WHERE u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
 AND encode(sha256(convert_to('titus-owner-v1:'||u.id::text||':'||b.person_entity_id::text||':'||d.course_id::text,'UTF8')),'hex')=v_binding
 AND (SELECT count(*) FROM reality.auth_person_bindings z WHERE z.auth_user_id=u.id AND z.binding_state='active' AND z.retired_at IS NULL)=1;
 IF v_matches<>1 THEN RAISE EXCEPTION 'exact confirmed founder binding not established'; END IF;
 SELECT count(*) INTO v_matches FROM reality.responsibility_relations r
 WHERE r.responsibility_key='titus_private_pilot_issuance' AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus';
 IF v_matches>0 THEN
  IF v_matches<>1 THEN RAISE EXCEPTION 'existing Titus authorities require adjudication'; END IF;
  SELECT * INTO v_existing FROM reality.responsibility_relations r
  WHERE r.responsibility_key='titus_private_pilot_issuance' AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus';
  IF v_existing.carrier_person_entity_id IS DISTINCT FROM v_person
   OR v_existing.establishment_basis->>'approval_receipt' IS DISTINCT FROM v_receipt
   OR v_existing.relation_state<>'active' OR v_existing.ended_at IS NOT NULL
   OR v_existing.permitted_operations IS DISTINCT FROM v_ops THEN
   RAISE EXCEPTION 'existing authority differs; no overwrite';
  END IF;
 ELSE
  INSERT INTO reality.responsibility_relations(carrier_person_entity_id,responsibility_key,title,
    relation_state,jurisdiction_kind,jurisdiction_domain,permitted_operations,establishment_kind,establishment_basis)
  VALUES(v_person,'titus_private_pilot_issuance','Founding Titus owner','active','domain','titus',v_ops,
    'owner_authorized_foundation',jsonb_build_object('approval_receipt',v_receipt,'contract','titus-founder-v1'));
 END IF;
 IF NOT titus.authoring_grant_current_active_v1(v_person) THEN RAISE EXCEPTION 'founding authoring verification failed'; END IF;
END $activate$;
COMMIT;
\set QUIET 0
\echo PASS founder responsibility and authoring verified; no invitation, Course adoption or migration
