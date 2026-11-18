-- Fictional PG17-only carrier and authority tests for HELD M3.6.
-- NOT production schema: current source function remains governed/released.
ALTER TABLE atlas.ledgers ADD COLUMN status text NOT NULL DEFAULT 'active';
ALTER TABLE atlas.principals ADD COLUMN person_id uuid REFERENCES reality.entities(id);
ALTER TABLE atlas.principals ADD COLUMN status text NOT NULL DEFAULT 'active';
CREATE TABLE atlas.organizations (
 id uuid PRIMARY KEY, status text NOT NULL
);
CREATE TABLE atlas.ledger_organization_participations (
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL,
 organization_id uuid NOT NULL,
 participation_kind text NOT NULL,
 status text NOT NULL,
 ended_at timestamptz
);
CREATE TABLE atlas.principal_ledger_authorities (
 id uuid PRIMARY KEY,
 principal_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 authority_kind text NOT NULL,
 status text NOT NULL
);
INSERT INTO atlas.ledgers(id,status) VALUES
 ('77777777-7777-4777-8777-777777777777','active');
INSERT INTO atlas.organizations(id,status) VALUES
 ('b7777777-7777-4777-8777-777777777777','active');
INSERT INTO atlas.ledger_organization_participations(
 id,ledger_id,organization_id,participation_kind,status)
VALUES (
 'c7777777-7777-4777-8777-777777777777',
 '77777777-7777-4777-8777-777777777777',
 'b7777777-7777-4777-8777-777777777777',
 'governing','active'
);
-- Fictitious outsider is the *institutional governor* but NOT the
-- private Course author. The private author has no root Ledger authority.
INSERT INTO atlas.principals(id,person_id,status) VALUES
 ('d7777777-7777-4777-8777-777777777777',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd','active');
INSERT INTO atlas.principal_ledger_authorities(
 id,principal_id,ledger_id,authority_kind,status) VALUES(
 'e7777777-7777-4777-8777-777777777777',
 'd7777777-7777-4777-8777-777777777777',
 '77777777-7777-4777-8777-777777777777',
 'root_governing','active'
);
-- Fictitious signed root guard modeled after RELEASED source:
-- only active principal linked to the current signed Person and
-- root_governing authority over exactly the supplied legacy Ledger ID.
CREATE FUNCTION atlas.capability_root_authority_context_self_v1(
 p_ledger_id uuid
) RETURNS TABLE(
 person_id uuid,principal_id uuid,principal_ledger_authority_id uuid
) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog AS $fictional_root$
DECLARE v_person uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 RETURN QUERY
 SELECT p.person_id,p.id,a.id
 FROM atlas.principals p JOIN atlas.principal_ledger_authorities a
 ON a.principal_id=p.id
 WHERE p.person_id=v_person AND p.status='active'
 AND a.ledger_id=p_ledger_id
 AND a.authority_kind='root_governing' AND a.status='active';
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Current root governor authority missing'
   USING ERRCODE='42501';
 END IF;
END
$fictional_root$;

-- This NONPRODUCT test transport is created ONLY on fictional scratch PG17.
-- The actual held governor prerequisite remains unexposed to the browser.
CREATE FUNCTION public.clone_test_shared_course_governor_self_v1(p_ledger_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog AS $fictional_test$
BEGIN
 PERFORM atlas.require_shared_course_native_ledger_governor_self_v1(p_ledger_id);
 RETURN true;
END
$fictional_test$;
REVOKE ALL ON FUNCTION public.clone_test_shared_course_governor_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.clone_test_shared_course_governor_self_v1(uuid)
 TO authenticated;
