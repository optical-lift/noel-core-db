begin;

-- Atlas Implementation Legacy Establishment Authority Cutover v1
--
-- Behavioral cutover ONLY.
--
-- Prerequisite:
--   additive Reality Candidate custody is already live and the compatible Atlas
--   application has moved manual reality intake away from legacy establishment
--   text authority.
--
-- This migration does not create Reality Candidate infrastructure. It removes
-- only one legacy authority: practitioner-authored free text may no longer mark
-- itself "established" without an owning-domain canonical consequence.
--
-- Historical established rows are preserved.

do $prerequisite$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Reality Candidate custody must be live before legacy authority cutover.'
      using errcode='0A000';
  end if;
end;
$prerequisite$;

create or replace function atlas.save_implementation_establishment_item_self_api_v1(
  p_implementation_case_id uuid,
  p_category text,
  p_title text,
  p_detail text default '',
  p_status text default 'proposed'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.implementation_cases c
    where c.id=p_implementation_case_id
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Open implementation case not found.'
      using errcode='23503';
  end if;

  if p_category not in (
    'institution',
    'ledger_scope',
    'people_authority',
    'implementation_authority',
    'boundary',
    'unresolved'
  ) then
    raise exception 'Invalid establishment category.'
      using errcode='22023';
  end if;

  if p_status not in ('proposed','unresolved') then
    raise exception 'Implementation text may be proposed or unresolved only; established reality requires an owning-domain canonical consequence.'
      using errcode='22023';
  end if;

  insert into atlas.implementation_establishment_items(
    implementation_case_id,
    category,
    title,
    detail,
    status,
    author_user_id,
    basis
  ) values (
    p_implementation_case_id,
    p_category,
    btrim(p_title),
    coalesce(p_detail,''),
    p_status,
    auth.uid(),
    jsonb_build_object(
      'source','practitioner_workbench',
      'authorityBoundary','candidate_only_after_reality_sentence_v1'
    )
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'id',v_id,
    'status',p_status,
    'canonicalMutation',false
  );
end;
$function$;

revoke all on function atlas.save_implementation_establishment_item_self_api_v1(
  uuid,text,text,text,text
) from public,anon,authenticated,service_role;

comment on function atlas.save_implementation_establishment_item_self_api_v1(
  uuid,text,text,text,text
) is
  'Legacy Implementation establishment-item writer retained only for compatibility coordination. Practitioner input may persist proposed/unresolved material; canonical establishment requires an owning-domain consequence.';

comment on table atlas.implementation_establishment_items is
  'Legacy Implementation coordination material. Historical established rows are preserved. New practitioner text cannot become canonical truth through this table after the Reality Candidate application cutover.';

commit;
