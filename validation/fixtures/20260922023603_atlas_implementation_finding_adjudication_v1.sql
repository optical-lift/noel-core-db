-- Clone-only fixture for Atlas Implementation Finding Adjudication v1.
-- Establishes one assigned practitioner, one non-assigned practitioner, one open
-- Implementation Case/Thread, several proposed Findings, and one already-promoted
-- same-case Reality Candidate for existing-domain-fact proof.

insert into auth.users(id) values
  ('f4700000-0000-4000-8000-000000000001'::uuid),
  ('f4700000-0000-4000-8000-000000000002'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values
(
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true,"role":"assigned"}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4700000-0000-4000-8000-000000000002'::uuid,
  'active',
  '{"validationFixture":true,"role":"unassigned"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider,provider_checkout_session_id,offer_key,starting_label,
  payment_option,purchase_state,currency,setup_contract_amount_cents,
  monthly_ledger_unit_price_cents,metadata
) values (
  'f4700000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_finding_adjudication',
  'validation_finding_adjudication',
  'Finding Adjudication Proof',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values (
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,
  active,basis,metadata
) values (
  'f4700000-0000-4000-8000-000000000121'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'practitioner',
  true,
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_threads(
  id,implementation_case_id,work_area,title,state,author_user_id,shared_with_participants
) values (
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'structure_mismatch',
  'Finding adjudication proof',
  'open',
  'f4700000-0000-4000-8000-000000000001'::uuid,
  false
);

insert into atlas.implementation_findings(
  id,implementation_thread_id,statement,status,author_user_id
) values
(
  'f4700000-0000-4000-8000-000000000141'::uuid,
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'The intake-to-dispatch interpretation uses the governed configuration crosswalk.',
  'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid
),
(
  'f4700000-0000-4000-8000-000000000142'::uuid,
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'The institution already knows the canonical Person represented by this promoted Reality Candidate.',
  'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid
),
(
  'f4700000-0000-4000-8000-000000000143'::uuid,
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'Decision authority should be reassigned.',
  'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid
),
(
  'f4700000-0000-4000-8000-000000000144'::uuid,
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'A later Finding replaces the earlier interpretation.',
  'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid
);

insert into atlas.implementation_reality_candidates(
  id,
  implementation_case_id,
  implementation_thread_id,
  contract_version,
  operation_id,
  origin_kind,
  literal_statement,
  subject_binding,
  object_binding,
  context_binding,
  evidence_refs,
  establishment_basis,
  candidate_state,
  canonical_consequence_kind,
  canonical_consequence_ref,
  promoted_at,
  promoted_by_user_id,
  author_user_id,
  provenance
) values (
  'f4700000-0000-4000-8000-000000000151'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000131'::uuid,
  'implementation_reality_candidate_v1',
  'institutional_person_record.establish',
  'manual_semantic_construction',
  'Proof Organization knows Proof Person as an institutional Person.',
  '{"kind":"person","label":"Proof Person","resolution":"canonical","canonicalId":"f4700000-0000-4000-8000-000000000211"}'::jsonb,
  '{"kind":"organization","label":"Proof Organization","resolution":"canonical","canonicalId":"f4700000-0000-4000-8000-000000000212"}'::jsonb,
  null,
  '[]'::jsonb,
  '{"kind":"adjudicated_existing_reality","validationFixture":true}'::jsonb,
  'promoted',
  'institutional_person_record',
  'f4700000-0000-4000-8000-000000000213',
  now(),
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'f4700000-0000-4000-8000-000000000001'::uuid,
  '{"validationFixture":true}'::jsonb
);
