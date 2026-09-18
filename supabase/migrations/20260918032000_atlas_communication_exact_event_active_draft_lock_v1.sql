begin;

create unique index if not exists communication_email_drafts_active_exact_composition_uniq
on atlas.communication_email_drafts(
  communication_conversation_id,
  source_communication_event_id,
  composition_kind
)
where draft_state='active'
  and communication_conversation_id is not null
  and source_communication_event_id is not null
  and composition_kind in ('reply','reply_all','forward');

comment on index atlas.communication_email_drafts_active_exact_composition_uniq is
'One active exact-Event reply/reply-all/forward draft per common Conversation and composition mode. This is the durable collision lock; browser presence is only a projection of it.';

commit;
