-- ACCESS-01 TEST ONLY: append AFTER existing synthetic unified Today Event
-- disclosure fixture in a disposable production-shaped clone. Never production.
-- A second canonical open Work belongs to the same Ledger but another Event;
-- identity disclosure of Event A cannot authorize a search across to Work B.
INSERT INTO atlas.work_items(
 id,organization_id,title,work_state,source_object_type,source_object_id,
 stable_key,metadata
) VALUES (
 'f5210000-0000-4000-8000-000000000902'::uuid,
 'f5210000-0000-4000-8000-000000000010'::uuid,
 'Private unrelated Event B preparation','open',
 'ledger_occurrence_shared_work',
 'f5210000-0000-4000-8000-000000000102'::uuid,
 'clone-private-other-event-task-f521',
 '{"ledgerId":"f5210000-0000-4000-8000-000000000014","cloneFixture":true}'::jsonb
);
INSERT INTO atlas.company_work_native_ledger_relevance(
 organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
 attestation_source_ref,attestation_reason,established_by_person_id
) VALUES (
 'f5210000-0000-4000-8000-000000000010'::uuid,
 'f5210000-0000-4000-8000-000000000902'::uuid,
 'f5210000-0000-4000-8000-000000000014'::uuid,
 'serves_purpose','owner_attested','clone:other-event-work-f521',
 'The synthetic governor retains a separate original Work on the second Event.',
 'f5210000-0000-4000-8000-000000000004'::uuid
);
INSERT INTO atlas.work_item_context_links(
 organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind
) VALUES (
 'f5210000-0000-4000-8000-000000000010'::uuid,
 'f5210000-0000-4000-8000-000000000902'::uuid,
 'temporal','occurrence','f5210000-0000-4000-8000-000000000102'::uuid,'for'
);
