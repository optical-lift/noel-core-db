-- Data-only disposable fixture for SK101 management validation.
INSERT INTO atlas.agent_command_definitions
(command_key,command_version,label,scope_kind,execution_class,confirmation_requirement,handler_key,status,input_contract,target_contract)
VALUES
('teaching.course.management.read',1,'Read private Course management state','personal','read','none','teaching.course.management.read.v1','active','{}'::jsonb,'{"kind":"teaching_course"}'::jsonb),
('teaching.course.management.write',1,'Write private Course management state','personal','commit','none','teaching.course.management.write.v1','active','{}'::jsonb,'{"kind":"teaching_course"}'::jsonb)
ON CONFLICT (command_key,command_version) DO NOTHING;
