-- DISPOSABLE PRODUCTION-SCHEMA CLONE ONLY; apply after the pinned C1 and
-- reciprocal native-Ledger fixtures. Never a live migration or Person grant.
-- Owner already governs organization-primary Ledger A; Worker governs
-- operating Ledger B. This adds owner as a SECOND governor of B.
INSERT INTO atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis
) VALUES (
  'e5200000-0000-4000-8000-000000000603',
  'e5200000-0000-4000-8000-000000000111',
  'e5200000-0000-4000-8000-000000000402',
  'root_governing','active','option_c_signed_clone_second_governor'
);
-- No-seat canonical Person can be inspected as a *current B participant*
-- only by the real governor; no linked Principal is invented.
INSERT INTO ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis)
VALUES (
  'e5200000-0000-4000-8000-000000000506',
  'e5200000-0000-4000-8000-000000000402',
  'e5200000-0000-4000-8000-000000000104',
  'active','{"cloneFixture":true,"purpose":"unresolved_no_principal"}'
);

-- P1A: one fictional original Work / shared-subject source; disclosure remains governor-only.
-- All fixtures remain in ephemeral local validation DB. This explicitly does
-- not create real Work or reveal the Subject to the signed worker.
INSERT INTO atlas.farms(id,stable_key,name,organization_id)
VALUES ('e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-farm','Option C Fictional Farm',
        'e5200000-0000-4000-8000-000000000801');
INSERT INTO atlas.growing_objects(id,farm_id,stable_key,label,object_type)
VALUES ('e5200000-0000-4000-8000-000000000902',
        'e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-bed','Fictional Bed for source review','bed');
INSERT INTO atlas.work_items(id,organization_id,title,work_state)
VALUES ('e5200000-0000-4000-8000-000000000903',
        'e5200000-0000-4000-8000-000000000801',
        'Fictional single original Work','open');
INSERT INTO atlas.work_allocations(
   id,organization_id,work_item_id,assignee_canonical_person_id,
   establishment_basis_kind,establishment_basis,allocation_role,state
) VALUES (
   'e5200000-0000-4000-8000-000000000904',
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000903',
   'e5200000-0000-4000-8000-000000000102',
   'ledger_connection_direct_assignment','{"cloneFixture":true}'::jsonb,
   'responsible','active');
INSERT INTO atlas.company_work_native_ledger_relevance(
   id,organization_id,work_item_id,ledger_id,
   evidence_kind,attestation_source_ref,attestation_reason,established_by_person_id
) VALUES (
   'e5200000-0000-4000-8000-000000000905',
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000903',
   'e5200000-0000-4000-8000-000000000402',
   'owner_attested','option-c-disposable-source',
   'One fictional original Work serving the operating Ledger only.',
   'e5200000-0000-4000-8000-000000000101');
INSERT INTO atlas.work_item_context_links(
   id,organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind
) VALUES (
   'e5200000-0000-4000-8000-000000000906',
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000903',
   'spatial','growing_object','e5200000-0000-4000-8000-000000000902',
   'acts_on');
INSERT INTO atlas.subject_disclosure_decision_events_v1(
   id,organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
   subject_id,disclosure_class,decision_kind,source_action_id,reason,decided_by_person_id
) VALUES (
   'e5200000-0000-4000-8000-000000000907',
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000402',
   'e5200000-0000-4000-8000-000000000102',
   'spatial','growing_object','e5200000-0000-4000-8000-000000000902',
   'identity','grant','e5200000-0000-4000-8000-000000000909',
   'Fictional governor grants only this Subject identity source.',
   'e5200000-0000-4000-8000-000000000101'
),(
   'e5200000-0000-4000-8000-000000000908',
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000402',
   'e5200000-0000-4000-8000-000000000102',
   'spatial','growing_object','e5200000-0000-4000-8000-000000000902',
   'condition','withhold','e5200000-0000-4000-8000-000000000910',
   'Fictional governor withholds independent Subject condition.',
   'e5200000-0000-4000-8000-000000000101'
);
