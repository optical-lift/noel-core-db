BEGIN;
-- Private Noel Mark photo-component owner-review kernel. Candidate source, not deployment.
-- Structural only. No original photographs, owner records, browser permissions or model labels.

CREATE TABLE mark.photo_component_catalogues (
 catalogue_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 capture_id bigint NOT NULL REFERENCES mark.captures(capture_id) ON DELETE RESTRICT,
 capture_sha256 text NOT NULL CHECK (capture_sha256 ~ '^[0-9a-f]{64}$'),
 image_width int NOT NULL CHECK (image_width > 0),
 image_height int NOT NULL CHECK (image_height > 0),
 catalogue_digest text NOT NULL CHECK (catalogue_digest ~ '^[0-9a-f]{64}$'),
 algorithm_key text NOT NULL CHECK (length(algorithm_key) BETWEEN 3 AND 120),
 expected_count int NOT NULL CHECK (expected_count BETWEEN 1 AND 10000000),
 original_photo_in_database boolean NOT NULL DEFAULT false CHECK (original_photo_in_database=false),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (capture_id, catalogue_digest)
);
COMMENT ON TABLE mark.photo_component_catalogues IS
 'Immutable physical capture-bound machine component inventory; not canonical glyph identity.';

CREATE TABLE mark.photo_component_proposals (
 catalogue_id uuid NOT NULL REFERENCES mark.photo_component_catalogues(catalogue_id) ON DELETE RESTRICT,
 component_id int NOT NULL CHECK (component_id > 0),
 original_x int NOT NULL CHECK (original_x >= 0),
 original_y int NOT NULL CHECK (original_y >= 0),
 original_width int NOT NULL CHECK (original_width >= 4),
 original_height int NOT NULL CHECK (original_height >= 4),
 kind text NOT NULL CHECK(kind IN ('SINGLE_COMPONENT_SHAPE_CANDIDATE',
   'FRAGMENT_OR_SHORT_STROKE','EDGE_INCOMPLETE','POSSIBLY_JOINED_OR_DAMAGE')),
 machine_group text CHECK(machine_group IS NULL OR machine_group ~ '^[TBW]-[0-9]{3}$'),
 feature_version text NOT NULL CHECK(length(feature_version) BETWEEN 2 AND 120),
 ink_boundary_approved boolean NOT NULL DEFAULT false CHECK(ink_boundary_approved=false),
 training_authorized boolean NOT NULL DEFAULT false CHECK(training_authorized=false),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(catalogue_id,component_id)
);
CREATE INDEX photo_machine_group_lookup
 ON mark.photo_component_proposals(catalogue_id,machine_group,component_id);

CREATE TABLE mark.photo_catalogue_admissions (
 catalogue_id uuid PRIMARY KEY REFERENCES mark.photo_component_catalogues(catalogue_id) ON DELETE RESTRICT,
 verified_sha256 text NOT NULL CHECK (verified_sha256 ~ '^[0-9a-f]{64}$'),
 verified_digest text NOT NULL CHECK (verified_digest ~ '^[0-9a-f]{64}$'),
 verified_count int NOT NULL CHECK (verified_count>0),
 verified_by text NOT NULL CHECK(length(verified_by) BETWEEN 4 AND 180),
 verification_receipt text NOT NULL CHECK(length(verification_receipt) BETWEEN 8 AND 500),
 admitted_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE mark.photo_catalogue_admissions IS
 'Verified private capture and component census; supplied hash alone is not proof of owner authorization.';

CREATE TABLE mark.photo_owner_review_events (
 event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 catalogue_id uuid NOT NULL REFERENCES mark.photo_catalogue_admissions(catalogue_id) ON DELETE RESTRICT,
 action text NOT NULL CHECK(action IN ('ASSIGN','UNDO')),
 owner_actor_key text NOT NULL CHECK(length(owner_actor_key) BETWEEN 4 AND 180),
 verified_auth_receipt_key text NOT NULL CHECK(length(verified_auth_receipt_key) BETWEEN 8 AND 200),
 client_event_id uuid NOT NULL,
 client_sequence bigint NOT NULL CHECK(client_sequence>0),
 undo_of_event_id bigint REFERENCES mark.photo_owner_review_events(event_id) ON DELETE RESTRICT,
 original_capture_sha256 text NOT NULL CHECK(original_capture_sha256 ~ '^[0-9a-f]{64}$'),
 event_scope text NOT NULL CHECK(length(event_scope) BETWEEN 3 AND 180),
 received_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(catalogue_id,event_id),
 UNIQUE(catalogue_id,owner_actor_key,client_event_id),
 UNIQUE(catalogue_id,owner_actor_key,client_sequence),
 CHECK ((action='ASSIGN' AND undo_of_event_id IS NULL)
     OR (action='UNDO' AND undo_of_event_id IS NOT NULL))
);
CREATE UNIQUE INDEX photo_review_undo_once
 ON mark.photo_owner_review_events(undo_of_event_id) WHERE action='UNDO';
CREATE INDEX photo_review_event_history
 ON mark.photo_owner_review_events(catalogue_id,owner_actor_key,event_id DESC);
COMMENT ON TABLE mark.photo_owner_review_events IS
 'Append-only owner action, authenticated independently at a not-yet-released owner bridge.';

CREATE TABLE mark.photo_owner_review_decisions (
 catalogue_id uuid NOT NULL,
 event_id bigint NOT NULL,
 component_id int NOT NULL,
 reviewed_x int NOT NULL CHECK(reviewed_x>=0),
 reviewed_y int NOT NULL CHECK(reviewed_y>=0),
 reviewed_width int NOT NULL CHECK(reviewed_width>=4),
 reviewed_height int NOT NULL CHECK(reviewed_height>=4),
 verdict text NOT NULL CHECK(verdict IN ('VISUAL_FAMILY','NOT_THIS_FAMILY',
  'CREASE','DAMAGE','FRAGMENT','POSSIBLE_JOIN','UNKNOWN')),
 family_tag text CHECK(family_tag IS NULL OR family_tag ~ '^[A-Za-z][A-Za-z0-9_/-]{1,30}$'),
 boundary_authority text NOT NULL DEFAULT 'OWNER_ADJUSTED_REVIEW_RECTANGLE_NOT_INK_MASK'
    CHECK(boundary_authority='OWNER_ADJUSTED_REVIEW_RECTANGLE_NOT_INK_MASK'),
 training_authorized boolean NOT NULL DEFAULT false CHECK(training_authorized=false),
 semantic_function_assigned boolean NOT NULL DEFAULT false CHECK(semantic_function_assigned=false),
 complete_ink_mask_approved boolean NOT NULL DEFAULT false CHECK(complete_ink_mask_approved=false),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(event_id,component_id),
 FOREIGN KEY(catalogue_id,event_id)
  REFERENCES mark.photo_owner_review_events(catalogue_id,event_id) ON DELETE RESTRICT,
 FOREIGN KEY(catalogue_id,component_id)
  REFERENCES mark.photo_component_proposals(catalogue_id,component_id) ON DELETE RESTRICT,
 CHECK((verdict IN ('VISUAL_FAMILY','NOT_THIS_FAMILY') AND family_tag IS NOT NULL)
    OR(verdict NOT IN ('VISUAL_FAMILY','NOT_THIS_FAMILY') AND family_tag IS NULL))
);
CREATE INDEX photo_review_decisions_by_source
 ON mark.photo_owner_review_decisions(catalogue_id,component_id,event_id DESC);
CREATE INDEX photo_review_decisions_by_family
 ON mark.photo_owner_review_decisions(catalogue_id,family_tag,event_id DESC)
 WHERE family_tag IS NOT NULL;

CREATE FUNCTION mark.photo_verify_catalogue_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
DECLARE c record;
BEGIN
 SELECT sha256,width_px,height_px INTO c FROM mark.captures WHERE capture_id=NEW.capture_id;
 IF NOT FOUND OR c.sha256 IS DISTINCT FROM NEW.capture_sha256 OR
  c.width_px IS DISTINCT FROM NEW.image_width OR c.height_px IS DISTINCT FROM NEW.image_height THEN
  RAISE EXCEPTION 'Original source capture hash/dimensions mismatch';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER photo_capture_source_gate BEFORE INSERT ON mark.photo_component_catalogues
 FOR EACH ROW EXECUTE FUNCTION mark.photo_verify_catalogue_source();

CREATE FUNCTION mark.photo_verify_component_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
DECLARE c record;
BEGIN
 SELECT image_width,image_height INTO c FROM mark.photo_component_catalogues WHERE catalogue_id=NEW.catalogue_id FOR UPDATE;
 IF NOT FOUND OR NEW.original_x + NEW.original_width > c.image_width
  OR NEW.original_y + NEW.original_height > c.image_height THEN
   RAISE EXCEPTION 'Original component rectangle outside capture';
 END IF;
 IF EXISTS(SELECT 1 FROM mark.photo_catalogue_admissions WHERE catalogue_id=NEW.catalogue_id) THEN
   RAISE EXCEPTION 'Admitted component catalogue is frozen';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER photo_component_source_gate BEFORE INSERT ON mark.photo_component_proposals
 FOR EACH ROW EXECUTE FUNCTION mark.photo_verify_component_source();

CREATE FUNCTION mark.photo_verify_catalogue_admission() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
DECLARE c record; n bigint;
BEGIN
 SELECT capture_sha256,catalogue_digest,expected_count INTO c
 FROM mark.photo_component_catalogues WHERE catalogue_id=NEW.catalogue_id FOR UPDATE;
 IF NOT FOUND OR c.capture_sha256 IS DISTINCT FROM NEW.verified_sha256
  OR c.catalogue_digest IS DISTINCT FROM NEW.verified_digest THEN
  RAISE EXCEPTION 'Catalogue hash verification failed';
 END IF;
 SELECT count(*) INTO n FROM mark.photo_component_proposals WHERE catalogue_id=NEW.catalogue_id;
 IF n<>c.expected_count OR n<>NEW.verified_count THEN
  RAISE EXCEPTION 'Original component inventory incomplete';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER photo_catalogue_admission_gate BEFORE INSERT ON mark.photo_catalogue_admissions
 FOR EACH ROW EXECUTE FUNCTION mark.photo_verify_catalogue_admission();

CREATE FUNCTION mark.photo_verify_owner_event() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
DECLARE c record; prior record;
BEGIN
 SELECT capture_sha256 INTO c FROM mark.photo_component_catalogues WHERE catalogue_id=NEW.catalogue_id;
 IF NOT FOUND OR c.capture_sha256 IS DISTINCT FROM NEW.original_capture_sha256 THEN
  RAISE EXCEPTION 'Owner review capture mismatch';
 END IF;
 IF NEW.action='UNDO' THEN
  SELECT catalogue_id,owner_actor_key,action INTO prior
   FROM mark.photo_owner_review_events WHERE event_id=NEW.undo_of_event_id;
  IF NOT FOUND OR prior.catalogue_id IS DISTINCT FROM NEW.catalogue_id OR
   prior.owner_actor_key IS DISTINCT FROM NEW.owner_actor_key OR prior.action <> 'ASSIGN' THEN
   RAISE EXCEPTION 'Undo not authorized for this actor/source';
  END IF;
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER photo_owner_event_source_gate BEFORE INSERT ON mark.photo_owner_review_events
 FOR EACH ROW EXECUTE FUNCTION mark.photo_verify_owner_event();

CREATE FUNCTION mark.photo_verify_review_rectangle() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
DECLARE c record; e record; total bigint;
BEGIN
 SELECT image_width,image_height INTO c FROM mark.photo_component_catalogues
 WHERE catalogue_id=NEW.catalogue_id;
 IF NOT FOUND OR NEW.reviewed_x+NEW.reviewed_width>c.image_width
  OR NEW.reviewed_y+NEW.reviewed_height>c.image_height THEN
  RAISE EXCEPTION 'Owner review rectangle outside capture';
 END IF;
 SELECT action INTO e FROM mark.photo_owner_review_events
 WHERE event_id=NEW.event_id AND catalogue_id=NEW.catalogue_id FOR UPDATE;
 IF NOT FOUND OR e.action<>'ASSIGN' THEN RAISE EXCEPTION 'No assignable owner event'; END IF;
 SELECT count(*) INTO total FROM mark.photo_owner_review_decisions WHERE event_id=NEW.event_id;
 IF total>=600 THEN RAISE EXCEPTION 'Review batch exceeds 600'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER photo_review_rectangle_gate BEFORE INSERT ON mark.photo_owner_review_decisions
 FOR EACH ROW EXECUTE FUNCTION mark.photo_verify_review_rectangle();

CREATE FUNCTION mark.photo_deny_evidence_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,mark AS $$
BEGIN
 RAISE EXCEPTION 'Immutable photo evidence: append a new event';
END;
$$;
CREATE TRIGGER photo_catalogue_immutable BEFORE UPDATE OR DELETE ON mark.photo_component_catalogues
 FOR EACH ROW EXECUTE FUNCTION mark.photo_deny_evidence_mutation();
CREATE TRIGGER photo_component_immutable BEFORE UPDATE OR DELETE ON mark.photo_component_proposals
 FOR EACH ROW EXECUTE FUNCTION mark.photo_deny_evidence_mutation();
CREATE TRIGGER photo_admission_immutable BEFORE UPDATE OR DELETE ON mark.photo_catalogue_admissions
 FOR EACH ROW EXECUTE FUNCTION mark.photo_deny_evidence_mutation();
CREATE TRIGGER photo_event_immutable BEFORE UPDATE OR DELETE ON mark.photo_owner_review_events
 FOR EACH ROW EXECUTE FUNCTION mark.photo_deny_evidence_mutation();
CREATE TRIGGER photo_decision_immutable BEFORE UPDATE OR DELETE ON mark.photo_owner_review_decisions
 FOR EACH ROW EXECUTE FUNCTION mark.photo_deny_evidence_mutation();

CREATE VIEW mark.photo_owner_current_reviews WITH (security_invoker=true) AS
 SELECT DISTINCT ON (d.catalogue_id,d.component_id,e.owner_actor_key)
  d.catalogue_id,d.component_id,e.owner_actor_key,e.event_id,e.received_at,
  p.original_x,p.original_y,p.original_width,p.original_height,
  d.reviewed_x,d.reviewed_y,d.reviewed_width,d.reviewed_height,
  d.verdict,d.family_tag,d.boundary_authority
 FROM mark.photo_owner_review_decisions d
 JOIN mark.photo_owner_review_events e ON e.event_id=d.event_id AND e.catalogue_id=d.catalogue_id
 JOIN mark.photo_component_proposals p ON p.catalogue_id=d.catalogue_id AND p.component_id=d.component_id
 WHERE e.action='ASSIGN' AND NOT EXISTS (
  SELECT 1 FROM mark.photo_owner_review_events undo
  WHERE undo.action='UNDO' AND undo.undo_of_event_id=e.event_id)
 ORDER BY d.catalogue_id,d.component_id,e.owner_actor_key,e.event_id DESC;
COMMENT ON VIEW mark.photo_owner_current_reviews IS
 'Read-only derived owner visual decisions with append-only reversal history; never canonical marks.';

ALTER TABLE mark.photo_component_catalogues ENABLE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_component_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_catalogue_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_owner_review_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_owner_review_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_component_catalogues FORCE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_component_proposals FORCE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_catalogue_admissions FORCE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_owner_review_events FORCE ROW LEVEL SECURITY;
ALTER TABLE mark.photo_owner_review_decisions FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE mark.photo_component_catalogues,mark.photo_component_proposals,
 mark.photo_catalogue_admissions,mark.photo_owner_review_events,
 mark.photo_owner_review_decisions,mark.photo_owner_current_reviews
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE mark.photo_owner_review_events_event_id_seq
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION mark.photo_verify_catalogue_source(),
 mark.photo_verify_component_source(),mark.photo_verify_catalogue_admission(),
 mark.photo_verify_owner_event(),mark.photo_verify_review_rectangle(),
 mark.photo_deny_evidence_mutation()
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
