-- Private Titus PILOT grant: single reviewed data transaction, not a migration.
-- Requires a protected OWNER issue and protected production environment.
-- Run ONLY via the guarded issuance workflow with a trusted server-side psql
-- connection as postgres. Do not copy into a Supabase SQL editor.
-- :pilot_email, :pilot_receipt, :pilot_days are psql variables, escaped as SQL
-- string literals with :'name', never composed into SQL identifiers.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='25s';

SELECT pg_catalog.set_config('titus.pilot.email', :'pilot_email', true) AS ignored \gset
SELECT pg_catalog.set_config('titus.pilot.receipt', :'pilot_receipt', true) AS ignored \gset
SELECT pg_catalog.set_config('titus.pilot.days', :'pilot_days', true) AS ignored \gset

-- This lock serializes other grant issues and forbids a racing duplicate.
LOCK TABLE titus.customer_workspace_entitlements_v1 IN SHARE ROW EXCLUSIVE MODE;

DO $issue$
DECLARE
  v_email text := pg_catalog.current_setting('titus.pilot.email');
  v_receipt text := pg_catalog.current_setting('titus.pilot.receipt');
  v_days integer;
  v_matches integer;
  v_user uuid;
  v_prior titus.customer_workspace_entitlements_v1%ROWTYPE;
  v_confirmed boolean;
BEGIN
  -- Privileged execution, not a public authenticated-user API.
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Titus pilot issue requires protected postgres release role'
      USING ERRCODE='42501';
  END IF;
  -- Owner request #2489 authorizes exactly this existing test account.
  -- A structurally plausible issue number is NOT an authorization to
  -- award an unrelated user a pilot grant.
  IF pg_catalog.lower(v_email) <> 'lexprjct@gmail.com'
     OR v_receipt <> 'github:optical-lift/noel-core-db/issues/2489#titus-private-pilot-v1' THEN
    RAISE EXCEPTION 'Titus pilot target or owner receipt not authorized'
      USING ERRCODE='42501';
  END IF;
  IF length(v_email) NOT BETWEEN 6 AND 254
    OR v_email !~* '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    OR v_email<>pg_catalog.btrim(v_email) THEN
    RAISE EXCEPTION 'Invalid exact pilot email' USING ERRCODE='22023';
  END IF;
  IF v_receipt !~ '^github:optical-lift/noel-core-db/issues/[1-9][0-9]*#titus-private-pilot-v1$'
    OR length(v_receipt)>200 THEN
    RAISE EXCEPTION 'Invalid source-approved pilot issue receipt'
      USING ERRCODE='22023';
  END IF;
  BEGIN
    v_days:=pg_catalog.current_setting('titus.pilot.days')::integer;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Invalid pilot duration' USING ERRCODE='22023';
  END;
  IF v_days<1 OR v_days>180 THEN
    RAISE EXCEPTION 'Pilot duration must be 1 to 180 days'
      USING ERRCODE='22023';
  END IF;

  -- Exact, current, unique Auth account: no test user creation,
  -- no Person role, no trust in mutable profile/user_metadata claims.
  SELECT count(*),min(id::text)::uuid INTO v_matches,v_user
  FROM auth.users WHERE pg_catalog.lower(email)=pg_catalog.lower(v_email);
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'Pilot target must match exactly one existing Auth account'
      USING ERRCODE='42501';
  END IF;
  SELECT (
    deleted_at IS NULL
    AND NOT coalesce(is_anonymous,false)
    AND (email_confirmed_at IS NOT NULL OR phone_confirmed_at IS NOT NULL)
    AND (banned_until IS NULL OR banned_until<=now())
  ) INTO v_confirmed FROM auth.users WHERE id=v_user;
  IF NOT coalesce(v_confirmed,false) THEN
    RAISE EXCEPTION 'Pilot target is not an eligible confirmed Auth account'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_prior FROM titus.customer_workspace_entitlements_v1
    WHERE owner_auth_user_id=v_user;
  IF v_prior.owner_auth_user_id IS NOT NULL THEN
    -- Exact current active source receipt is an idempotent retry; anything
    -- else needs an independent owner-authorized revocation/renewal path.
    IF v_prior.grant_kind<>'private_pilot'
       OR v_prior.grant_source_receipt<>v_receipt
       OR v_prior.state<>'active'
       OR (v_prior.valid_until IS NOT NULL AND v_prior.valid_until<=now()) THEN
      RAISE EXCEPTION 'Conflicting or inactive prior Titus entitlement'
        USING ERRCODE='23505';
    END IF;
  ELSE
    INSERT INTO titus.customer_workspace_entitlements_v1(
      owner_auth_user_id,grant_kind,grant_source_receipt,state,valid_until
    ) VALUES(
      v_user,'private_pilot',v_receipt,'active',
      pg_catalog.clock_timestamp()+(v_days || ' days')::interval
    );
  END IF;
END;
$issue$;

-- Only minimal verification values enter job logs; no target UUIDs, tokens.
SELECT
  (SELECT count(*) FROM titus.customer_workspace_entitlements_v1 e
     JOIN auth.users u ON u.id=e.owner_auth_user_id
     WHERE pg_catalog.lower(u.email)=pg_catalog.lower(
       pg_catalog.current_setting('titus.pilot.email'))
       AND e.grant_kind='private_pilot'
       AND e.state='active'
       AND (e.valid_until IS NULL OR e.valid_until>now())
       AND e.grant_source_receipt=pg_catalog.current_setting('titus.pilot.receipt')
  ) AS verified_exact_active_pilot,
  (SELECT count(*) FROM titus.customer_workspace_entitlements_v1) AS all_pilots_and_purchases,
  (SELECT count(*) FROM titus.customer_workspaces_v1) AS unchanged_workspace_count,
  (SELECT count(*) FROM titus.customer_course_drafts_v1) AS unchanged_course_count;
COMMIT;
