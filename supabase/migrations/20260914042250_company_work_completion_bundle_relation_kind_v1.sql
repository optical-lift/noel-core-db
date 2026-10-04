alter table atlas.work_item_relations drop constraint if exists work_item_relations_relation_kind_check;
alter table atlas.work_item_relations add constraint work_item_relations_relation_kind_check
check (relation_kind = any (array['blocks'::text,'enables'::text,'depends_on'::text,'part_of'::text,'alternative_to'::text,'handoff_to'::text,'completion_bundle_member'::text]));