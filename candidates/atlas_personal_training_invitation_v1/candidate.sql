BEGIN;

-- DRAFT REVIEWED-CANDIDATE ONLY. Do not execute against live project.
-- First-domain 15K training pilot, not a universal Program engine.
CREATE TABLE atlas.personal_training_programs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 author_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 160),
 goal_distance_m integer NOT NULL DEFAULT 15000 CHECK (goal_distance_m=15000),
 method_version integer NOT NULL DEFAULT 1 CHECK (method_version=1),
 event_date date,
 reviewed_method jsonb NOT NULL CHECK (jsonb_typeof(reviewed_method) IN ('object','array')),
 provenance jsonb NOT NULL CHECK (jsonb_typeof(provenance)='object'),
 reviewed_at timestamptz NOT NULL DEFAULT now(),
 request_key text NOT NULL CHECK (length(request_key) BETWEEN 8 AND 160),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(owner_principal_id,request_key)
);
CREATE TABLE atlas.personal_training_invitations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id),
 sender_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 recipient_email text NOT NULL CHECK (recipient_email=lower(btrim(recipient_email))),
 state text NOT NULL DEFAULT 'issued' CHECK (state IN ('issued','accepted','declined','revoked')),
 issued_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '30 days'),
 accepted_at timestamptz,
 accepted_by_principal_id uuid REFERENCES atlas.principals(id),
 declined_at timestamptz,
 revoked_at timestamptz,
 request_key text NOT NULL CHECK (length(request_key) BETWEEN 8 AND 160),
 UNIQUE(program_id,recipient_email),
 UNIQUE(sender_principal_id,request_key),
 CHECK ((state='accepted')=(accepted_at IS NOT NULL AND accepted_by_principal_id IS NOT NULL)),
 CHECK ((state='declined')=(declined_at IS NOT NULL)),
 CHECK ((state='revoked')=(revoked_at IS NOT NULL))
);
CREATE TABLE atlas.personal_training_participations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id),
 principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 participation_kind text NOT NULL CHECK (participation_kind IN ('initiator','invited')),
 invitation_id uuid UNIQUE REFERENCES atlas.personal_training_invitations(id),
 state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','withdrawn')),
 share_progress boolean NOT NULL DEFAULT false,
 joined_at timestamptz NOT NULL DEFAULT now(),
 withdrawn_at timestamptz,
 UNIQUE(program_id,principal_id),
 CHECK ((state='withdrawn')=(withdrawn_at IS NOT NULL))
);
CREATE INDEX personal_training_invites_pending_idx
 ON atlas.personal_training_invitations(recipient_email,expires_at) WHERE state='issued';
ALTER TABLE atlas.personal_training_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.personal_training_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.personal_training_participations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_training_programs,atlas.personal_training_invitations,atlas.personal_training_participations FROM PUBLIC,anon,authenticated;

-- No direct table API. Caller-bound, audited, narrowly granted operations.
CREATE FUNCTION atlas.personal_training_create_self_api_v1(
 p_title text, p_method jsonb, p_provenance jsonb, p_event_date date,
 p_human_reviewed boolean, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_principal uuid; v_access jsonb; v_row atlas.personal_training_programs%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 v_principal:=atlas.current_principal_id_v1();
 v_access:=atlas.personal_atlas_access_status_self_api_v1();
 IF v_principal IS NULL OR (v_access->>'eligible')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501'; END IF;
 IF p_human_reviewed IS DISTINCT FROM true OR p_method IS NULL
    OR jsonb_typeof(p_method) NOT IN ('array','object')
    OR p_method IN ('{}'::jsonb,'[]'::jsonb)
    OR p_provenance IS NULL OR jsonb_typeof(p_provenance)<>'object'
 THEN RAISE EXCEPTION 'Reviewed source-backed method required' USING ERRCODE='22023'; END IF;
 IF length(coalesce(btrim(p_title),'')) NOT BETWEEN 3 AND 160
    OR length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
    OR octet_length(p_method::text)>100000 OR octet_length(p_provenance::text)>20000
 THEN RAISE EXCEPTION 'Invalid parameters' USING ERRCODE='22023'; END IF;
 INSERT INTO atlas.personal_training_programs
  (owner_principal_id,author_auth_user_id,title,event_date,reviewed_method,provenance,request_key)
 VALUES(v_principal,auth.uid(),btrim(p_title),p_event_date,p_method,p_provenance,p_request_key)
 ON CONFLICT(owner_principal_id,request_key) DO NOTHING;
 SELECT * INTO v_row FROM atlas.personal_training_programs
  WHERE owner_principal_id=v_principal AND request_key=p_request_key;
 IF v_row.title<>btrim(p_title) OR v_row.event_date IS DISTINCT FROM p_event_date
    OR v_row.reviewed_method<>p_method OR v_row.provenance<>p_provenance
 THEN RAISE EXCEPTION 'Idempotency conflict' USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.personal_training_participations(program_id,principal_id,participation_kind)
 VALUES(v_row.id,v_principal,'initiator') ON CONFLICT(program_id,principal_id) DO NOTHING;
 RETURN jsonb_build_object('ok',true,'programId',v_row.id,'methodVersion',v_row.method_version);
END;$function$;

CREATE FUNCTION atlas.personal_training_invite_self_api_v1(
 p_program_id uuid, p_email text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_principal uuid; v_email text:=lower(btrim(coalesce(p_email,'')));
 v_owner uuid; v_invite atlas.personal_training_invitations%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 v_principal:=atlas.current_principal_id_v1();
 IF v_principal IS NULL OR
   (atlas.personal_atlas_access_status_self_api_v1()->>'eligible')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501'; END IF;
 SELECT owner_principal_id INTO v_owner FROM atlas.personal_training_programs WHERE id=p_program_id;
 IF v_owner IS DISTINCT FROM v_principal THEN RAISE EXCEPTION 'Program unavailable' USING ERRCODE='42501'; END IF;
 IF length(v_email) NOT BETWEEN 5 AND 320 OR
    v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    OR length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Invalid recipient or request key' USING ERRCODE='22023'; END IF;
 IF v_email=(SELECT lower(email) FROM auth.users WHERE id=auth.uid())
 THEN RAISE EXCEPTION 'Self-invitation not permitted' USING ERRCODE='22023'; END IF;
 INSERT INTO atlas.personal_training_invitations(program_id,sender_principal_id,recipient_email,request_key)
 VALUES(p_program_id,v_principal,v_email,p_request_key)
 ON CONFLICT(program_id,recipient_email) DO NOTHING;
 SELECT * INTO v_invite FROM atlas.personal_training_invitations
  WHERE program_id=p_program_id AND recipient_email=v_email;
 IF v_invite.sender_principal_id<>v_principal OR v_invite.state<>'issued'
    OR v_invite.expires_at<=now()
 THEN RAISE EXCEPTION 'Invitation cannot be reissued in pilot' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'invitationId',v_invite.id,'state','issued','expiresAt',v_invite.expires_at);
END;$function$;

CREATE FUNCTION atlas.personal_training_pending_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_email text; v_principal uuid; v_items jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 v_principal:=atlas.current_principal_id_v1();
 IF v_principal IS NULL OR
    (atlas.personal_atlas_access_status_self_api_v1()->>'eligible')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501'; END IF;
 SELECT lower(email) INTO v_email FROM auth.users
 WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
 IF v_email IS NULL THEN RAISE EXCEPTION 'Verified email required' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'invitationId',i.id,'programId',p.id,'title',p.title,
   'distanceMeters',p.goal_distance_m,'eventDate',p.event_date,
   'senderName',s.name,'expiresAt',i.expires_at,'methodVersion',p.method_version
 ) ORDER BY i.issued_at DESC),'[]'::jsonb) INTO v_items
 FROM atlas.personal_training_invitations i
 JOIN atlas.personal_training_programs p ON p.id=i.program_id
 JOIN atlas.principals s ON s.id=i.sender_principal_id
 WHERE i.recipient_email=v_email AND i.state='issued' AND i.expires_at>now();
 RETURN jsonb_build_object('ok',true,'items',v_items);
END;$function$;

CREATE FUNCTION atlas.personal_training_decide_self_api_v1(
 p_invitation_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_principal uuid; v_email text; v_i atlas.personal_training_invitations%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 v_principal:=atlas.current_principal_id_v1();
 IF v_principal IS NULL OR
    (atlas.personal_atlas_access_status_self_api_v1()->>'eligible')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('accept','decline')
 THEN RAISE EXCEPTION 'Invalid decision' USING ERRCODE='22023'; END IF;
 SELECT lower(email) INTO v_email FROM auth.users
 WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
 IF v_email IS NULL THEN RAISE EXCEPTION 'Verified email required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_i FROM atlas.personal_training_invitations WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL OR v_i.recipient_email<>v_email
 THEN RAISE EXCEPTION 'Invitation not available' USING ERRCODE='42501'; END IF;
 IF v_i.state='accepted' AND p_decision='accept' AND v_i.accepted_by_principal_id=v_principal
 THEN RETURN jsonb_build_object('ok',true,'state','accepted','programId',v_i.program_id); END IF;
 IF v_i.state='declined' AND p_decision='decline'
 THEN RETURN jsonb_build_object('ok',true,'state','declined'); END IF;
 IF v_i.state<>'issued' OR v_i.expires_at<=now()
 THEN RAISE EXCEPTION 'Invitation no longer available' USING ERRCODE='23514'; END IF;
 IF p_decision='decline' THEN
   UPDATE atlas.personal_training_invitations SET state='declined',declined_at=now() WHERE id=v_i.id;
   RETURN jsonb_build_object('ok',true,'state','declined');
 END IF;
 IF v_i.sender_principal_id=v_principal
 THEN RAISE EXCEPTION 'Self invitation not permitted' USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.personal_training_participations(program_id,principal_id,participation_kind,invitation_id)
 VALUES(v_i.program_id,v_principal,'invited',v_i.id)
 ON CONFLICT(program_id,principal_id) DO NOTHING;
 IF NOT EXISTS(SELECT 1 FROM atlas.personal_training_participations x
   WHERE x.program_id=v_i.program_id AND x.principal_id=v_principal
     AND x.invitation_id=v_i.id AND x.state='active')
 THEN RAISE EXCEPTION 'Participation conflict requires review' USING ERRCODE='23514'; END IF;
 UPDATE atlas.personal_training_invitations
 SET state='accepted',accepted_at=now(),accepted_by_principal_id=v_principal WHERE id=v_i.id;
 RETURN jsonb_build_object('ok',true,'state','accepted','programId',v_i.program_id);
END;$function$;

CREATE FUNCTION atlas.personal_training_revoke_self_api_v1(p_invitation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_p uuid:=atlas.current_principal_id_v1(); v_i atlas.personal_training_invitations%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR v_p IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_i FROM atlas.personal_training_invitations WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL OR v_i.sender_principal_id<>v_p
 THEN RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE='42501'; END IF;
 IF v_i.state='revoked' THEN RETURN jsonb_build_object('ok',true,'state','revoked'); END IF;
 IF v_i.state<>'issued' THEN RAISE EXCEPTION 'Cannot revoke settled invitation' USING ERRCODE='23514'; END IF;
 UPDATE atlas.personal_training_invitations SET state='revoked',revoked_at=now() WHERE id=v_i.id;
 RETURN jsonb_build_object('ok',true,'state','revoked');
END;$function$;

CREATE FUNCTION atlas.personal_training_withdraw_self_api_v1(p_program_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,atlas,auth AS $function$
DECLARE v_p uuid:=atlas.current_principal_id_v1(); v_row atlas.personal_training_participations%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR v_p IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_row FROM atlas.personal_training_participations
 WHERE program_id=p_program_id AND principal_id=v_p FOR UPDATE;
 IF v_row.id IS NULL THEN RAISE EXCEPTION 'Participation unavailable' USING ERRCODE='42501'; END IF;
 IF v_row.state='active' THEN UPDATE atlas.personal_training_participations
  SET state='withdrawn',withdrawn_at=now(),share_progress=false WHERE id=v_row.id; END IF;
 RETURN jsonb_build_object('ok',true,'state','withdrawn');
END;$function$;

-- No anonymous execution or direct access to any of the three tables.
REVOKE ALL ON FUNCTION
 atlas.personal_training_create_self_api_v1(text,jsonb,jsonb,date,boolean,text),
 atlas.personal_training_invite_self_api_v1(uuid,text,text),
 atlas.personal_training_pending_self_api_v1(),
 atlas.personal_training_decide_self_api_v1(uuid,text),
 atlas.personal_training_revoke_self_api_v1(uuid),
 atlas.personal_training_withdraw_self_api_v1(uuid)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 atlas.personal_training_create_self_api_v1(text,jsonb,jsonb,date,boolean,text),
 atlas.personal_training_invite_self_api_v1(uuid,text,text),
 atlas.personal_training_pending_self_api_v1(),
 atlas.personal_training_decide_self_api_v1(uuid,text),
 atlas.personal_training_revoke_self_api_v1(uuid),
 atlas.personal_training_withdraw_self_api_v1(uuid)
TO authenticated;
COMMIT;
