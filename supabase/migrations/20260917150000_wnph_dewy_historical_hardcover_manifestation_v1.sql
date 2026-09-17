-- Correct The Wish Fairy and Dewy Dear WNPH physical manifestation from an
-- accidental paperback assumption to the historically grounded restored
-- cloth-hardcover target. Preserve the existing Manifestation UUID and all
-- prior derivation history; add a new physical render profile/derivation.
--
-- Historical bound-book dimensions remain source evidence only. This migration
-- does not promote them into an exact WNPH trim specification.

do $$
begin
  if not exists (
    select 1
    from wnph.manifestations
    where id = '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid
      and canonical_key = 'wish-fairy-dewy-dear:wnph-paperback-v1'
      and status = 'planned'
  ) then
    raise exception 'Expected planned Dewy WNPH paperback manifestation was not found in the audited state';
  end if;

  if exists (
    select 1
    from wnph.manifestations
    where canonical_key = 'wish-fairy-dewy-dear:wnph-hardcover-v1'
      and id <> '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid
  ) then
    raise exception 'Dewy hardcover canonical key is already owned by another manifestation';
  end if;
end
$$;

update wnph.manifestations
set canonical_key = 'wish-fairy-dewy-dear:wnph-hardcover-v1',
    publication_statement = 'WNPH restored publication manifestation planned from the governed publication Expression and historically grounded in the Henry Altemus c1922 physical edition.',
    format_statement = 'restored cloth hardcover; gray cloth with green lettering/art treatment; matching historical dust-jacket character documented separately pending approved jacket artwork; final WNPH trim unresolved',
    notes = 'Physical restored hardcover manifestation. Historical evidence records gray cloth, green lettering, book-specific multicolor artwork/applique, approximately 5.5 x 4.25 inch bound-book dimensions, and a matching white coated dust jacket. WNPH intentionally adopts that historical physical character as the restoration target. The approximate historical dimensions remain source evidence and do not establish exact WNPH printer trim. Text authority remains the publication Expression master. Final WNPH trim, spine width, stocks, final page block, and jacket artwork remain unresolved until governed publication inputs establish them.'
where id = '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid;

insert into wnph.publication_render_profiles (
  id,
  canonical_key,
  output_family,
  profile_version,
  rules,
  profile_status,
  notes,
  supersedes_profile_id
)
values (
  'be1709a8-b4a1-4d54-bea0-82dc845c4b73'::uuid,
  'wnph:render:cloth-hardcover:v1',
  'hardcover',
  '1',
  jsonb_build_object(
    'input_view', 'v_wnph_expression_render_input_v1',
    'text_input_view', 'v_wnph_expression_render_input_v1',
    'media_input_view', 'v_wnph_expression_media_input_v1',
    'master_contract', 'publication_expression',
    'master_snapshot_contract', 'wnph_publication_expression_snapshot_v2',
    'physical_output', true,
    'text_and_media_master', true,
    'requires_print_interior', true,
    'geometry_owned_by_manifestation', true,
    'require_single_expression_snapshot', true,
    'construction', 'cloth-case'
  ),
  'active',
  'Cloth-hardcover physical rendering profile. Typography, trim, case geometry, materials, and jacket state belong to the Manifestation/EPP and do not alter publication Expression text authority.',
  null
)
on conflict (canonical_key) do nothing;

do $$
begin
  if not exists (
    select 1
    from wnph.publication_render_profiles
    where id = 'be1709a8-b4a1-4d54-bea0-82dc845c4b73'::uuid
      and canonical_key = 'wnph:render:cloth-hardcover:v1'
      and output_family = 'hardcover'
      and profile_status = 'active'
  ) then
    raise exception 'Dewy hardcover render profile did not resolve to the expected canonical profile';
  end if;

  if not exists (
    select 1
    from wnph.publication_manifestation_derivations
    where id = '7a8f443a-1ace-4675-95e0-c3874bdd43e9'::uuid
      and manifestation_id = '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid
      and publication_expression_id = 'd383ca4f-227f-4455-b7d0-169d7485e5a2'::uuid
      and derivation_status = 'planned'
  ) then
    raise exception 'Expected latest audited Dewy paperback derivation is missing; refusing to invent a supersession chain';
  end if;
end
$$;

insert into wnph.publication_manifestation_derivations (
  id,
  source_package_id,
  render_profile_id,
  manifestation_id,
  derivation_status,
  build_metadata,
  supersedes_derivation_id,
  publication_expression_id
)
select
  'aeac0ab9-0b32-4a1d-aff6-c6cb72fb0d42'::uuid,
  d.source_package_id,
  'be1709a8-b4a1-4d54-bea0-82dc845c4b73'::uuid,
  d.manifestation_id,
  'planned',
  d.build_metadata
    - 'output_family'
    - 'fanout_contract'
    - 'profile_upgrade'
    - 'supersession_reason'
    - 'render_contract_version'
    || jsonb_build_object(
      'output_family', 'hardcover',
      'construction', 'cloth-case',
      'restoration_basis', 'henry_altemus_c1922_physical_character',
      'manifestation_correction', 'paperback_to_historically_grounded_cloth_hardcover',
      'supersession_reason', 'correct_accidental_paperback_manifestation_assumption',
      'render_contract_version', 1
    ),
  d.id,
  d.publication_expression_id
from wnph.publication_manifestation_derivations d
where d.id = '7a8f443a-1ace-4675-95e0-c3874bdd43e9'::uuid
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1
    from wnph.manifestations
    where id = '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid
      and canonical_key = 'wish-fairy-dewy-dear:wnph-hardcover-v1'
      and format_statement ilike '%cloth hardcover%'
      and format_statement ilike '%trim unresolved%'
  ) then
    raise exception 'Dewy WNPH manifestation hardcover correction failed';
  end if;

  if not exists (
    select 1
    from wnph.publication_manifestation_derivations
    where id = 'aeac0ab9-0b32-4a1d-aff6-c6cb72fb0d42'::uuid
      and manifestation_id = '0bb1920c-3df4-4ae9-9e4a-67ba8b39ff82'::uuid
      and render_profile_id = 'be1709a8-b4a1-4d54-bea0-82dc845c4b73'::uuid
      and supersedes_derivation_id = '7a8f443a-1ace-4675-95e0-c3874bdd43e9'::uuid
      and derivation_status = 'planned'
  ) then
    raise exception 'Dewy hardcover derivation was not created with the expected custody chain';
  end if;
end
$$;
