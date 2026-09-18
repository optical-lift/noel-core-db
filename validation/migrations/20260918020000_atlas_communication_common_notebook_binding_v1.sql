begin;

do $validation$
declare
  v_old_subject_count integer;
  v_old_binding_count integer;
  v_bad_correspondence_count integer;
  v_bad_binding_count integer;
begin
  select count(*)
  into v_old_subject_count
  from atlas.notebook_spread_instances spread
  where spread.subject_domain='communication'
    and spread.subject_kind='institutional_correspondence';

  if v_old_subject_count<>0 then
    raise exception 'Active notebook registry still contains institutional Correspondence subject vocabulary.';
  end if;

  select count(*)
  into v_old_binding_count
  from atlas.notebook_spread_source_bindings binding
  where binding.source_domain='communication'
    and binding.source_kind='institutional_correspondence_v1'
    and binding.binding_state='active'
    and binding.retired_at is null;

  if v_old_binding_count<>0 then
    raise exception 'Active notebook registry still contains institutional Correspondence source-binding vocabulary.';
  end if;

  select count(*)
  into v_bad_correspondence_count
  from atlas.notebook_spread_instances spread
  where (
      spread.section_key='Correspondence'
      or spread.spread_key like 'letters:%'
      or (spread.subject_domain='communication' and spread.subject_kind='correspondence')
    )
    and not (
      spread.subject_domain='communication'
      and spread.subject_kind='correspondence'
      and nullif(btrim(spread.subject_id),'') is not null
    );

  if v_bad_correspondence_count<>0 then
    raise exception 'Correspondence NotebookAddress subject coordinates are not common communication/correspondence coordinates.';
  end if;

  select count(*)
  into v_bad_binding_count
  from atlas.notebook_spread_instances spread
  join atlas.notebook_spread_source_bindings binding
    on binding.spread_instance_id=spread.id
   and binding.binding_state='active'
   and binding.retired_at is null
  where spread.subject_domain='communication'
    and spread.subject_kind='correspondence'
    and not (
      binding.source_domain='communication'
      and binding.source_kind='conversation_sequence_v1'
      and binding.relationship_kind='sequence'
      and binding.source_id=spread.subject_id
      and coalesce(binding.basis->>'identityRoot','')='communication_conversation'
      and coalesce(binding.basis->>'readSeam','')='organization_correspondence_list_self_api_v2'
      and coalesce(binding.basis->>'detailSeam','')='organization_correspondence_conversation_self_api_v4'
    );

  if v_bad_binding_count<>0 then
    raise exception 'Correspondence source binding is not rooted in the common Communication Conversation sequence.';
  end if;

  if exists (
    select 1
    from atlas.notebook_spread_source_bindings binding
    join atlas.notebook_spread_instances spread on spread.id=binding.spread_instance_id
    where spread.subject_domain='communication'
      and spread.subject_kind='correspondence'
      and binding.binding_state='active'
      and binding.retired_at is null
      and (
        lower(coalesce(binding.basis::text,'')) like '%institutional_shared_inbox%'
        or lower(coalesce(binding.basis::text,'')) like '%institutional_conversation_detail%'
      )
  ) then
    raise exception 'Correspondence source-binding basis still names retired Institutional read seams.';
  end if;
end;
$validation$;

rollback;
