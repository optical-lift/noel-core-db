-- HELD 6A, source-specific protected rhythm-clock signal guard.
-- Current live pg_get_functiondef MD5: 44878fb25c583320a0af033e4266d25b.
-- Requires the same existing U1A/U1B native governed helper from P3 file 03.
-- Unrelated sale commitment, harvest output, and seed shortfall signals remain
-- in the original source, NOT globally revoked or rewritten.
-- This source is NOT compiled, tested, migrated, merged or released.
BEGIN;
DO $source$
BEGIN
 IF (SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='signal_work_occurrence_v1') IS DISTINCT FROM '44878fb25c583320a0af033e4266d25b' OR pg_catalog.to_regprocedure('atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)') IS NULL THEN
  RAISE EXCEPTION 'Shared signal source drift or reviewed governed-source guard missing';
 END IF;
END;
$source$;
CREATE OR REPLACE FUNCTION atlas.signal_work_occurrence_v1(p_occurrence_id uuid, p_signal_key text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare o atlas.planned_work_occurrences%rowtype; v_release jsonb;
begin select * into o from atlas.planned_work_occurrences where id=p_occurrence_id for update; if o.id is null then raise exception 'Planned occurrence was not found.' using errcode='P0002'; end if;
if p_signal_key like 'rhythm_clock:%' then
  if o.source_kind is distinct from 'rhythm_state' or o.source_id is null
  then
    raise exception 'Rhythm clock signal cannot invent native rhythm source'
      using errcode='42501';
  end if;
  if atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(o.source_id)
  then
    -- 6A + one U1A/U1B governor: this signal only records that a
    -- source clock boundary was observed. It does NOT satisfy an old
    -- occurrence's task-release gate, turn it eligible, trigger the
    -- shared farm-wide release sweep or issue the next original.
    -- Existing historical Task/occurrence identity is never erased.
    update atlas.planned_work_occurrences
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
       'last_signal_key',p_signal_key,
       'last_signal_payload',coalesce(p_payload,'{}'::jsonb),
       'last_signal_at',now(),
       'governed_signal_requires_independent_work_issuance',true,
       'automatic_task_release_authorized',false),
       updated_at=now()
    where id=o.id;
    return jsonb_build_object(
      'occurrenceId',o.id,
      'release',jsonb_build_object(
        'action','governed_rhythm_clock_signal_held',
        'noNewWorkCreated',true,'noAutomaticNextTask',true,
        'currentRulebookNotReplaced',true),
      'taskId',null,
      'historicalTaskPreserved',o.released_task_id is not null);
  end if;
end if; update atlas.planned_work_occurrences set gate_satisfied_at=now(),state=case when state in ('released','completed') then state else 'eligible' end,metadata=metadata||jsonb_build_object('last_signal_key',p_signal_key,'last_signal_payload',coalesce(p_payload,'{}'::jsonb),'last_signal_at',now()),updated_at=now() where id=o.id; v_release:=atlas.release_eligible_work_v1(o.farm_id,null,1); return jsonb_build_object('occurrenceId',o.id,'release',v_release,'taskId',(select released_task_id from atlas.planned_work_occurrences where id=o.id)); end;$function$

COMMIT;
