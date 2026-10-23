-- DML-only fixture for numbered weight-recognition migration on disposable clone.
-- No production account, email, personal note or research source is used.
insert into auth.users(id,aud,role,created_at,updated_at) values
('a1400000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
('a1400000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now());

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values
('a1400000-0000-4000-8000-000000000101','weight-signed-proof-one','person','Synthetic Weight Person One','canonical'),
('a1400000-0000-4000-8000-000000000102','weight-signed-proof-two','person','Synthetic Weight Person Two','canonical');

insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values
('a1400000-0000-4000-8000-000000000001','a1400000-0000-4000-8000-000000000101','active','{"localFixture":true}'),
('a1400000-0000-4000-8000-000000000002','a1400000-0000-4000-8000-000000000102','active','{"localFixture":true}');

insert into atlas.people(id,display_name,status) values
('a1400000-0000-4000-8000-000000000101','Synthetic Weight Person One','active'),
('a1400000-0000-4000-8000-000000000102','Synthetic Weight Person Two','active');

insert into atlas.person_auth_credentials(person_id,credential_kind,auth_user_id,status,provenance) values
('a1400000-0000-4000-8000-000000000101','supabase_auth_user','a1400000-0000-4000-8000-000000000001','active','{"localFixture":true}'),
('a1400000-0000-4000-8000-000000000102','supabase_auth_user','a1400000-0000-4000-8000-000000000002','active','{"localFixture":true}');

insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values
('a1400000-0000-4000-8000-000000000201','a1400000-0000-4000-8000-000000000001','a1400000-0000-4000-8000-000000000101','weight-proof-principal-one','Synthetic Weight Principal One','active'),
('a1400000-0000-4000-8000-000000000202','a1400000-0000-4000-8000-000000000002','a1400000-0000-4000-8000-000000000102','weight-proof-principal-two','Synthetic Weight Principal Two','active');

insert into atlas.personal_atlas_access_grants(id,principal_id,grant_kind,state,basis) values
('a1400000-0000-4000-8000-000000000301','a1400000-0000-4000-8000-000000000201','test_fixture','active','{"localFixture":true}'),
('a1400000-0000-4000-8000-000000000302','a1400000-0000-4000-8000-000000000202','test_fixture','active','{"localFixture":true}');

insert into atlas.evidence_records(
id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,
evidence_kind,source_kind,source_key,value,provenance)
values
('a1400000-0000-4000-8000-000000000401','person','a1400000-0000-4000-8000-000000000001','health','person_body','body','first_party_testimony','personal_notebook_daily_log','weight-one-first','{"sourceText":"I weighed 172 pounds this morning."}','{"localFixture":true}'),
('a1400000-0000-4000-8000-000000000402','person','a1400000-0000-4000-8000-000000000001','health','person_body','body','first_party_testimony','personal_notebook_daily_log','weight-one-before','{"sourceText":"I weighed 169 pounds today."}','{"localFixture":true}'),
('a1400000-0000-4000-8000-000000000403','person','a1400000-0000-4000-8000-000000000002','health','person_body','body','first_party_testimony','personal_notebook_daily_log','weight-two','{"sourceText":"I weighed 80 kg today."}','{"localFixture":true}');

insert into atlas.personal_reality_captures(
id,principal_id,owner_user_id,source_action_id,testimony,evidence_id,
capture_state,source_surface,capture_context,metadata,captured_at)
values
('a1400000-0000-4000-8000-000000000501','a1400000-0000-4000-8000-000000000201','a1400000-0000-4000-8000-000000000001','weight-proof-first','I weighed 172 pounds this morning.','a1400000-0000-4000-8000-000000000401','captured','personal_notebook_daily_log',jsonb_build_object('notebookDate',(now() at time zone 'UTC')::date::text),'{"notebookEntryKind":"raw_note"}',now()-interval '4 hours'),
('a1400000-0000-4000-8000-000000000502','a1400000-0000-4000-8000-000000000201','a1400000-0000-4000-8000-000000000001','weight-proof-before','I weighed 169 pounds today.','a1400000-0000-4000-8000-000000000402','captured','personal_notebook_daily_log',jsonb_build_object('notebookDate',(now() at time zone 'UTC')::date::text),'{"notebookEntryKind":"raw_note"}',now()-interval '8 hours'),
('a1400000-0000-4000-8000-000000000503','a1400000-0000-4000-8000-000000000202','a1400000-0000-4000-8000-000000000002','weight-proof-other','I weighed 80 kg today.','a1400000-0000-4000-8000-000000000403','captured','personal_notebook_daily_log',jsonb_build_object('notebookDate',(now() at time zone 'UTC')::date::text),'{"notebookEntryKind":"raw_note"}',now()-interval '3 hours');

insert into atlas.task_entries(id,owner_user_id,principal_id,sentence,due_date,status,source_action_id,completed_at) values
('a1400000-0000-4000-8000-000000000601','a1400000-0000-4000-8000-000000000001','a1400000-0000-4000-8000-000000000201','First Person finished a task',(now() at time zone 'UTC')::date,'done','period-one-done',now()-interval '2 hours'),
('a1400000-0000-4000-8000-000000000602','a1400000-0000-4000-8000-000000000002','a1400000-0000-4000-8000-000000000202','Second Person task',(now() at time zone 'UTC')::date,'done','period-two-done',now()-interval '1 hour'),
('a1400000-0000-4000-8000-000000000603','a1400000-0000-4000-8000-000000000001','a1400000-0000-4000-8000-000000000201','Not finished',(now() at time zone 'UTC')::date,'open','period-one-open',null);
