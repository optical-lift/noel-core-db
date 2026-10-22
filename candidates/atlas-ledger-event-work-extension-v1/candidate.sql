-- SOURCE-ONLY CANDIDATE. Dependency: the reviewed ordinary shared Event Work
-- migration 20261022013255. Do not run this file against production.
BEGIN;

-- Separate append-only Event-specific decisions from the Work result/acceptance
-- graph. "Blocked" is NOT an unsupported fifth atlas.work_items.work_state.
CREATE TABLE IF NOT EXISTS atlas.ledger_occurrence_work_actions_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
  ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
  occurrence_id uuid NOT NULL REFERENCES local_intel.occurrences(id),
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id),
  action_kind text NOT NULL CHECK
    (action_kind IN ('linked','blocked','reopened','removed','attention_directed','attention_cleared')),
  source_action_id text NOT NULL CHECK (length(btrim(source_action_id)) BETWEEN 1 AND 128),
  actor_person_id uuid NOT NULL REFERENCES reality.entities(id),
  target_person_id uuid REFERENCES reality.entities(id),
  explanation text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ledger_id,occurrence_id,source_action_id),
  CHECK (
    (action_kind IN ('attention_directed','attention_cleared') AND target_person_id IS NOT NULL)
    OR (action_kind NOT IN ('attention_directed','attention_cleared') AND target_person_id IS NULL)
  )
);
CREATE INDEX IF NOT EXISTS ledger_occurrence_work_actions_latest_v1
 ON atlas.ledger_occurrence_work_actions_v1
 (ledger_id,occurrence_id,work_item_id,occurred_at DESC,id DESC);

-- Attention has its own relational identity. It is never atlas.work_allocations
-- and never a Worker Day obligation or acceptance offer.
CREATE TABLE IF NOT EXISTS atlas.ledger_occurrence_work_attention_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
  ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
  occurrence_id uuid NOT NULL REFERENCES local_intel.occurrences(id),
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id),
  person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
  attention_state text NOT NULL DEFAULT 'active'
    CHECK (attention_state IN ('active','cleared')),
  directed_by_person_id uuid NOT NULL REFERENCES reality.entities(id),
  directed_at timestamptz NOT NULL DEFAULT now(),
  cleared_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ledger_id,occurrence_id,work_item_id,person_entity_id),
  CHECK ((attention_state='active' AND cleared_at IS NULL) OR
         (attention_state='cleared' AND cleared_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ledger_occurrence_person_attention_v1
 ON atlas.ledger_occurrence_work_attention_v1(person_entity_id,attention_state,ledger_id);

ALTER TABLE atlas.ledger_occurrence_work_actions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.ledger_occurrence_work_attention_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.ledger_occurrence_work_actions_v1,
  atlas.ledger_occurrence_work_attention_v1 FROM PUBLIC,anon,authenticated;

-- An internal shared assertion used by ALL three features. It does not
-- transfer responsibility, rewrite the Work source or infer permission from
-- an event title, date, browser parameters or stale Employee status.
CREATE OR REPLACE FUNCTION atlas.assert_ledger_occurrence_work_link_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_work_item_id uuid
) RETURNS atlas.work_items
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_work atlas.work_items%rowtype;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
   p_organization_id,p_ledger_id,p_occurrence_id);
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id;
 IF v_work.id IS NULL OR NOT EXISTS (
  SELECT 1 FROM atlas.company_work_native_ledger_relevance r
  WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.work_item_id=p_work_item_id AND r.attribution_state='active'
 ) OR NOT EXISTS (
  SELECT 1 FROM atlas.work_item_context_links c
  WHERE c.organization_id=p_organization_id AND c.work_item_id=p_work_item_id
   AND c.subject_domain='temporal' AND c.subject_kind='occurrence'
   AND c.subject_id=p_occurrence_id
 ) THEN
  RAISE EXCEPTION 'Exact active Ledger Work/Event relationship required'
    USING ERRCODE='42501';
 END IF;
 RETURN v_work;
END
$f$;

-- Feature 1: find *existing* source Work already relevant to this Ledger,
-- and attach it to the Event without cloning Work, allocations or results.
CREATE OR REPLACE FUNCTION atlas.event_existing_work_choices_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_query text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_items jsonb;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
   p_organization_id,p_ledger_id,p_occurrence_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'workItemId',x.id,'title',x.title,'workState',x.work_state)
   ORDER BY x.title,x.id),'[]'::jsonb) INTO v_items
 FROM (
   SELECT w.id,w.title,w.work_state
   FROM atlas.work_items w
   JOIN atlas.company_work_native_ledger_relevance r
    ON r.work_item_id=w.id AND r.organization_id=w.organization_id
      AND r.ledger_id=p_ledger_id AND r.attribution_state='active'
   WHERE w.organization_id=p_organization_id AND w.work_state='open'
     AND (nullif(btrim(coalesce(p_query,'')),'') IS NULL
       OR w.title ILIKE '%' || replace(replace(btrim(p_query),'%','\%'),'_','\_') || '%' ESCAPE '\')
     AND NOT EXISTS (SELECT 1 FROM atlas.work_item_context_links c
       WHERE c.work_item_id=w.id AND c.subject_domain='temporal'
       AND c.subject_kind='occurrence' AND c.subject_id=p_occurrence_id)
   ORDER BY w.title,w.id LIMIT 40
 ) x;
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
   'occurrenceId',p_occurrence_id,'choices',v_items,
   'sourceContract','existing_canonical_ledger_work');
END
$f$;

CREATE OR REPLACE FUNCTION atlas.link_existing_ledger_event_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
 p_work_item_id uuid,p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_work atlas.work_items%rowtype;v_action text;
 v_record atlas.ledger_occurrence_work_actions_v1%rowtype;v_link uuid;
BEGIN
 v_action:=nullif(btrim(coalesce(p_source_action_id,'')),'');
 IF v_action IS NULL OR length(v_action)>128 THEN
  RAISE EXCEPTION 'Stable source action required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.event.work-link:'||p_ledger_id||':'||p_occurrence_id||':'||p_work_item_id,0));
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' OR NOT EXISTS(
  SELECT 1 FROM atlas.company_work_native_ledger_relevance r
  WHERE r.ledger_id=p_ledger_id AND r.organization_id=p_organization_id
    AND r.work_item_id=p_work_item_id AND r.attribution_state='active') THEN
  RAISE EXCEPTION 'Existing active Work must already belong to this Ledger'
    USING ERRCODE='42501'; END IF;
 SELECT * INTO v_record FROM atlas.ledger_occurrence_work_actions_v1 a
 WHERE a.ledger_id=p_ledger_id AND a.occurrence_id=p_occurrence_id
  AND a.source_action_id=v_action;
 IF v_record.id IS NOT NULL THEN
   IF v_record.work_item_id<>p_work_item_id OR v_record.action_kind<>'linked'
      OR v_record.actor_person_id<>v_actor THEN
     RAISE EXCEPTION 'Action ID reused for different Work' USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'workItemId',p_work_item_id,
      'contextLinkId',(v_record.metadata->>'contextLinkId')::uuid,
      'idempotent',true,'workCustodyChanged',false);
 END IF;
 v_link:=atlas.attach_work_item_context_internal_v1(
  p_work_item_id,'temporal','occurrence',p_occurrence_id,'for',null,
  jsonb_build_object('source','link_existing_ledger_event_work_self_api_v1',
    'ledgerId',p_ledger_id,'actorPersonId',v_actor),
  '{"linkedWithoutCopy":true}'::jsonb);
 INSERT INTO atlas.ledger_occurrence_work_actions_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,action_kind,
  source_action_id,actor_person_id,metadata)
 VALUES (p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
  'linked',v_action,v_actor,jsonb_build_object('contextLinkId',v_link));
 RETURN jsonb_build_object('ok',true,'workItemId',p_work_item_id,
   'contextLinkId',v_link,'idempotent',false,
   'workCustodyChanged',false,'personalCopyCreated',false);
END
$f$;

-- Feature 2: universal ordinary action history. Block keeps canonical
-- Work open; Reopen unblocks OR reopens completed work only if it was born
-- under the ordinary Event result contract. Remove hides a pre-existing
-- Work link but preserves its independent Ledger truth. For a newly created
-- outstanding Event-only Work item, remove safely cancels Work when its
-- dependency snapshot is empty (otherwise it DENIES instead of hiding debt).
CREATE OR REPLACE FUNCTION atlas.change_ledger_event_ordinary_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_work_item_id uuid,
 p_action text,p_source_action_id text,p_explanation text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_work atlas.work_items%rowtype;v_a text;
 v_key text;v_previous text;v_record atlas.ledger_occurrence_work_actions_v1%rowtype;
 v_impact jsonb;v_created_here boolean;v_remove_underlying boolean:=false;
BEGIN
 v_a:=lower(btrim(coalesce(p_action,'')));
 v_key:=nullif(btrim(coalesce(p_source_action_id,'')),'');
 IF v_a NOT IN ('blocked','reopened','removed') OR v_key IS NULL
  OR length(v_key)>128 OR length(coalesce(p_explanation,''))>1200 THEN
  RAISE EXCEPTION 'Recognized action and stable action ID required' USING ERRCODE='22023';
 END IF;
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.event.work-change:'||p_work_item_id,0));
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_work.id IS NULL THEN RAISE EXCEPTION 'Work not found' USING ERRCODE='P0002'; END IF;
 PERFORM atlas.assert_ledger_occurrence_work_link_v1(
  p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id);
 SELECT * INTO v_record FROM atlas.ledger_occurrence_work_actions_v1 e
 WHERE e.ledger_id=p_ledger_id AND e.occurrence_id=p_occurrence_id
   AND e.source_action_id=v_key;
 IF v_record.id IS NOT NULL THEN
  IF v_record.actor_person_id<>v_actor OR v_record.action_kind<>v_a
      OR v_record.work_item_id<>p_work_item_id THEN
    RAISE EXCEPTION 'Action ID collision' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'idempotent',true,
   'workItemId',p_work_item_id,'action',v_a,'actionId',v_record.id);
 END IF;
 SELECT e.action_kind INTO v_previous
 FROM atlas.ledger_occurrence_work_actions_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
  AND e.occurrence_id=p_occurrence_id AND e.work_item_id=p_work_item_id
  AND e.action_kind IN ('blocked','reopened','removed')
 ORDER BY e.occurred_at DESC,e.id DESC LIMIT 1;
 IF v_previous='removed' THEN
  RAISE EXCEPTION 'Removed Event association cannot be operated without explicit restoration'
   USING ERRCODE='23514'; END IF;
 v_created_here:=v_work.source_object_type='ledger_occurrence_shared_work'
  AND v_work.source_object_id=p_occurrence_id
  AND v_work.result_contract_key='ledger_occurrence_shared_confirmation_v1'
  AND v_work.metadata->>'ledgerId'=p_ledger_id::text;
 IF v_a='blocked' THEN
   IF v_work.work_state<>'open' OR v_previous='blocked' THEN
    RAISE EXCEPTION 'Only active outstanding Work may become blocked' USING ERRCODE='23514';
   END IF;
 ELSIF v_a='reopened' THEN
   IF v_previous='blocked' AND v_work.work_state='open' THEN NULL;
   ELSIF v_work.work_state='completed' AND v_created_here THEN
     UPDATE atlas.work_items SET work_state='open',completed_at=NULL,updated_at=now()
       WHERE id=v_work.id AND work_state='completed';
     IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent Work change' USING ERRCODE='40001'; END IF;
   ELSE
     RAISE EXCEPTION 'Only blocked Work or an ordinary completed Event checklist may reopen'
       USING ERRCODE='23514';
   END IF;
 ELSIF v_a='removed' THEN
   -- Cancellation is only appropriate when this was an Event-created item
   -- with NO other subject or Ledger using it. Otherwise withdraw the
   -- local Event's visibility and preserve the single institutional Work.
   v_remove_underlying:=v_created_here AND v_work.work_state='open'
    AND NOT EXISTS (SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.work_item_id=v_work.id
        AND NOT (c.subject_domain='temporal' AND c.subject_kind='occurrence'
          AND c.subject_id=p_occurrence_id))
    AND NOT EXISTS (SELECT 1 FROM atlas.company_work_native_ledger_relevance r
      WHERE r.work_item_id=v_work.id AND r.attribution_state='active'
        AND r.ledger_id<>p_ledger_id);
   IF v_remove_underlying THEN
     v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
     IF jsonb_array_length(v_impact->'requirements')<>0
       OR jsonb_array_length(v_impact->'relations')<>0
       OR jsonb_array_length(v_impact->'pendingOfferIds')<>0
       OR jsonb_array_length(v_impact->'projectionIds')<>0
       OR jsonb_array_length(v_impact->'executionResultIds')<>0
       OR jsonb_array_length(v_impact->'activeTimeContractIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAllocationIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activePlanIds')<>0
     THEN RAISE EXCEPTION 'This task has dependencies; resolve them before removal'
      USING ERRCODE='23514'; END IF;
     UPDATE atlas.work_items
        SET work_state='cancelled',cancelled_at=now(),updated_at=now()
      WHERE id=v_work.id AND work_state='open';
   END IF;
 END IF;
 INSERT INTO atlas.ledger_occurrence_work_actions_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,action_kind,
  source_action_id,actor_person_id,explanation,metadata)
 VALUES (p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
   v_a,v_key,v_actor,nullif(btrim(coalesce(p_explanation,'')),''),
   jsonb_build_object('originalSourceWorkPreserved',not v_created_here,
      'physicalPerformerNotInferred',true));
 RETURN jsonb_build_object('ok',true,'idempotent',false,'workItemId',v_work.id,
  'action',v_a,'actorPersonId',v_actor,'underlyingWorkCancelled',
    v_a='removed' AND v_remove_underlying);
END
$f$;

-- Feature 3: Personal attention addresses source Work. A target Person may
-- have an active native Ledger seat WITHOUT YET having Atlas Auth/Personal
-- Atlas; the pointer will become visible only when they claim their notebook.
CREATE OR REPLACE FUNCTION atlas.direct_ledger_event_work_attention_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_work_item_id uuid,
 p_person_entity_id uuid,p_direct boolean,p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_work atlas.work_items%rowtype;v_key text;
 v_kind text;v_existing atlas.ledger_occurrence_work_actions_v1%rowtype;
BEGIN
 v_key:=nullif(btrim(coalesce(p_source_action_id,'')),'');
 IF v_key IS NULL OR length(v_key)>128 OR p_person_entity_id IS NULL THEN
  RAISE EXCEPTION 'Exact target Person and source action required' USING ERRCODE='22023';END IF;
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 v_work:=atlas.assert_ledger_occurrence_work_link_v1(
  p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id);
 IF v_work.work_state<>'open' OR EXISTS (
   SELECT 1 FROM atlas.ledger_occurrence_work_actions_v1 removed
   WHERE removed.ledger_id=p_ledger_id AND removed.occurrence_id=p_occurrence_id
      AND removed.work_item_id=p_work_item_id AND removed.action_kind='removed'
 ) OR NOT EXISTS (
  SELECT 1 FROM ledger.seats s JOIN reality.entities e ON e.id=s.person_entity_id
  WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=p_person_entity_id
    AND s.seat_state='active' AND s.ended_at IS NULL AND e.entity_kind='person'
    AND e.identity_state='canonical') THEN
  RAISE EXCEPTION 'Attention requires an active connected Person and valid Work'
    USING ERRCODE='42501';END IF;
 v_kind:=CASE WHEN p_direct THEN 'attention_directed' ELSE 'attention_cleared' END;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.event.attention:'||p_ledger_id||':'||p_occurrence_id||':'||p_work_item_id||':'||p_person_entity_id,0));
 SELECT * INTO v_existing FROM atlas.ledger_occurrence_work_actions_v1
 WHERE ledger_id=p_ledger_id AND occurrence_id=p_occurrence_id
  AND source_action_id=v_key;
 IF v_existing.id IS NOT NULL THEN
  IF v_existing.actor_person_id<>v_actor
    OR v_existing.action_kind<>v_kind OR v_existing.target_person_id<>p_person_entity_id
    OR v_existing.work_item_id<>p_work_item_id THEN
   RAISE EXCEPTION 'Attention source action collision' USING ERRCODE='23505';END IF;
  RETURN jsonb_build_object('ok',true,'idempotent',true,
     'attentionState',CASE WHEN p_direct THEN 'active' ELSE 'cleared' END);
 END IF;
 INSERT INTO atlas.ledger_occurrence_work_attention_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,person_entity_id,
  attention_state,directed_by_person_id,cleared_at)
 VALUES (p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
  p_person_entity_id,CASE WHEN p_direct THEN 'active' ELSE 'cleared' END,
  v_actor,CASE WHEN p_direct THEN NULL ELSE now() END)
 ON CONFLICT (ledger_id,occurrence_id,work_item_id,person_entity_id)
 DO UPDATE SET attention_state=excluded.attention_state,
   directed_by_person_id=excluded.directed_by_person_id,
   directed_at=now(),cleared_at=excluded.cleared_at,updated_at=now();
 INSERT INTO atlas.ledger_occurrence_work_actions_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,action_kind,
  source_action_id,actor_person_id,target_person_id,metadata)
 VALUES (p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
  v_kind,v_key,v_actor,p_person_entity_id,
  '{"isPersonalAttentionNotAssignment":true,"noWorkerAcceptanceRequired":true}'::jsonb);
 RETURN jsonb_build_object('ok',true,'idempotent',false,
  'workItemId',p_work_item_id,'personEntityId',p_person_entity_id,
  'attentionState',CASE WHEN p_direct THEN 'active' ELSE 'cleared' END,
  'workOwnershipTransferred',false,'exclusiveCompletionAuthority',false);
END
$f$;

-- Minimal personally authenticated projection. No query can pass the target
-- Person ID: it comes from the current verified native Personal Atlas.
CREATE OR REPLACE FUNCTION atlas.my_ledger_event_work_attention_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_person uuid;v_access jsonb;v_rows jsonb;
BEGIN
 v_access:=atlas.reality_access_self_api_v1();
 IF v_access->>'state' IS DISTINCT FROM 'ready' OR
    v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'An active personal Atlas session is required' USING ERRCODE='42501';END IF;
 v_person:=atlas.current_person_id_v1();
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'ledgerId',z.ledger_id,'occurrenceId',z.occurrence_id,
  'workItemId',z.work_item_id,'title',z.title,'workState',z.work_state,
  'eventTitle',z.event_title,'startsAt',z.start_at)
  ORDER BY z.start_at,z.title,z.work_item_id),'[]'::jsonb) INTO v_rows
 FROM (
  SELECT a.ledger_id,a.occurrence_id,a.work_item_id,w.title,w.work_state,
    o.title event_title,o.start_at
  FROM atlas.ledger_occurrence_work_attention_v1 a
  JOIN atlas.work_items w ON w.id=a.work_item_id AND w.organization_id=a.organization_id
  JOIN local_intel.occurrences o ON o.id=a.occurrence_id
  JOIN ledger.occurrence_calendar_bindings cb
   ON cb.ledger_id=a.ledger_id AND cb.occurrence_id=a.occurrence_id
      AND cb.binding_state='active'
  WHERE a.person_entity_id=v_person AND a.attention_state='active'
    AND w.work_state='open'
    AND EXISTS (SELECT 1 FROM atlas.ledger_organization_participations lop
      WHERE lop.ledger_id=a.ledger_id AND lop.organization_id=a.organization_id
        AND lop.status='active' AND lop.ended_at IS NULL)
    AND EXISTS (SELECT 1 FROM atlas.organization_occurrence_bindings ob
      WHERE ob.organization_id=a.organization_id AND ob.occurrence_id=a.occurrence_id
        AND ob.binding_state='active')
    AND atlas.person_has_native_ledger_connection_v1(
     a.organization_id,a.ledger_id,v_person)
    AND NOT EXISTS (SELECT 1 FROM atlas.ledger_occurrence_work_actions_v1 e
      WHERE e.ledger_id=a.ledger_id AND e.occurrence_id=a.occurrence_id
        AND e.work_item_id=a.work_item_id AND e.action_kind='removed')
  ORDER BY o.start_at,w.title,w.id LIMIT 150
 ) z;
 RETURN jsonb_build_object('ok',true,'contractVersion','my_ledger_event_work_attention_v1',
  'personEntityId',v_person,'items',v_rows,'sourceOwnedNotPersonalCopies',true);
END
$f$;

-- List exact connected people for event attention picker, never general
-- Organization identity search or unrelated institution members.
CREATE OR REPLACE FUNCTION atlas.ledger_event_attention_people_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_people jsonb;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'personEntityId',x.id,'displayName',x.display_name)
   ORDER BY x.display_name,x.id),'[]'::jsonb) INTO v_people
 FROM (SELECT DISTINCT e.id,e.display_name
   FROM ledger.seats s JOIN reality.entities e ON e.id=s.person_entity_id
   WHERE s.ledger_id=p_ledger_id AND s.seat_state='active' AND s.ended_at IS NULL
     AND e.entity_kind='person' AND e.identity_state='canonical'
 ) x;
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
   'occurrenceId',p_occurrence_id,'people',v_people);
END
$f$;

-- A direct call to the original Mark Done RPC must honor the new shared
-- Blocked state too. Do not silently turn a blocked item into completed by
-- bypassing the notebook's narrower UI.
CREATE OR REPLACE FUNCTION atlas.guard_blocked_ledger_occurrence_completion_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_work atlas.work_items%rowtype;v_latest text;
BEGIN
 IF new.result_kind<>'completed' OR
    new.result_contract_key<>'ledger_occurrence_shared_confirmation_v1' THEN
   RETURN new;
 END IF;
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=new.work_item_id AND organization_id=new.organization_id;
 IF v_work.source_object_type<>'ledger_occurrence_shared_work' THEN
   RETURN new;
 END IF;
 SELECT action_kind INTO v_latest
 FROM atlas.ledger_occurrence_work_actions_v1 e
 WHERE e.work_item_id=new.work_item_id
   AND e.occurrence_id=v_work.source_object_id
   AND e.ledger_id=(v_work.metadata->>'ledgerId')::uuid
   AND e.action_kind IN ('blocked','reopened','removed')
 ORDER BY e.occurred_at DESC,e.id DESC LIMIT 1;
 IF v_latest IN ('blocked','removed') THEN
   RAISE EXCEPTION 'Blocked or removed shared Event Work cannot be checked off'
     USING ERRCODE='23514';
 END IF;
 RETURN new;
END
$f$;
CREATE TRIGGER guard_blocked_ledger_occurrence_completion_v1
 BEFORE INSERT ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_blocked_ledger_occurrence_completion_v1();

-- Event-specific projection, with no second Work storage.
-- Histories are source events; base Work remains canonical.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_work_extension_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
DECLARE v_actor uuid;v_items jsonb;v_history jsonb;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',z.id,'title',z.title,'state',z.display_state,
  'workState',z.work_state,'canMarkDone',z.can_mark_done,
  'directedTo',z.directed_to,'sourceOwned',true,
  'createdInsideEvent',z.created_inside_event)
  ORDER BY z.created_at,z.id),'[]'::jsonb) INTO v_items
 FROM (
  SELECT w.id,w.title,w.work_state,w.created_at,
   CASE WHEN w.work_state='open' AND action.action_kind='blocked'
     THEN 'blocked' ELSE w.work_state END display_state,
   (w.source_object_type='ledger_occurrence_shared_work'
      AND w.source_object_id=p_occurrence_id
      AND w.metadata->>'ledgerId'=p_ledger_id::text) created_inside_event,
   (w.work_state='open' AND coalesce(action.action_kind,'')<>'blocked'
     AND w.source_object_type='ledger_occurrence_shared_work'
     AND w.source_object_id=p_occurrence_id
     AND w.result_contract_key='ledger_occurrence_shared_confirmation_v1') can_mark_done,
   (SELECT coalesce(jsonb_agg(jsonb_build_object(
     'personEntityId',att.person_entity_id,'displayName',e.display_name)
     ORDER BY e.display_name),'[]'::jsonb)
    FROM atlas.ledger_occurrence_work_attention_v1 att
    JOIN reality.entities e ON e.id=att.person_entity_id
    WHERE att.work_item_id=w.id AND att.ledger_id=p_ledger_id
     AND att.occurrence_id=p_occurrence_id AND att.attention_state='active') directed_to
  FROM atlas.work_item_context_links ctx
  JOIN atlas.work_items w ON w.id=ctx.work_item_id
   AND w.organization_id=p_organization_id
  JOIN atlas.company_work_native_ledger_relevance rel
   ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
     AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
  LEFT JOIN LATERAL (
    SELECT e.action_kind FROM atlas.ledger_occurrence_work_actions_v1 e
    WHERE e.work_item_id=w.id AND e.ledger_id=p_ledger_id
      AND e.occurrence_id=p_occurrence_id
      AND e.action_kind IN ('blocked','reopened','removed')
    ORDER BY e.occurred_at DESC,e.id DESC LIMIT 1
  ) action ON true
  WHERE ctx.organization_id=p_organization_id
    AND ctx.subject_domain='temporal' AND ctx.subject_kind='occurrence'
    AND ctx.subject_id=p_occurrence_id
    AND w.work_state IN ('open','completed')
    AND coalesce(action.action_kind,'')<>'removed'
 ) z;
 -- History combines native Work creation and accepted completion evidence
 -- with append-only Event actions. A completed task is not falsely labelled
 -- as performed by the checker; actor/performer remains separate.
 WITH historical_events AS (
  SELECT a.work_item_id,a.action_kind,a.actor_person_id,
    a.target_person_id,a.occurred_at,a.explanation,a.id
  FROM atlas.ledger_occurrence_work_actions_v1 a
  WHERE a.organization_id=p_organization_id AND a.ledger_id=p_ledger_id
    AND a.occurrence_id=p_occurrence_id
  UNION ALL
  SELECT w.id,'created'::text,
    NULLIF(w.metadata->>'createdByPersonId','')::uuid,NULL::uuid,
    w.created_at,NULL::text,w.id
  FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='ledger_occurrence_shared_work'
    AND w.source_object_id=p_occurrence_id
    AND w.metadata->>'ledgerId'=p_ledger_id::text
  UNION ALL
  SELECT r.work_item_id,'marked_done'::text,
    NULLIF(r.metadata->>'actorPersonId','')::uuid,NULL::uuid,
    r.reported_at,NULL::text,r.id
  FROM atlas.work_execution_results r
  JOIN atlas.work_result_acceptances accepted
    ON accepted.execution_result_id=r.id AND accepted.decision='accepted'
  JOIN atlas.work_items w ON w.id=r.work_item_id
  WHERE r.organization_id=p_organization_id
    AND r.result_contract_key='ledger_occurrence_shared_confirmation_v1'
    AND r.result_kind='completed'
    AND w.source_object_type='ledger_occurrence_shared_work'
    AND w.source_object_id=p_occurrence_id
    AND w.metadata->>'ledgerId'=p_ledger_id::text
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',e.work_item_id,'actionKind',e.action_kind,
  'actorPersonId',e.actor_person_id,'actorName',person.display_name,
  'targetPersonId',e.target_person_id,'at',e.occurred_at,
  'explanation',e.explanation,'physicalPerformerNotAsserted',true)
  ORDER BY e.occurred_at,e.id),'[]'::jsonb) INTO v_history
 FROM historical_events e
 LEFT JOIN reality.entities person ON person.id=e.actor_person_id;
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
  'organizationId',p_organization_id,'occurrenceId',p_occurrence_id,
  'work',v_items,'history',v_history,
  'custody','ledger','attentionDoesNotTransferControl',true);
END
$f$;

REVOKE ALL ON FUNCTION atlas.assert_ledger_occurrence_work_link_v1(uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated;
-- Protect all self endpoints against PUBLIC's default Postgres EXECUTE.
REVOKE ALL ON FUNCTION atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.my_ledger_event_work_attention_self_api_v1()
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.my_ledger_event_work_attention_self_api_v1()
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid)
 TO authenticated;
COMMIT;
