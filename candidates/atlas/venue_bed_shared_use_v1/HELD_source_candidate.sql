-- HELD / DRAFT ONLY. NOT A MIGRATION. DO NOT APPLY TO PRODUCTION.
-- Owner design: original Flower Bed remains one identity/custody; Venue can gain
-- bounded exact-Bed USE and associate EXISTING Venue-owned Work. No new Work,
-- Bed, farm custody, global read permission, or broad RLS policy.
-- All new SQL is additive. Never replace guard_work_growing_object_context_v1.
-- Pre-release: protected full-schema disposable clone, signed GoTrue/PostgREST
-- governor/worker/outsider/revoked tests, security review, explicit source release.
BEGIN;

CREATE TABLE atlas.venue_bed_shared_use_authorizations_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bed_id uuid NOT NULL REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT,
  flower_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  venue_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  use_kind text NOT NULL DEFAULT 'venue_work_reference'
    CHECK (use_kind = 'venue_work_reference'),
  use_state text NOT NULL DEFAULT 'offered'
    CHECK (use_state IN ('offered','active','withdrawn')),
  offered_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  offered_at timestamptz NOT NULL DEFAULT now(),
  offer_action_id text NOT NULL CHECK (
    length(btrim(offer_action_id)) BETWEEN 1 AND 128
  ),
  accepted_by_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  accepted_at timestamptz,
  withdrawn_by_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  withdrawn_at timestamptz,
  CONSTRAINT venue_bed_distinct_ledgers_v1 CHECK (flower_ledger_id <> venue_ledger_id),
  CONSTRAINT venue_bed_use_lifecycle_v1 CHECK (
    (use_state = 'offered'
      AND accepted_by_principal_id IS NULL AND accepted_at IS NULL
      AND withdrawn_by_principal_id IS NULL AND withdrawn_at IS NULL)
    OR (use_state = 'active'
      AND accepted_by_principal_id IS NOT NULL AND accepted_at IS NOT NULL
      AND withdrawn_by_principal_id IS NULL AND withdrawn_at IS NULL)
    OR (use_state = 'withdrawn'
      AND withdrawn_by_principal_id IS NOT NULL AND withdrawn_at IS NOT NULL)
  ),
  CONSTRAINT venue_bed_offer_action_idempotent_v1
    UNIQUE (flower_ledger_id, offer_action_id),
  CONSTRAINT venue_bed_use_exact_reference_key_v1
    UNIQUE (id, venue_ledger_id, bed_id)
);

CREATE UNIQUE INDEX venue_bed_one_current_use_v1
ON atlas.venue_bed_shared_use_authorizations_v1 (bed_id, venue_ledger_id)
WHERE use_state IN ('offered','active');

CREATE TABLE atlas.venue_bed_work_references_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  use_authorization_id uuid NOT NULL
    REFERENCES atlas.venue_bed_shared_use_authorizations_v1(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  venue_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  bed_id uuid NOT NULL REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT,
  recorded_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  source_action_id text NOT NULL
    CHECK (length(btrim(source_action_id)) BETWEEN 1 AND 128),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  -- This is a Venue source reference, NOT a copy of Work or a replacement
  -- for the canonical work_item_context_links table / source Work engine.
  CONSTRAINT venue_bed_work_one_reference_v1
    UNIQUE (use_authorization_id, work_item_id),
  CONSTRAINT venue_bed_work_action_idempotent_v1
    UNIQUE (venue_ledger_id, source_action_id),
  CONSTRAINT venue_bed_work_ref_exact_authorization_v1
    FOREIGN KEY (use_authorization_id, venue_ledger_id, bed_id)
    REFERENCES atlas.venue_bed_shared_use_authorizations_v1
      (id, venue_ledger_id, bed_id) ON DELETE RESTRICT
);

-- Store authorized relationships privately. No direct authenticated table
-- read/write, and no public API wrapper in this held candidate.
ALTER TABLE atlas.venue_bed_shared_use_authorizations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.venue_bed_work_references_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.venue_bed_shared_use_authorizations_v1 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE atlas.venue_bed_work_references_v1 FROM PUBLIC, anon, authenticated;

-- Pure source check, NOT an authorization to read Bed contents.
CREATE FUNCTION atlas.venue_bed_shared_use_source_current_v1(
  p_bed_id uuid, p_flower_ledger_id uuid, p_venue_ledger_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM atlas.growing_objects bed
    JOIN atlas.farms farm ON farm.id=bed.farm_id
    JOIN atlas.farm_crop_ledger_custody_v1 custody
      ON custody.farm_id=farm.id
      AND custody.ledger_id=p_flower_ledger_id
      AND custody.custody_state='active' AND custody.ended_at IS NULL
    JOIN atlas.ledger_organization_participations flower_participation
      ON flower_participation.organization_id=farm.organization_id
      AND flower_participation.ledger_id=p_flower_ledger_id
      AND flower_participation.status='active'
      AND flower_participation.ended_at IS NULL
      AND flower_participation.participation_kind IN ('governing','operating')
    JOIN atlas.ledgers flower_app_ledger
      ON flower_app_ledger.id=p_flower_ledger_id
      AND flower_app_ledger.status='active'
    JOIN ledger.ledgers flower_ledger
      ON flower_ledger.id=flower_app_ledger.id
      AND flower_ledger.ledger_state='active'
      AND flower_ledger.retired_at IS NULL
    JOIN atlas.ledgers venue_app_ledger
      ON venue_app_ledger.id=p_venue_ledger_id
      AND venue_app_ledger.status='active'
    JOIN ledger.ledgers venue_ledger
      ON venue_ledger.id=venue_app_ledger.id
      AND venue_ledger.ledger_state='active'
      AND venue_ledger.retired_at IS NULL
    WHERE bed.id=p_bed_id AND bed.object_type='bed'
      AND p_flower_ledger_id<>p_venue_ledger_id
      AND EXISTS (
        SELECT 1 FROM atlas.ledger_organization_participations venue_participation
        WHERE venue_participation.ledger_id=p_venue_ledger_id
          AND venue_participation.status='active'
          AND venue_participation.ended_at IS NULL
          AND venue_participation.participation_kind IN ('governing','operating')
      )
  );
$$;

-- Internal issuer: current signed Flower governor offers one exact Bed to
-- one other existing native Ledger. No content or rights granted yet.
CREATE FUNCTION atlas.offer_venue_bed_shared_use_self_v1(
  p_flower_ledger_id uuid, p_venue_ledger_id uuid,
  p_bed_id uuid, p_source_action_id text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_principal uuid;
  v_offer atlas.venue_bed_shared_use_authorizations_v1%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
    OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Current signed session required' USING ERRCODE='42501';
  END IF;
  v_principal := atlas.current_principal_id_v1();
  IF v_principal IS NULL
    OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
      v_principal,p_flower_ledger_id),false)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(p_flower_ledger_id);
  IF p_source_action_id IS NULL
     OR length(btrim(p_source_action_id)) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'Stable source action required' USING ERRCODE='22023';
  END IF;
  IF NOT atlas.venue_bed_shared_use_source_current_v1(
    p_bed_id,p_flower_ledger_id,p_venue_ledger_id)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_offer FROM atlas.venue_bed_shared_use_authorizations_v1
   WHERE flower_ledger_id=p_flower_ledger_id AND offer_action_id=p_source_action_id;
  IF FOUND THEN
    IF v_offer.bed_id<>p_bed_id OR v_offer.venue_ledger_id<>p_venue_ledger_id
      OR v_offer.offered_by_principal_id<>v_principal
    THEN RAISE EXCEPTION 'Source action reused' USING ERRCODE='23505';
    END IF;
    RETURN v_offer.id;
  END IF;
  INSERT INTO atlas.venue_bed_shared_use_authorizations_v1 (
    bed_id,flower_ledger_id,venue_ledger_id,offered_by_principal_id,offer_action_id
  ) VALUES (p_bed_id,p_flower_ledger_id,p_venue_ledger_id,
    v_principal,p_source_action_id) RETURNING * INTO v_offer;
  RETURN v_offer.id;
END;
$$;

-- Internal recipient acceptance. Must be a DIFFERENT exact native-Ledger
-- authority check; the offer alone gives Venue nothing.
CREATE FUNCTION atlas.accept_venue_bed_shared_use_self_v1(p_offer_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_principal uuid;
  v_offer atlas.venue_bed_shared_use_authorizations_v1%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
    OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Current signed session required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_offer FROM atlas.venue_bed_shared_use_authorizations_v1
    WHERE id=p_offer_id FOR UPDATE;
  v_principal := atlas.current_principal_id_v1();
  IF v_offer.id IS NULL OR v_principal IS NULL
    OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
      v_principal,v_offer.venue_ledger_id),false)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(v_offer.venue_ledger_id);
  IF NOT atlas.venue_bed_shared_use_source_current_v1(
    v_offer.bed_id,v_offer.flower_ledger_id,v_offer.venue_ledger_id)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  IF v_offer.use_state='active' AND v_offer.accepted_by_principal_id=v_principal
  THEN RETURN v_offer.id; END IF;
  IF v_offer.use_state<>'offered' THEN
    RAISE EXCEPTION 'No current offer' USING ERRCODE='42501';
  END IF;
  UPDATE atlas.venue_bed_shared_use_authorizations_v1
    SET use_state='active',accepted_by_principal_id=v_principal,accepted_at=now()
    WHERE id=v_offer.id;
  RETURN v_offer.id;
END;
$$;

-- Internal exact Venue-Work attachment. The original Work, Bed and crop
-- custody remain unchanged. Relevance alone does NOT reveal Work details.
CREATE FUNCTION atlas.establish_venue_work_bed_reference_self_v1(
  p_use_authorization_id uuid, p_work_item_id uuid,
  p_source_action_id text, p_human_review jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_principal uuid;
  v_use atlas.venue_bed_shared_use_authorizations_v1%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_bed atlas.growing_objects%ROWTYPE;
  v_existing atlas.venue_bed_work_references_v1%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
    OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Current signed session required' USING ERRCODE='42501';
  END IF;
  v_principal := atlas.current_principal_id_v1();
  SELECT * INTO v_use FROM atlas.venue_bed_shared_use_authorizations_v1
    WHERE id=p_use_authorization_id AND use_state='active';
  IF v_use.id IS NULL OR v_principal IS NULL
    OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
      v_principal,v_use.venue_ledger_id),false)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(v_use.venue_ledger_id);
  IF NOT atlas.venue_bed_shared_use_source_current_v1(
    v_use.bed_id,v_use.flower_ledger_id,v_use.venue_ledger_id)
  THEN RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  IF p_source_action_id IS NULL
    OR length(btrim(p_source_action_id)) NOT BETWEEN 1 AND 128
    OR p_human_review IS NULL OR jsonb_typeof(p_human_review)<>'object'
    OR p_human_review->>'humanConfirmed' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'Bounded Work review required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id;
  SELECT * INTO v_bed FROM atlas.growing_objects WHERE id=v_use.bed_id;
  IF v_work.id IS NULL OR v_work.work_state<>'open'
     OR v_work.organization_id IS NULL
     OR v_bed.id IS NULL
     OR p_human_review->>'reviewedWorkStableKey' IS DISTINCT FROM v_work.stable_key
     OR p_human_review->>'reviewedBedStableKey' IS DISTINCT FROM v_bed.stable_key
     OR NOT EXISTS (
       SELECT 1 FROM atlas.company_work_native_ledger_relevance relevance
       JOIN atlas.ledger_organization_participations participation
         ON participation.organization_id=relevance.organization_id
         AND participation.ledger_id=relevance.ledger_id
         AND participation.status='active' AND participation.ended_at IS NULL
         AND participation.participation_kind IN ('operating','governing')
       WHERE relevance.work_item_id=v_work.id
         AND relevance.organization_id=v_work.organization_id
         AND relevance.ledger_id=v_use.venue_ledger_id
         AND relevance.attribution_state='active'
     )
  THEN RAISE EXCEPTION 'Venue Work source unproven' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_existing FROM atlas.venue_bed_work_references_v1
    WHERE venue_ledger_id=v_use.venue_ledger_id
      AND source_action_id=p_source_action_id;
  IF FOUND THEN
    IF v_existing.work_item_id<>v_work.id
       OR v_existing.bed_id<>v_bed.id
       OR v_existing.use_authorization_id<>v_use.id
       OR v_existing.recorded_by_principal_id<>v_principal
    THEN RAISE EXCEPTION 'Source action reused' USING ERRCODE='23505';
    END IF;
    RETURN v_existing.id;
  END IF;
  INSERT INTO atlas.venue_bed_work_references_v1 (
    use_authorization_id,work_item_id,venue_ledger_id,bed_id,
    recorded_by_principal_id,source_action_id
  ) VALUES (
    v_use.id,v_work.id,v_use.venue_ledger_id,v_bed.id,v_principal,p_source_action_id
  ) RETURNING * INTO v_existing;
  RETURN v_existing.id;
END;
$$;

-- Both current Venue and Flower root governors may terminate Venue's use.
-- Historical Work references remain, but future effective read/operation
-- MUST join current use_state and re-check source custody at request time.
CREATE FUNCTION atlas.withdraw_venue_bed_shared_use_self_v1(p_use_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_use atlas.venue_bed_shared_use_authorizations_v1%ROWTYPE;
  v_principal uuid;
  v_ledger uuid;
BEGIN
  IF auth.uid() IS NULL
    OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Current signed session required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_use FROM atlas.venue_bed_shared_use_authorizations_v1
    WHERE id=p_use_id FOR UPDATE;
  v_principal := atlas.current_principal_id_v1();
  IF v_use.id IS NULL OR v_principal IS NULL THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  IF coalesce(atlas.principal_has_ledger_authority_v1(
    v_principal,v_use.flower_ledger_id),false)
  THEN v_ledger:=v_use.flower_ledger_id;
  ELSIF coalesce(atlas.principal_has_ledger_authority_v1(
    v_principal,v_use.venue_ledger_id),false)
  THEN v_ledger:=v_use.venue_ledger_id;
  ELSE RAISE EXCEPTION 'Not found' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(v_ledger);
  IF v_use.use_state='withdrawn' THEN RETURN true; END IF;
  UPDATE atlas.venue_bed_shared_use_authorizations_v1
    SET use_state='withdrawn', withdrawn_by_principal_id=v_principal,
        withdrawn_at=now()
    WHERE id=v_use.id;
  RETURN true;
END;
$$;

-- No public wrapper and no authenticated execution grant: draft source only.
REVOKE ALL ON FUNCTION atlas.venue_bed_shared_use_source_current_v1(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atlas.offer_venue_bed_shared_use_self_v1(uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atlas.accept_venue_bed_shared_use_self_v1(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atlas.establish_venue_work_bed_reference_self_v1(uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atlas.withdraw_venue_bed_shared_use_self_v1(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
