-- Atlas Event notebook REST RPC boundary, source-only candidate.
-- The browser uses Supabase's exposed PUBLIC schema; Atlas source functions
-- are private-schema, verified independently. These eleven narrow, invoker
-- delegates expose no table/view, never mint source identity/actor/authority,
-- never assume Ledger Seat alone grants operation power and never copy Work.
-- All underlying source guard functions are retained byte-for-byte.
BEGIN;
-- ledger_occurrence_shared_index_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.ledger_occurrence_shared_index_self_api_v1(p_ledger_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.ledger_occurrence_shared_index_self_api_v1(p_ledger_id) $wrapper$;

REVOKE ALL ON FUNCTION public.ledger_occurrence_shared_index_self_api_v1(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ledger_occurrence_shared_index_self_api_v1(uuid) TO authenticated;

-- ledger_occurrence_shared_work_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.ledger_occurrence_shared_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.ledger_occurrence_shared_work_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id) $wrapper$;

REVOKE ALL ON FUNCTION public.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid) TO authenticated;

-- ledger_occurrence_work_extension_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.ledger_occurrence_work_extension_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.ledger_occurrence_work_extension_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id) $wrapper$;

REVOKE ALL ON FUNCTION public.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid) TO authenticated;

-- event_existing_work_choices_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.event_existing_work_choices_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_query text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.event_existing_work_choices_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_query) $wrapper$;

REVOKE ALL ON FUNCTION public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text) TO authenticated;

-- ledger_event_attention_people_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.ledger_event_attention_people_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.ledger_event_attention_people_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id) $wrapper$;

REVOKE ALL ON FUNCTION public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid) TO authenticated;

-- link_existing_ledger_event_work_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.link_existing_ledger_event_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_source_action_id text)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.link_existing_ledger_event_work_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_work_item_id, p_source_action_id) $wrapper$;

REVOKE ALL ON FUNCTION public.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text) TO authenticated;

-- direct_ledger_event_work_attention_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.direct_ledger_event_work_attention_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_person_entity_id uuid, p_direct boolean, p_source_action_id text)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.direct_ledger_event_work_attention_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_work_item_id, p_person_entity_id, p_direct, p_source_action_id) $wrapper$;

REVOKE ALL ON FUNCTION public.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text) TO authenticated;

-- change_ledger_event_ordinary_work_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.change_ledger_event_ordinary_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_action text, p_source_action_id text, p_explanation text)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.change_ledger_event_ordinary_work_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_work_item_id, p_action, p_source_action_id, p_explanation) $wrapper$;

REVOKE ALL ON FUNCTION public.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text) TO authenticated;

-- my_ledger_event_work_attention_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.my_ledger_event_work_attention_self_api_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.my_ledger_event_work_attention_self_api_v1() $wrapper$;

REVOKE ALL ON FUNCTION public.my_ledger_event_work_attention_self_api_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_ledger_event_work_attention_self_api_v1() TO authenticated;

-- create_ledger_occurrence_shared_work_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.create_ledger_occurrence_shared_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_sentence text, p_source_action_id text)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.create_ledger_occurrence_shared_work_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_sentence, p_source_action_id) $wrapper$;

REVOKE ALL ON FUNCTION public.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text) TO authenticated;

-- mark_ledger_occurrence_shared_work_done_self_api_v1: no public SECURITY DEFINER, identity or policy shortcut.
CREATE OR REPLACE FUNCTION public.mark_ledger_occurrence_shared_work_done_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_source_action_id text)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $wrapper$ SELECT atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(p_organization_id, p_ledger_id, p_occurrence_id, p_work_item_id, p_source_action_id) $wrapper$;

REVOKE ALL ON FUNCTION public.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text) TO authenticated;
COMMIT;
