-- Normalize Elm purpose-context stable keys to reusable Organization-scoped function keys.
-- Titles and Organization-owned metadata remain Elm-specific display/content data.

update atlas.organization_purpose_contexts
set stable_key = case stable_key
  when 'elm_community_calendar' then 'community_calendar'
  when 'elm_educational_events' then 'educational_events'
  when 'elm_local_resources' then 'local_resources'
  else stable_key
end,
updated_at = now()
where organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
  and stable_key in (
    'elm_community_calendar',
    'elm_educational_events',
    'elm_local_resources'
  );
