create or replace view atlas.v_flower_buyer_correspondence_position_v1 as
select
  f.id as farm_id,rel.organization_id,rel.organization_unit_id,rel.id as external_relationship_id,rel.subject_id,
  coalesce(proj.display_name,legacy.business_name,rel.stable_key) as relationship_label,rel.relationship_state,
  last_message.occurred_at as last_message_at,last_message.direction as last_message_direction,last_message.subject as last_message_subject,last_message.body as last_message_body,last_message.participant_address as last_message_address,
  last_outgoing.occurred_at as last_outgoing_at,last_outgoing.subject as last_outgoing_subject,last_outgoing.body as last_outgoing_body,
  last_incoming.occurred_at as last_incoming_at,last_incoming.subject as last_incoming_subject,last_incoming.body as last_incoming_body,
  case when last_interaction.occurred_at is null then last_message.occurred_at when last_message.occurred_at is null then last_interaction.occurred_at else greatest(last_interaction.occurred_at,last_message.occurred_at) end as last_contact_at,
  case
    when last_message.direction='outgoing'
      and (last_incoming.occurred_at is null or last_message.occurred_at>last_incoming.occurred_at)
      and not (last_interaction.interaction_kind='email_bounced' and last_interaction.occurred_at>=last_message.occurred_at)
    then true else false end as awaiting_reply,
  last_interaction.interaction_kind as last_interaction_kind,last_interaction.channel as last_interaction_channel,last_interaction.outcome as last_interaction_outcome,last_interaction.follow_up as last_follow_up
from atlas.external_relationships rel
join atlas.farms f on f.organization_id=rel.organization_id and f.organization_unit_id is not distinct from rel.organization_unit_id
left join atlas.identity_subject_projections proj on proj.subject_id=rel.subject_id
left join atlas.legacy_buyer_relationship_external_mappings lm on lm.external_relationship_id=rel.id
left join atlas.buyer_relationship_reconstruction legacy on legacy.id=lm.buyer_relationship_id
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id order by e.occurred_at desc,e.event_key desc limit 1) last_message on true
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id and e.direction='outgoing' order by e.occurred_at desc,e.event_key desc limit 1) last_outgoing on true
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id and e.direction='incoming' order by e.occurred_at desc,e.event_key desc limit 1) last_incoming on true
left join lateral (select i.* from atlas.external_relationship_interactions i where i.external_relationship_id=rel.id order by i.occurred_at desc,i.id desc limit 1) last_interaction on true
where exists(select 1 from atlas.external_relationship_roles rr where rr.external_relationship_id=rel.id and rr.role_key='customer' and rr.role_state='active');
comment on view atlas.v_flower_buyer_correspondence_position_v1 is 'Current correspondence position for flower customer relationships. Last-contact fields are derived from append-only evidence; awaiting_reply is false when the latest relevant delivery result is an email bounce.';