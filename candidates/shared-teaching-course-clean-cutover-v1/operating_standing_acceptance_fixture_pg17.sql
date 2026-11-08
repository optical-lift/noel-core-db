-- Disposable PG17 fictional Teaching entitlement/activation source ONLY.
-- No real Teaching entitlement, authorization, institution or student data.
ALTER TABLE atlas.capability_activations
 ADD COLUMN ledger_id uuid,
 ADD COLUMN capability_key text,
 ADD COLUMN capability_version integer,
 ADD COLUMN subject_ledger_id uuid,
 ADD COLUMN state text;
INSERT INTO atlas.capability_activations(
 id,ledger_id,capability_key,capability_version,subject_ledger_id,state)
VALUES(
 'a7777777-7777-4777-8777-777777777777',
 '77777777-7777-4777-8777-777777777777',
 'teaching',1,
 '77777777-7777-4777-8777-777777777777','active');
CREATE TABLE atlas.fictional_teaching_entitlement(
 ledger_id uuid PRIMARY KEY,
 capability_key text NOT NULL,
 capability_version integer NOT NULL,
 state text NOT NULL
);
INSERT INTO atlas.fictional_teaching_entitlement VALUES(
 '77777777-7777-4777-8777-777777777777','teaching',1,'active');

CREATE FUNCTION atlas.capability_entitlement_grant_live_v1(
 p_ledger_id uuid,p_capability_key text,p_capability_version integer
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog AS $entitlement$
 SELECT EXISTS (SELECT 1 FROM atlas.fictional_teaching_entitlement e
 WHERE e.ledger_id=p_ledger_id AND e.capability_key=p_capability_key
 AND e.capability_version=p_capability_version AND e.state='active')
$entitlement$;
CREATE FUNCTION atlas.teaching_activation_active_v1(
 p_ledger_id uuid,p_capability_activation_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog AS $activation$
 SELECT EXISTS(SELECT 1 FROM atlas.capability_activations a
 WHERE a.id=p_capability_activation_id AND a.ledger_id=p_ledger_id
 AND a.subject_ledger_id=p_ledger_id
 AND a.capability_key='teaching' AND a.capability_version=1
 AND a.state='active')
$activation$;
