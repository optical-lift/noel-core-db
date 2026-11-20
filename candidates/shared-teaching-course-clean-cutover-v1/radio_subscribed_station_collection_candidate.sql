-- HELD Radio subscription originals + current-Person collection read.
-- Scratch candidate only. No station, membership, subscription, publication
-- or issuer is seeded. No writer, no billing, no independent identity system.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('titus.reject_account_context_original_mutation_v1()') IS NULL
 OR to_regclass('ledger.ledgers') IS NULL
 THEN RAISE EXCEPTION 'held Radio subscription clone prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;
-- Station is a programming place operated through a native Ledger, not
-- another institutional identity. Its UUID is the collection grouping key.
CREATE TABLE titus.radio_stations_v1 (
 station_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200 AND title=btrim(title) AND title !~ '[[:cntrl:]]'),
 established_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 retired_at timestamptz,
 UNIQUE(station_id,ledger_id),
 CHECK(retired_at IS NULL OR retired_at>=established_at)
);
CREATE TABLE titus.radio_programs_v1 (
 program_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 station_id uuid NOT NULL REFERENCES titus.radio_stations_v1(station_id) ON DELETE RESTRICT,
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200 AND title=btrim(title)),
 established_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 retired_at timestamptz,
 UNIQUE(program_id,station_id),
 CHECK(retired_at IS NULL OR retired_at>=established_at)
);
-- Library membership is distinct from institution account administration.
-- This initial candidate handles a Ledger's library only, not product seats.
CREATE TABLE titus.library_memberships_v1 (
 membership_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 issuer_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 source_receipt text NOT NULL UNIQUE CHECK(length(btrim(source_receipt)) BETWEEN 8 AND 256),
 accepted_at timestamptz NOT NULL,
 valid_until timestamptz,
 UNIQUE(membership_id,ledger_id,person_id),
 CHECK(valid_until IS NULL OR valid_until>accepted_at)
);
CREATE TABLE titus.library_membership_endings_v1 (
 membership_id uuid PRIMARY KEY REFERENCES titus.library_memberships_v1(membership_id) ON DELETE RESTRICT,
 ended_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 source_receipt text NOT NULL UNIQUE CHECK(length(btrim(source_receipt)) BETWEEN 8 AND 256),
 ended_at timestamptz NOT NULL
);
-- Exact program inclusion or station subscription. A nullable program ID
-- signifies station-level subscription only; it confers no blanket media access.
-- Membership inclusion requires matching Person and governing Ledger by FK.
CREATE TABLE titus.radio_subscriptions_v1 (
 subscription_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 station_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 program_id uuid,
 person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 membership_id uuid,
 issuer_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 source_receipt text NOT NULL UNIQUE CHECK(length(btrim(source_receipt)) BETWEEN 8 AND 256),
 accepted_at timestamptz NOT NULL,
 valid_until timestamptz,
 FOREIGN KEY(station_id,ledger_id) REFERENCES titus.radio_stations_v1(station_id,ledger_id) ON DELETE RESTRICT,
 FOREIGN KEY(program_id,station_id) REFERENCES titus.radio_programs_v1(program_id,station_id) ON DELETE RESTRICT,
 FOREIGN KEY(membership_id,ledger_id,person_id) REFERENCES titus.library_memberships_v1(membership_id,ledger_id,person_id) ON DELETE RESTRICT,
 CHECK(valid_until IS NULL OR valid_until>accepted_at)
);
CREATE INDEX radio_subscriptions_person_scope_v1 ON titus.radio_subscriptions_v1(person_id,station_id);
CREATE TABLE titus.radio_subscription_endings_v1 (
 subscription_id uuid PRIMARY KEY REFERENCES titus.radio_subscriptions_v1(subscription_id) ON DELETE RESTRICT,
 ended_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 source_receipt text NOT NULL UNIQUE CHECK(length(btrim(source_receipt)) BETWEEN 8 AND 256),
 ended_at timestamptz NOT NULL
);
DO $privacy$
DECLARE n text;
BEGIN
 FOREACH n IN ARRAY ARRAY['radio_stations_v1','radio_programs_v1','library_memberships_v1',
 'library_membership_endings_v1','radio_subscriptions_v1','radio_subscription_endings_v1'] LOOP
  EXECUTE format('ALTER TABLE titus.%I ENABLE ROW LEVEL SECURITY',n);
  EXECUTE format('REVOKE ALL ON TABLE titus.%I FROM PUBLIC,anon,authenticated',n);
  IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
   EXECUTE format('REVOKE ALL ON TABLE titus.%I FROM service_role',n);
  END IF;
 END LOOP;
 FOREACH n IN ARRAY ARRAY['library_memberships_v1','library_membership_endings_v1',
 'radio_subscriptions_v1','radio_subscription_endings_v1'] LOOP
  EXECUTE format('CREATE TRIGGER immutable_original BEFORE UPDATE OR DELETE ON titus.%I FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1()',n);
 END LOOP;
END $privacy$;
-- This is a fresh current-Person read, not a Course or account-context check.
-- No caller Person argument, roster, membership detail, media location or
-- publishing authority. Ledger retirement or ended membership removes its cover
-- if no independent subscription remains. Exact media rights are evaluated
-- separately on each request, never from the collection response.
CREATE FUNCTION public.titus_radio_subscribed_stations_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $read$
DECLARE v_person uuid; v_now timestamptz; v_rows jsonb; v_count bigint;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 IF v_person IS NULL THEN RAISE EXCEPTION 'current Person required' USING ERRCODE='42501'; END IF;
 v_now:=clock_timestamp();
 SELECT count(*),coalesce(jsonb_agg(jsonb_build_object(
  'subscriptionId',x.subscription_id,'stationId',x.station_id,
  'stationName',x.title,'programId',x.program_id) ORDER BY x.station_id,x.subscription_id),'[]'::jsonb)
 INTO v_count,v_rows
 FROM (
  SELECT s.subscription_id,s.station_id,st.title,s.program_id
  FROM titus.radio_subscriptions_v1 s
  JOIN titus.radio_stations_v1 st ON st.station_id=s.station_id AND st.ledger_id=s.ledger_id
  JOIN ledger.ledgers l ON l.id=s.ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL
  JOIN reality.entities e ON e.id=l.subject_entity_id AND e.identity_state='canonical'
  LEFT JOIN titus.radio_programs_v1 p ON p.program_id=s.program_id AND p.station_id=s.station_id
  LEFT JOIN titus.library_memberships_v1 m ON m.membership_id=s.membership_id
    AND m.ledger_id=s.ledger_id AND m.person_id=s.person_id
  WHERE s.person_id=v_person AND s.accepted_at<=v_now
  AND (s.valid_until IS NULL OR s.valid_until>v_now)
  AND st.established_at<=v_now AND st.retired_at IS NULL
  AND (s.program_id IS NULL OR (p.program_id IS NOT NULL AND p.established_at<=v_now AND p.retired_at IS NULL))
  AND NOT EXISTS(SELECT 1 FROM titus.radio_subscription_endings_v1 x
    WHERE x.subscription_id=s.subscription_id AND x.ended_at<=v_now)
  AND (s.membership_id IS NULL OR (m.membership_id IS NOT NULL AND m.accepted_at<=v_now
    AND (m.valid_until IS NULL OR m.valid_until>v_now)
    AND NOT EXISTS(SELECT 1 FROM titus.library_membership_endings_v1 x
      WHERE x.membership_id=m.membership_id AND x.ended_at<=v_now)))
  ORDER BY s.station_id,s.subscription_id LIMIT 1001
 ) x;
 IF v_count>1000 THEN RAISE EXCEPTION 'Radio collection exceeds bounded response' USING ERRCODE='54000'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscribed_stations_v1',
   'personId',v_person,'subscriptions',v_rows);
END $read$;
REVOKE ALL ON FUNCTION public.titus_radio_subscribed_stations_self_api_v1() FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
  EXECUTE 'REVOKE ALL ON FUNCTION public.titus_radio_subscribed_stations_self_api_v1() FROM service_role';
 END IF;
END $acl$;
GRANT EXECUTE ON FUNCTION public.titus_radio_subscribed_stations_self_api_v1() TO authenticated;
