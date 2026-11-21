-- UNI-OPS-01 U2F — HELD SOURCE ONLY; NOT A VERSIONED MIGRATION.
-- Draft-only UNIVERSAL delegated command, no new table or Work engine.
-- No credentials, principal, authorization, campaign, candidate, original,
-- queue, schedule, trigger, grant, API or executable handler are created.
-- Intended for a separately owner-approved disposable current-schema clone.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '20s';

DO $u2f_first_original_preflight$
DECLARE
  v_eval oid;
BEGIN
  IF to_regclass('atlas.agent_command_definitions') IS NULL
     OR to_regclass('atlas.delegated_agent_carriers') IS NULL
     OR to_regclass('atlas.delegated_agent_authorizations') IS NULL
     OR to_regclass('atlas.delegated_agent_credentials') IS NULL
     OR to_regclass('atlas.agent_command_invocations') IS NULL
     OR to_regclass('atlas.work_items') IS NULL THEN
    RAISE EXCEPTION 'U2F existing canonical command or Work source absent; stop';
  END IF;
  v_eval:=to_regprocedure(
    'atlas.evaluate_delegated_agent_command_authority_v1(uuid,text,integer)'
  )::oid;
  IF v_eval IS NULL
     OR (SELECT md5(pg_catalog.pg_get_functiondef(p.oid))
         FROM pg_catalog.pg_proc p WHERE p.oid=v_eval)
       IS DISTINCT FROM '28bbb95ce3874a7dbf641387c22ac1fd' THEN
    RAISE EXCEPTION 'U2F delegated-source authority definition drift; stop';
  END IF;
  IF EXISTS(
    SELECT 1 FROM atlas.agent_command_definitions
    WHERE command_key='work.original.establish_one'
  ) THEN
    RAISE EXCEPTION 'U2F command identity already exists; review before any replacement';
  END IF;
END
$u2f_first_original_preflight$;

INSERT INTO atlas.agent_command_definitions (
  command_key,command_version,label,scope_kind,execution_class,
  confirmation_requirement,handler_key,status,
  input_contract,target_contract,metadata
) VALUES (
  'work.original.establish_one',1,
  'One accepted canonical original Work (issuer held)',
  'ledger','commit','principal_explicit',
  'u2f_held_no_executable_handler_v1','draft',
  pg_catalog.jsonb_build_object(
    'contractVersion','uni_ops_u2f_first_original_draft_v1',
    'requires',pg_catalog.jsonb_build_array(
      'current_approved_rulebook','one_source_verified_need',
      'one_independent_worker_acceptance','one_active_bounded_campaign',
      'current_source_eligible_service_day',
      'source_bound_real_recipient_and_capacity',
      'separate_registered_carrier_and_credential',
      'independent_current_governing_principal_authorization',
      'source_atomic_single_original_and_replay',
      'after_result_no_automatic_successor'
    )
  ),
  pg_catalog.jsonb_build_object(
    'kind','source_accepted_original_offer',
    'scope','original_work',
    'requiresExactSourceOffer',true,
    'noLegacyTaskOrQueueFallback',true
  ),
  pg_catalog.jsonb_build_object(
    'held',true,
    'sourceOnly',true,
    'executable',false,
    'autoNextWork',false,
    'maxOriginalsPerCampaign',1,
    'existingCanonicalWorkTable','atlas.work_items',
    'noSeparateFarmWorkEngine',true
  )
);

DO $u2f_first_original_postcondition$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM atlas.agent_command_definitions
    WHERE command_key='work.original.establish_one'
      AND command_version=1 AND status='draft'
      AND scope_kind='ledger'
      AND execution_class='commit'
      AND confirmation_requirement='principal_explicit'
      AND handler_key='u2f_held_no_executable_handler_v1'
      AND target_contract->>'kind'='source_accepted_original_offer'
      AND metadata->>'autoNextWork'='false'
      AND metadata->>'executable'='false'
  ) THEN
    RAISE EXCEPTION 'U2F candidate did not remain draft-only and inert';
  END IF;
  -- No carrier, delegation, token or executable command is created here.
  -- The installed authority evaluator explicitly denies draft commands.
  IF EXISTS (
    SELECT 1 FROM atlas.agent_command_definitions
    WHERE command_key='work.original.establish_one' AND status='active'
  ) THEN
    RAISE EXCEPTION 'U2F has incorrectly become executable';
  END IF;
END
$u2f_first_original_postcondition$;
COMMIT;
