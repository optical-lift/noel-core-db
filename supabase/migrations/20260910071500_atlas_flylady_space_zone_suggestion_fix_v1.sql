-- Correct FlyLady room-zone proposal defaults before production application.
-- Generic bathrooms and non-primary bedrooms belong with Zone 3 suggestions;
-- only explicitly primary bedroom/bath/closet spaces suggest Zone 4.

create or replace function atlas.flylady_suggested_zone_for_space_v1(p_space_type text,p_tags text[])
returns smallint
language sql
immutable
set search_path=pg_catalog
as $function$
  select case
    when coalesce(p_space_type,'') in ('entry_mudroom','entry','porch','dining','dining_room')
      or coalesce(p_tags,'{}'::text[]) && array['arrival','transition','dining']::text[] then 1
    when coalesce(p_space_type,'') in ('kitchen','pantry','food_storage')
      or coalesce(p_tags,'{}'::text[]) && array['food','kitchen','pantry']::text[] then 2
    when coalesce(p_space_type,'') in ('bathroom','bedroom','office','utility','craft_room','kids_room','guest_room','secondary_room')
      or coalesce(p_tags,'{}'::text[]) && array['hygiene','secondary_room']::text[] then 3
    when coalesce(p_space_type,'') in ('primary_bedroom','primary_closet','primary_bathroom')
      or coalesce(p_tags,'{}'::text[]) && array['primary_sleeping','dressing']::text[] then 4
    when coalesce(p_space_type,'') in ('living_space','living_room','family_room')
      or coalesce(p_tags,'{}'::text[]) && array['primary_gathering']::text[] then 5
    else null
  end::smallint;
$function$;
