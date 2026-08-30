-- Repair the per-page Commons access render URLs without changing the governed 1575 master surrogate.
-- Wikimedia's current thumbnail service accepts the listed 500px derivative for this multipage DjVu,
-- while the previously registered 934px page-thumbnail form now returns HTTP 400.
do $$
declare
  v_pkg uuid;
  r record;
  v_page integer;
  v_uri text;
begin
  select p.id into strict v_pkg
  from wnph.publication_source_packages p
  where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  for r in
    select a.*
    from wnph.publication_source_assets a
    where a.source_package_id=v_pkg
      and a.asset_role='source_surface'
      and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    order by (a.source_locator->>'sequence_index')::integer
  loop
    v_page := (r.source_locator->>'scan_page')::integer;
    v_uri := 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/A_Proper_New_Booke_of_Cookery_%281575%29.djvu/page'
             || v_page::text || '-500px-A_Proper_New_Booke_of_Cookery_%281575%29.djvu.jpg';

    insert into wnph.publication_source_assets(
      source_package_id,asset_key,asset_role,source_surrogate_id,evidence_source_id,
      source_locator,storage_uri,media_type,metadata,supersedes_asset_id
    ) values(
      r.source_package_id,r.asset_key,r.asset_role,r.source_surrogate_id,r.evidence_source_id,
      jsonb_set(r.source_locator,'{image_uri}',to_jsonb(v_uri),true),
      v_uri,
      r.media_type,
      r.metadata || jsonb_build_object(
        'render_width_px',500,
        'access_render_status','repaired',
        'access_render_reason','Wikimedia current multipage thumbnail width requirement',
        'master_surrogate_unchanged',true
      ),
      r.id
    );
  end loop;

  if (select count(*) from wnph.publication_source_assets a where a.source_package_id=v_pkg and a.asset_role='source_surface' and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)) <> 33 then
    raise exception 'WNPH Proper New Booke source-surface repair: expected exactly 33 active source surfaces';
  end if;
end $$;