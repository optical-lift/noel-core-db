begin;

do $validation$
declare
  v_indexdef text;
  v_duplicates bigint;
begin
  select pg_get_indexdef(indexrelid)
  into v_indexdef
  from pg_index
  where indexrelid='atlas.communication_email_drafts_active_exact_composition_uniq'::regclass;

  if v_indexdef is null
     or position('UNIQUE INDEX' in v_indexdef)=0
     or position('communication_conversation_id' in v_indexdef)=0
     or position('source_communication_event_id' in v_indexdef)=0
     or position('composition_kind' in v_indexdef)=0
     or position('draft_state' in v_indexdef)=0 then
    raise exception 'Exact-event active draft collision lock is missing or malformed.';
  end if;

  select count(*) into v_duplicates
  from (
    select communication_conversation_id,source_communication_event_id,composition_kind
    from atlas.communication_email_drafts
    where draft_state='active'
      and communication_conversation_id is not null
      and source_communication_event_id is not null
      and composition_kind in ('reply','reply_all','forward')
    group by 1,2,3
    having count(*)>1
  ) duplicates;

  if v_duplicates<>0 then
    raise exception 'Existing active exact-event composition drafts violate the collision lock.';
  end if;
end;
$validation$;

rollback;
