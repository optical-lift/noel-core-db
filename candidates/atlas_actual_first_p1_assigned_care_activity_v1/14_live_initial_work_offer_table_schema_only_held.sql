-- HELD P1: recover exact existing live pending individual offer gate TABLE
-- in one freshly disposable RiverSong database, never production.
-- Canonical native assignment checks this table for competing outstanding
-- individual offers. An absent table is not authority to bypass the check.
-- DDL from current Noel pg_catalog, 2026-11-05; zero rows, no fake offers.
DO $pre$
BEGIN IF to_regclass('atlas.company_work_initial_responsibility_offers') IS NOT NULL
THEN RAISE EXCEPTION 'STOP existing live offer table already in schema'; END IF;
END;$pre$;
CREATE TABLE atlas.company_work_initial_responsibility_offers (
id uuid NOT NULL DEFAULT gen_random_uuid(),
organization_id uuid NOT NULL,
work_item_id uuid NOT NULL,
ledger_id uuid NOT NULL,
offered_by_person_id uuid NOT NULL,
offered_by_membership_id uuid,
target_person_id uuid NOT NULL,
target_membership_id uuid,
reason text NOT NULL,
offer_state text NOT NULL DEFAULT 'offered'::text,
accepted_allocation_id uuid,
offered_at timestamp with time zone NOT NULL DEFAULT now(),
resolved_at timestamp with time zone,
resolution_reason text,
CONSTRAINT company_work_initial_responsibili_offered_by_membership_id_fkey FOREIGN KEY (offered_by_membership_id) REFERENCES atlas.organization_memberships(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_accepted_allocation_id_fkey FOREIGN KEY (accepted_allocation_id) REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_o_offered_by_person_id_fkey FOREIGN KEY (offered_by_person_id) REFERENCES reality.entities(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_o_target_membership_id_fkey FOREIGN KEY (target_membership_id) REFERENCES atlas.organization_memberships(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_offer_target_person_id_fkey FOREIGN KEY (target_person_id) REFERENCES reality.entities(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_offers_check CHECK ((offered_by_person_id <> target_person_id)),
CONSTRAINT company_work_initial_responsibility_offers_check1 CHECK ((((offer_state = 'offered'::text) AND (resolved_at IS NULL) AND (accepted_allocation_id IS NULL)) OR ((offer_state = 'accepted'::text) AND (resolved_at IS NOT NULL) AND (accepted_allocation_id IS NOT NULL)) OR ((offer_state = ANY (ARRAY['declined'::text, 'stale'::text, 'withdrawn'::text])) AND (resolved_at IS NOT NULL) AND (accepted_allocation_id IS NULL)))),
CONSTRAINT company_work_initial_responsibility_offers_ledger_id_fkey FOREIGN KEY (ledger_id) REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_offers_offer_state_check CHECK ((offer_state = ANY (ARRAY['offered'::text, 'accepted'::text, 'declined'::text, 'stale'::text, 'withdrawn'::text]))),
CONSTRAINT company_work_initial_responsibility_offers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
CONSTRAINT company_work_initial_responsibility_offers_pkey PRIMARY KEY (id),
CONSTRAINT company_work_initial_responsibility_offers_reason_check CHECK (((length(btrim(reason)) >= 1) AND (length(btrim(reason)) <= 1200))),
CONSTRAINT company_work_initial_responsibility_offers_work_item_id_fkey FOREIGN KEY (work_item_id) REFERENCES atlas.work_items(id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX company_work_initial_responsibility_one_pending_v1 ON atlas.company_work_initial_responsibility_offers USING btree (work_item_id) WHERE (offer_state = 'offered'::text);
REVOKE ALL ON TABLE atlas.company_work_initial_responsibility_offers FROM PUBLIC,anon,authenticated,service_role;
DO $proof$
BEGIN
 IF (SELECT count(*) FROM atlas.company_work_initial_responsibility_offers)<>0 OR
 (SELECT count(*) FROM pg_constraint WHERE conrelid='atlas.company_work_initial_responsibility_offers'::regclass)<>13 OR
 (SELECT count(*) FROM pg_attribute WHERE attrelid='atlas.company_work_initial_responsibility_offers'::regclass AND attnum>0 AND NOT attisdropped)<>14 OR
 (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.company_work_initial_responsibility_offers'::regclass) OR
 has_table_privilege('authenticated','atlas.company_work_initial_responsibility_offers','SELECT') OR
 has_table_privilege('anon','atlas.company_work_initial_responsibility_offers','SELECT')
 THEN RAISE EXCEPTION 'STOP competing offer exact live gate not preserved'; END IF;
 RAISE NOTICE 'PASS native individual pending-offer table recreated empty with exact check/FKs';
END;$proof$;
