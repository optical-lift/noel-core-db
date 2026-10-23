-- Synthetic Person observations; the real noel-core database is not contacted.
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222');
insert into atlas.personal_reality_captures
 (id,owner_user_id,principal_id,evidence_id,source_surface,metadata,testimony,capture_context,captured_at)
values
 ('00000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'e0000000-0000-4000-8000-000000000001',
  'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}',
  'I weighed 172 pounds this morning.',
  jsonb_build_object('notebookDate',current_date::text),now()-interval '4 hours'),
 ('00000000-0000-4000-8000-000000000002',
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'e0000000-0000-4000-8000-000000000002',
  'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}',
  'I weighed 169 pounds today.',
  jsonb_build_object('notebookDate',current_date::text),now()-interval '8 hours'),
 ('00000000-0000-4000-8000-000000000003',
  '22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'e0000000-0000-4000-8000-000000000003',
  'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}',
  'I weighed 80 kg today.',
  jsonb_build_object('notebookDate',current_date::text),now()-interval '3 hours');
