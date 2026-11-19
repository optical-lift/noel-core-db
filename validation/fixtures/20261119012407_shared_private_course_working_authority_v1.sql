-- Disposable clone prerequisite only; no production execution.
-- Exact registration from released 20261118205907_shared_titus_delegated_course_authoring_v1.sql.
-- Schema-only snapshots omit command registry rows. No principals, credentials or user data.
INSERT INTO atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,
 confirmation_requirement,handler_key,status,input_contract,target_contract)
 VALUES('teaching.course.authoring.apply_proposal',1,'Apply reviewed Course draft proposal','personal','commit',
 'principal_explicit','teaching.course.authoring.apply_proposal.v1','active',
 '{"contractVersion":"titus_course_authoring_proposal_v1","maxItems":12}'::jsonb,'{"kind":"teaching_course"}'::jsonb);
