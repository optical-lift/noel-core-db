create or replace view titus.v_teacher_source_adjudication_targets_live
with (security_invoker = true)
as
select
  a.adjudication_id,
  a.source_unit_id,
  u.unit_key,
  u.unit_title,
  a.disposition,
  a.approval_status,
  t.adjudication_target_id,
  t.target_kind,
  t.relation_type,
  t.confidence,
  t.review_status,
  t.relation_note,
  t.canon_claim_id,
  c.claim_key,
  c.claim_text,
  c.status as claim_status,
  t.truth_ref_id,
  tr.ref_kind,
  tr.song_object_id,
  tr.function_key,
  tr.label_snapshot as truth_label_snapshot
from titus.teacher_source_adjudications a
join titus.teacher_source_units u on u.source_unit_id=a.source_unit_id
join titus.teacher_source_adjudication_targets t on t.adjudication_id=a.adjudication_id
left join titus.canon_claims c on c.canon_claim_id=t.canon_claim_id
left join titus.truth_refs tr on tr.truth_ref_id=t.truth_ref_id;
revoke all on titus.v_teacher_source_adjudication_targets_live from anon, authenticated;