-- Structural gate only. Run after my-work-status-candidate.sql on the
-- protected disposable PG17 production-schema clone; never on production.
-- This does NOT substitute for signed Auth/REST, revoked Person or outsider proof.
DO $status$
DECLARE
  s text;
  f regprocedure;
BEGIN
  f:=to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)');
  IF f IS NULL THEN
    RAISE EXCEPTION 'Existing signed Person My Work reader absent';
  END IF;
  s:=pg_get_functiondef(f::oid);
  IF position('latestResultKind' in s)=0 OR
     position('latest_result.result_kind' in s)=0 OR
     position('r.responsible_allocation_id=a.id' in s)=0 OR
     position('r.work_item_id=w.id' in s)=0 OR
     position('a.assignee_canonical_person_id=v_self' in s)=0 OR
     position('a.state=''active''' in s)=0 OR
     position('w.work_state=''open''' in s)=0 OR
     position('person_original_work_identity_disclosed_self_v1' in s)=0 OR
     position('person_has_native_ledger_connection_v1' in s)=0 OR
     position('optionalRequestsExcluded' in s)=0
  THEN
    RAISE EXCEPTION 'My Work result status is missing a source-identity, connected-Person, or exact responsible-allocation guard';
  END IF;
  IF position('r.payload' in s)>0 OR
     position('payload.note' in s)>0 OR
     position('noteText' in s)>0
  THEN
    RAISE EXCEPTION 'My Work summary must not expose a Result narrative';
  END IF;
  RAISE NOTICE 'PASS structural latest-Result-kind custody only; actor authorization NOT TESTED';
END
$status$;
