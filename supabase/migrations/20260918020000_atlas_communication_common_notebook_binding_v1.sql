begin;

update atlas.notebook_spread_instances
set subject_kind='correspondence',
    updated_at=now()
where subject_domain='communication'
  and subject_kind='institutional_correspondence';

update atlas.notebook_spread_source_bindings binding
set source_kind='conversation_sequence_v1',
    basis=jsonb_build_object(
      'kind','governed_projection',
      'identityRoot','communication_conversation',
      'readSeam','organization_correspondence_list_self_api_v2',
      'detailSeam','organization_correspondence_conversation_self_api_v4'
    ),
    metadata=coalesce(binding.metadata,'{}'::jsonb) || jsonb_build_object(
      'bindingContract','communication_conversation_sequence_v1'
    ),
    updated_at=now()
where binding.source_domain='communication'
  and binding.source_kind='institutional_correspondence_v1'
  and binding.binding_state='active'
  and binding.retired_at is null;

commit;
