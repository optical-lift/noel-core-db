-- DISPOSABLE C1 VENUE EXTENSION ONLY; fictional identity and Work context.
-- Append to immutable C1 fictional fixture from commit
-- 83833e3efbb2e18c6376b56eb3982df5b8c000b3. NO production use.
-- Do not assert that fixture establishment is a real human action.

-- Every signed actor must have their own native Personal Atlas to pass
-- the existing real-session membrane.
INSERT INTO personal.atlases(person_entity_id,atlas_state,native)
SELECT seed.person_entity_id,'active',true FROM (VALUES
 ('e5200000-0000-4000-8000-000000000101'::uuid),
 ('e5200000-0000-4000-8000-000000000102'::uuid),
 ('e5200000-0000-4000-8000-000000000103'::uuid),
 ('e5200000-0000-4000-8000-000000000104'::uuid)
) seed(person_entity_id)
WHERE NOT EXISTS (
 SELECT 1 FROM personal.atlases a WHERE a.person_entity_id=seed.person_entity_id
);

-- The immutable C1 base fixture contains signed Persons/Seats, but NO farm,
-- growing Beds or original Work 901. These are explicit synthetic dependencies
-- for this Venue proof; never infer they came from production or a real Farm.
INSERT INTO atlas.farms(
  id,stable_key,name,organization_id,organization_unit_id,metadata
) VALUES (
  'e5200000-0000-4000-8000-000000000b01',
  'clone-universal-garden','Fictional Flower Test Farm',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000802',
  '{"fictional":true}'::jsonb
);
-- Source-backed Flower physical-context positive parity: these zones,
-- task and responsibility are synthetic C1 prerequisite facts, not a new
-- Work/Bed issued by the Venue permission.
INSERT INTO atlas.zones(id,farm_id,stable_key,label)
VALUES
 ('e5200000-0000-4000-8000-000000000a01',
  'e5200000-0000-4000-8000-000000000b01',
  'clone-physical-bed-zone','Fictional Flower Bed Zone'),
 ('e5200000-0000-4000-8000-000000000a02',
  'e5200000-0000-4000-8000-000000000b01',
  'clone-withheld-physical-zone','Fictional Withheld Zone');

INSERT INTO atlas.growing_objects(
  id,farm_id,zone_id,stable_key,label,object_type,metadata
) VALUES
('e5200000-0000-4000-8000-000000000b03',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000a01',
 'clone-upick-bed-3','Fictional Flower Bed 3','bed',
 '{"fictional":true,"privateNote":"private-held"}'::jsonb),
('e5200000-0000-4000-8000-000000000b04',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000a01',
 'clone-upick-bed-4','Fictional Flower Bed 4','bed',
 '{"fictional":true}'::jsonb),
('e5200000-0000-4000-8000-000000000b05',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000a02',
 'clone-withheld-bed-5','Fictional Withheld Bed','bed',
 '{"fictional":true,"sourceOwnerOnly":true}'::jsonb);

-- Existing Flower original Work, deliberately NOT Venue-relevant. This is a
-- wrong-Ledger negative subject, not a fabricated new Work from Venue link.
INSERT INTO atlas.tasks(
 id,farm_id,zone_id,title,task_type,status,organization_id,task_scope,metadata
) VALUES (
 'e5200000-0000-4000-8000-000000000a11',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000a01',
 'Fictional Flower Bed 3 preparation','general','open',
 'e5200000-0000-4000-8000-000000000801','farm_operation',
 '{"cloneOnly":true,"sourceTask":true}'::jsonb
);
INSERT INTO atlas.organization_memberships(
 id,organization_id,user_id,role,active
) VALUES
 ('e5200000-0000-4000-8000-000000000a21',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000001','owner',true),
 ('e5200000-0000-4000-8000-000000000a22',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000002','member',true);
INSERT INTO atlas.work_items(
 id,organization_id,organization_unit_id,stable_key,title,work_state,
 source_object_type,source_object_id
) VALUES (
 'e5200000-0000-4000-8000-000000000901',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000802',
 'clone-flower-original-work-901',
 'Fictional Flower Work on original Bed','open',
 'legacy_task','e5200000-0000-4000-8000-000000000a11'
);
INSERT INTO atlas.work_allocations(
 id,organization_id,work_item_id,assignee_membership_id,
 allocation_role,state,metadata
) VALUES (
 'e5200000-0000-4000-8000-000000000a23',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000901',
 'e5200000-0000-4000-8000-000000000a22',
 'responsible','active',
 '{"cloneOnly":true,"source":"explicit_worker_task_company_work_adoption_v2",
   "legacyTaskId":"e5200000-0000-4000-8000-000000000a11"}'::jsonb
);
INSERT INTO atlas.company_work_native_ledger_relevance(
 organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
 attestation_source_ref,attestation_reason,established_by_person_id
) VALUES (
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000901',
 'e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:flower-work-901',
 'Existing original Work admitted to Flower only in disposable evidence',
 'e5200000-0000-4000-8000-000000000101'
);

-- Venue is a separate current native Ledger over the existing Organization.
-- Its independent root is the pre-existing C1 Other-Ledger Person, not Flower's.
INSERT INTO atlas.ledgers(id,stable_key,name,ledger_kind,status,organization_id)
VALUES (
 'e5200000-0000-4000-8000-000000000402',
 'venue-disposable-ledger-b','Fictional Venue Ledger',
 'governed_reality','active',
 'e5200000-0000-4000-8000-000000000801'
);

INSERT INTO atlas.ledger_organization_participations(
 id,ledger_id,organization_id,participation_kind,is_compatibility_primary,basis
) VALUES (
 'e5200000-0000-4000-8000-000000000804',
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000801',
 'operating',false,'{"fictional":true,"doesNotTransferFarmCustody":true}'::jsonb
);

INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status)
VALUES (
 'e5200000-0000-4000-8000-000000000113',
 'e5200000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000103',
 'disposable-venue-principal','Fictional Venue Governor','active'
);

INSERT INTO atlas.principal_ledger_authorities(
 id,principal_id,ledger_id,authority_kind,status,basis
) VALUES (
 'e5200000-0000-4000-8000-000000000603',
 'e5200000-0000-4000-8000-000000000113',
 'e5200000-0000-4000-8000-000000000402',
 'root_governing','active','disposable_venue_fixture'
);

-- Synthetic prerequisite: this exact fictional Farm is custodied to Flower A.
-- The existing active-Farm custody unique index remains in force.
INSERT INTO atlas.farm_crop_ledger_custody_v1(
 farm_id,ledger_id,authority_domain,custody_state,
 established_by_principal_id,adjudication
) VALUES (
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000401',
 'farm_crop_operations','active',
 'e5200000-0000-4000-8000-000000000111',
 '{"fictional":true,"FlowerOwnsOriginal":true,"VenueMayOnlyReference":true}'::jsonb
);

-- Existing original Venue Work: not a new Work issued by the tested command.
-- The distinct Venue-Ledger relevance is human-attested in the existing source
-- vocabulary; this fixture does not claim a source-verified Event origin.
INSERT INTO atlas.work_items(id,organization_id,stable_key,title,work_state)
VALUES (
 'e5200000-0000-4000-8000-000000000b20',
 'e5200000-0000-4000-8000-000000000801',
 'disposable-venue-work-near-bed',
 'Fictional Venue preparation near existing Bed','open'
);

INSERT INTO atlas.company_work_native_ledger_relevance(
 organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
 attestation_source_ref,attestation_reason,established_by_person_id
) VALUES (
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b20',
 'e5200000-0000-4000-8000-000000000402',
 'serves_purpose','owner_attested',
 'clone:venue-work-source-b20',
 'Fictional existing Venue Work only - not a new Work command',
 'e5200000-0000-4000-8000-000000000103'
);


-- The production-only schema dump has no reference policy rows. This
-- fictional policy permits the rightful Event checklist writer in this
-- clone, so a denial on ordinary already-existing Work means source mismatch
-- rather than a missing contract policy.
INSERT INTO atlas.work_result_contract_policies(
 contract_key,source_domain,acceptance_mode,active
) VALUES (
 'ledger_occurrence_shared_confirmation_v1',
 'organization','domain_adapter',true
);

-- Synthetic original Event binding positive prerequisite. This native
-- Occurrence is ALREADY a source of the Venue Ledger; signed link later
-- associates an existing original Venue Work with it, without Work creation.
INSERT INTO local_intel.occurrences(
 id,stable_key,title,occurrence_type,start_at,end_at,status
) VALUES (
 'e5200000-0000-4000-8000-000000000b40',
 'clone-venue-existing-work-event',
 'Fictional Venue original Event','community_event',
 '2030-10-30 16:00+00','2030-10-30 19:00+00','scheduled'
);
INSERT INTO ledger.occurrence_calendar_bindings(
 ledger_id,occurrence_id,binding_state
) VALUES (
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000b40','active'
);
INSERT INTO atlas.organization_occurrence_bindings(
 id,organization_id,occurrence_id,binding_state
) VALUES (
 'e5200000-0000-4000-8000-000000000b41',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b40','active'
);
