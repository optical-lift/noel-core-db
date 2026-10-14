BEGIN;

-- Identity-only household connection. This is NOT household membership
-- authorization, personal Atlas sharing, invitation email, or a Person merge.
CREATE TABLE IF NOT EXISTS atlas.household_identity_link_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
  household_member_id uuid NOT NULL REFERENCES atlas.household_members(id) ON DELETE RESTRICT,
  invited_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  secret_sha256 text NOT NULL UNIQUE,
  invitation_state text NOT NULL CHECK (invitation_state IN ('pending','accepted','revoked','expired')),
  expires_at timestamptz NOT NULL,
  accepted_by_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS household_identity_link_invitation_pending_idx
  ON atlas.household_identity_link_invitations(household_member_id)
  WHERE invitation_state='pending';
CREATE TABLE IF NOT EXISTS atlas.household_member_identity_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
  household_member_id uuid NOT NULL REFERENCES atlas.household_members(id) ON DELETE RESTRICT,
  target_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
  target_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_invitation_id uuid NOT NULL UNIQUE REFERENCES atlas.household_identity_link_invitations(id) ON DELETE RESTRICT,
  link_state text NOT NULL DEFAULT 'active' CHECK (link_state IN ('active','revoked')),
  linked_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by_user_id uuid REFERENCES auth.users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS household_identity_active_member_idx
  ON atlas.household_member_identity_links(household_member_id) WHERE link_state='active';
CREATE UNIQUE INDEX IF NOT EXISTS household_identity_active_person_in_house_idx
  ON atlas.household_member_identity_links(household_id,target_person_id) WHERE link_state='active';
CREATE INDEX IF NOT EXISTS household_identity_target_lookup_idx
  ON atlas.household_member_identity_links(target_auth_user_id) WHERE link_state='active';
ALTER TABLE atlas.household_identity_link_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.household_member_identity_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_identity_link_invitations FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.household_member_identity_links FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.household_identity_member_owner_v1(p_member_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth
AS $fn$
DECLARE v_hid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
  SELECT h.id INTO v_hid
  FROM atlas.household_members m
  JOIN atlas.households h ON h.id=m.household_id AND h.status='active'
  JOIN atlas.principals p ON p.id=h.principal_id AND p.status='active' AND p.user_id=auth.uid()
  WHERE m.id=p_member_id AND m.active=true
    AND m.user_id IS NULL AND (m.household_role IS DISTINCT FROM 'principal')
  ;
  IF v_hid IS NULL THEN RAISE EXCEPTION 'No authorized unlinked household member' USING errcode='42501'; END IF;
  RETURN v_hid;
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_link_status_self_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth
AS $fn$
DECLARE v_hid uuid; v_link_id uuid; v_invite_state text;
BEGIN
  v_hid:=atlas.household_identity_member_owner_v1(p_member_id);
  SELECT l.id INTO v_link_id FROM atlas.household_member_identity_links l
  WHERE l.household_id=v_hid AND l.household_member_id=p_member_id AND l.link_state='active';
  IF v_link_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok',true,'state','connected');
  END IF;
  SELECT CASE WHEN i.expires_at<=now() THEN 'expired' ELSE 'invitation_pending' END
    INTO v_invite_state
  FROM atlas.household_identity_link_invitations i
  WHERE i.household_id=v_hid AND i.household_member_id=p_member_id AND i.invitation_state='pending';
  RETURN jsonb_build_object('ok',true,'state',coalesce(v_invite_state,'not_connected'));
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_invite_create_self_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth,extensions
AS $fn$
DECLARE v_hid uuid; v_token text; v_exp timestamptz:=now()+interval '7 days'; v_invite uuid;
BEGIN
  v_hid:=atlas.household_identity_member_owner_v1(p_member_id);
  PERFORM 1 FROM atlas.household_members WHERE id=p_member_id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM atlas.household_member_identity_links
            WHERE household_member_id=p_member_id AND link_state='active') THEN
    RETURN jsonb_build_object('ok',false,'code','already_connected');
  END IF;
  UPDATE atlas.household_identity_link_invitations
    SET invitation_state='revoked',updated_at=now()
    WHERE household_member_id=p_member_id AND invitation_state='pending';
  -- 256 bits sourced from two independent random UUIDs. Only SHA-256 persists.
  v_token:=replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  INSERT INTO atlas.household_identity_link_invitations(
    household_id,household_member_id,invited_by_user_id,secret_sha256,invitation_state,expires_at
  ) VALUES(v_hid,p_member_id,auth.uid(),encode(extensions.digest(v_token,'sha256'),'hex'),'pending',v_exp)
  RETURNING id INTO v_invite;
  RETURN jsonb_build_object('ok',true,'token',v_token,'expiresAt',v_exp);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_invite_preview_self_v1(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth,extensions
AS $fn$
DECLARE v_inv atlas.household_identity_link_invitations%rowtype; v_label text; v_owner text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','sign_in_required');
  END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_or_expired');
  END IF;
  SELECT * INTO v_inv FROM atlas.household_identity_link_invitations
  WHERE secret_sha256=encode(extensions.digest(p_token,'sha256'),'hex')
    AND invitation_state='pending' AND expires_at>now();
  IF v_inv.id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_expired'); END IF;
  SELECT m.display_name INTO v_label
    FROM atlas.household_members m
    WHERE m.id=v_inv.household_member_id AND m.household_id=v_inv.household_id AND m.active;
  IF v_label IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_expired'); END IF;
  SELECT p.name INTO v_owner FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
  WHERE h.id=v_inv.household_id AND h.status='active' AND p.status='active';
  IF v_owner IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_or_expired'); END IF;
  RETURN jsonb_build_object('ok',true,'state','pending','invitedName',v_label,
     'householdOwnerName',v_owner,'expiresAt',v_inv.expires_at,
     'accessGranted',false);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_invite_accept_self_v1(p_token text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth,reality,personal,extensions
AS $fn$
DECLARE v_inv atlas.household_identity_link_invitations%rowtype;
        v_p atlas.principals%rowtype; v_member atlas.household_members%rowtype;
        v_h atlas.households%rowtype; v_existing uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_or_expired');
  END IF;
  SELECT * INTO v_inv FROM atlas.household_identity_link_invitations
  WHERE secret_sha256=encode(extensions.digest(p_token,'sha256'),'hex')
  FOR UPDATE;
  IF v_inv.id IS NULL OR v_inv.invitation_state<>'pending' OR v_inv.expires_at<=now() THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_or_expired');
  END IF;
  IF v_inv.invited_by_user_id=auth.uid() THEN
    RETURN jsonb_build_object('ok',false,'code','different_account_required');
  END IF;
  SELECT * INTO v_p FROM atlas.principals WHERE user_id=auth.uid() AND status='active';
  IF v_p.id IS NULL OR v_p.person_id IS NULL
      OR NOT EXISTS(SELECT 1 FROM atlas.people a WHERE a.id=v_p.person_id AND a.status='active')
      OR NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=auth.uid() AND a.email_confirmed_at IS NOT NULL AND a.deleted_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM atlas.person_auth_credentials c WHERE c.auth_user_id=auth.uid() AND c.person_id=v_p.person_id AND c.status='active' AND c.retired_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM reality.auth_person_bindings b WHERE b.auth_user_id=auth.uid() AND b.person_entity_id=v_p.person_id AND b.binding_state='active' AND b.retired_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM personal.atlases a WHERE a.person_entity_id=v_p.person_id AND a.native AND a.atlas_state='active')
  THEN
    RETURN jsonb_build_object('ok',false,'code','personal_atlas_identity_not_ready');
  END IF;
  SELECT * INTO v_member FROM atlas.household_members
     WHERE id=v_inv.household_member_id AND household_id=v_inv.household_id FOR UPDATE;
  SELECT * INTO v_h FROM atlas.households
     WHERE id=v_inv.household_id AND status='active';
  IF v_member.id IS NULL OR NOT v_member.active OR v_member.user_id IS NOT NULL
      OR v_member.household_role='principal' OR v_h.id IS NULL
      OR NOT EXISTS(SELECT 1 FROM atlas.principals p WHERE p.id=v_h.principal_id AND p.user_id=v_inv.invited_by_user_id AND p.status='active') THEN
    RETURN jsonb_build_object('ok',false,'code','invitation_no_longer_valid');
  END IF;
  SELECT id INTO v_existing FROM atlas.household_member_identity_links
  WHERE link_state='active' AND
      (household_member_id=v_member.id OR (household_id=v_h.id AND target_person_id=v_p.person_id))
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','already_connected_or_conflict');
  END IF;
  INSERT INTO atlas.household_member_identity_links(
    household_id,household_member_id,target_person_id,target_auth_user_id,accepted_invitation_id
  ) VALUES(v_h.id,v_member.id,v_p.person_id,auth.uid(),v_inv.id);
  UPDATE atlas.household_identity_link_invitations
    SET invitation_state='accepted',accepted_at=now(),accepted_by_user_id=auth.uid(),updated_at=now()
    WHERE id=v_inv.id;
  RETURN jsonb_build_object('ok',true,'state','connected','accessGranted',false,
    'notebookMerged',false,'householdMemberModified',false);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_link_disconnect_self_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,atlas,auth
AS $fn$
DECLARE v_link atlas.household_member_identity_links%rowtype;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
  SELECT l.* INTO v_link FROM atlas.household_member_identity_links l
  JOIN atlas.households h ON h.id=l.household_id
  JOIN atlas.principals p ON p.id=h.principal_id
  WHERE l.household_member_id=p_member_id AND l.link_state='active'
    AND (p.user_id=auth.uid() OR l.target_auth_user_id=auth.uid())
  FOR UPDATE OF l;
  IF v_link.id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_connected_or_not_authorized'); END IF;
  UPDATE atlas.household_member_identity_links
    SET link_state='revoked',revoked_at=now(),revoked_by_user_id=auth.uid()
    WHERE id=v_link.id;
  RETURN jsonb_build_object('ok',true,'state','not_connected');
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.household_identity_received_links_self_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog
AS $fn$
  SELECT jsonb_build_object('ok',true,'links',coalesce(jsonb_agg(jsonb_build_object(
    'householdMemberId',l.household_member_id,
    'householdOwnerName',p.name,
    'linkedAt',l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb))
  FROM atlas.household_member_identity_links l
  JOIN atlas.households h ON h.id=l.household_id
  JOIN atlas.principals p ON p.id=h.principal_id
  WHERE l.target_auth_user_id=auth.uid() AND l.link_state='active';
$fn$;

CREATE OR REPLACE FUNCTION public.household_identity_link_status_self_api_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_link_status_self_v1(p_member_id); $fn$;
CREATE OR REPLACE FUNCTION public.household_identity_invite_create_self_api_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_invite_create_self_v1(p_member_id); $fn$;
CREATE OR REPLACE FUNCTION public.household_identity_invite_preview_self_api_v1(p_token text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_invite_preview_self_v1(p_token); $fn$;
CREATE OR REPLACE FUNCTION public.household_identity_invite_accept_self_api_v1(p_token text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_invite_accept_self_v1(p_token); $fn$;
CREATE OR REPLACE FUNCTION public.household_identity_link_disconnect_self_api_v1(p_member_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_link_disconnect_self_v1(p_member_id); $fn$;
CREATE OR REPLACE FUNCTION public.household_identity_received_links_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $fn$ SELECT atlas.household_identity_received_links_self_v1(); $fn$;

REVOKE ALL ON FUNCTION atlas.household_identity_member_owner_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_link_status_self_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_invite_create_self_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_invite_preview_self_v1(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_invite_accept_self_v1(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_link_disconnect_self_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_identity_received_links_self_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.household_identity_link_status_self_api_v1(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.household_identity_invite_create_self_api_v1(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.household_identity_invite_preview_self_api_v1(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.household_identity_invite_accept_self_api_v1(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.household_identity_link_disconnect_self_api_v1(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.household_identity_received_links_self_api_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_identity_link_status_self_api_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.household_identity_invite_create_self_api_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.household_identity_invite_preview_self_api_v1(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.household_identity_invite_accept_self_api_v1(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.household_identity_link_disconnect_self_api_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.household_identity_received_links_self_api_v1() TO authenticated;

COMMIT;
