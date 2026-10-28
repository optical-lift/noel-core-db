-- Shadow reads ONLY; this view must never be used as permission to
-- complete Work. It compares one chronological state observation stream
-- with the original mutable Work position for cutover parity.
CREATE OR REPLACE VIEW atlas.work_lifecycle_shadow_reconciliation_v1
WITH (security_invoker=true)
AS
SELECT
 w.id AS work_item_id,w.organization_id,w.household_id,
 w.work_state AS live_state,
 (SELECT e.to_state FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=w.id
     AND e.event_kind IN (
       'historical_state_snapshot','work_established','work_state_observed')
   ORDER BY e.sequence_no DESC LIMIT 1) AS shadow_state,
 w.work_state IS NOT DISTINCT FROM
 (SELECT e.to_state FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=w.id
     AND e.event_kind IN (
       'historical_state_snapshot','work_established','work_state_observed')
   ORDER BY e.sequence_no DESC LIMIT 1) AS state_matches,
 (SELECT count(*) FROM atlas.work_execution_results r
    WHERE r.work_item_id=w.id) AS original_result_count,
 (SELECT count(*) FROM atlas.work_result_acceptances a
    WHERE a.work_item_id=w.id AND a.decision='accepted')
      AS original_accepted_result_count,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='result_reported')
      AS shadow_result_links,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='result_accepted')
      AS shadow_acceptance_links,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='historical_state_snapshot')
      AS baseline_count
FROM atlas.work_items w;
REVOKE ALL ON atlas.work_lifecycle_shadow_reconciliation_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- These must be installed only after a baseline is seeded while originals
-- are locked in a single migration transaction.
CREATE TRIGGER work_items_shadow_lifecycle_insert_v1
 AFTER INSERT ON atlas.work_items FOR EACH ROW
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_items_shadow_lifecycle_state_v1
 AFTER UPDATE OF work_state ON atlas.work_items
 FOR EACH ROW WHEN(OLD.work_state IS DISTINCT FROM NEW.work_state)
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();

CREATE TRIGGER work_execution_results_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_result_acceptances_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_result_acceptances
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_allocations_shadow_lifecycle_insert_v1
 AFTER INSERT ON atlas.work_allocations
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_allocations_shadow_lifecycle_state_v1
 AFTER UPDATE OF state,assignee_canonical_person_id,
 assignee_membership_id,assignee_household_member_id
 ON atlas.work_allocations FOR EACH ROW
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_execution_plan_events_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_execution_plan_events
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
