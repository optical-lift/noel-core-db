
alter table draft.reality_witness_adapter_registry
  add column if not exists identity_source_system_key text,
  add column if not exists identity_source_record_kind text;

update draft.reality_witness_adapter_registry
set identity_source_system_key='practice',
    identity_source_record_kind='person',
    updated_at=now()
where adapter_key in (
  'practice_body_observation',
  'practice_context_observation',
  'practice_intervention',
  'practice_outcome',
  'practice_discernment_signal'
);

update draft.reality_witness_adapter_registry
set identity_source_system_key='celestial',
    identity_source_record_kind='subject',
    updated_at=now()
where adapter_key in ('celestial_body_state','celestial_chart_event');

comment on column draft.reality_witness_adapter_registry.identity_source_system_key is
'Atlas identity source_system_key used when this adapter emits subject-bound objects. Null means the adapter does not participate in Atlas identity resolution.';

comment on column draft.reality_witness_adapter_registry.identity_source_record_kind is
'Atlas identity source_record_kind used to resolve this adapter''s source-local subject reference.';

create or replace view intelligence.v_reality_source_subject_resolution_v1
with (security_invoker=true)
as
select distinct
  wo.adapter_key,
  wo.witness_key,
  wo.object_type,
  wo.object_id,
  wo.subject_ref_type,
  wo.subject_ref,
  isr.organization_id,
  isa.subject_id as identity_subject_id,
  ipr.person_id as atlas_person_id,
  isa.assertion_kind,
  isa.confidence,
  isa.basis,
  isr.source_system_key,
  isr.source_record_kind,
  isr.source_record_key
from intelligence.v_reality_witness_objects_v2 wo
join draft.reality_witness_adapter_registry ar
  on ar.adapter_key=wo.adapter_key
 and ar.identity_source_system_key is not null
 and ar.identity_source_record_kind is not null
join atlas.identity_source_records isr
  on isr.source_system_key=ar.identity_source_system_key
 and isr.source_record_kind=ar.identity_source_record_kind
 and isr.source_record_key=wo.subject_ref
join atlas.identity_source_subject_assertions isa
  on isa.source_record_id=isr.id
join atlas.institutional_person_records ipr
  on ipr.organization_id=isr.organization_id
 and ipr.identity_subject_id=isa.subject_id
 and ipr.status='active'
where wo.subject_ref is not null;

comment on view intelligence.v_reality_source_subject_resolution_v1 is
'Resolves source-local Reality Witness subjects through Atlas identity custody to canonical atlas.people Person IDs. It does not infer identity from names, labels, or string similarity.';

revoke all on intelligence.v_reality_source_subject_resolution_v1 from anon,authenticated;
grant select on intelligence.v_reality_source_subject_resolution_v1 to service_role;
