create table wnph.publication_source_observations (
  id uuid primary key default gen_random_uuid(),
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  observation_key text not null check (btrim(observation_key) <> ''),
  observation_kind text not null check (observation_kind in ('page_text','layout_region','region','line','word','symbol')),
  ordinal integer check (ordinal is null or ordinal >= 0),
  text_candidate text,
  coordinate_unit text not null default 'pixel' check (coordinate_unit in ('pixel','percent','alto_1_1200in','alto_1_10mm','surface')),
  x numeric,
  y numeric,
  width numeric,
  height numeric,
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  source_format text not null check (btrim(source_format) <> ''),
  processor jsonb not null default '{}'::jsonb,
  external_locator jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_observation_id uuid references wnph.publication_source_observations(id),
  created_at timestamptz not null default now(),
  constraint publication_source_observations_geometry_ck check (
    ((x is null and y is null and width is null and height is null)
      or
     (x is not null and y is not null and width is not null and height is not null
      and x >= 0 and y >= 0 and width > 0 and height > 0))
  ),
  constraint publication_source_observations_surface_geometry_ck check (
    coordinate_unit <> 'surface' or (x is null and y is null and width is null and height is null)
  ),
  constraint publication_source_observations_supersedes_not_self check (
    supersedes_observation_id is null or supersedes_observation_id <> id
  )
);

comment on table wnph.publication_source_observations is
  'Append-only located recognition/transcription observations below the semantic publication source. A source image/page remains a publication_source_asset; observations retain OCR/layout/manual readings, coordinates, confidence, processor identity and upstream locator without becoming canonical prose.';

comment on column wnph.publication_source_observations.coordinate_unit is
  'Coordinate system for x/y/width/height. pixel and percent map directly to IIIF spatial addressing; ALTO native units remain explicit; surface means the observation applies to the whole source surface.';

create index publication_source_observations_asset_idx
  on wnph.publication_source_observations(source_asset_id);
create index publication_source_observations_asset_kind_ordinal_idx
  on wnph.publication_source_observations(source_asset_id,observation_kind,ordinal);
create index publication_source_observations_supersedes_idx
  on wnph.publication_source_observations(supersedes_observation_id)
  where supersedes_observation_id is not null;

create or replace function wnph.validate_publication_source_surface_asset_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_old wnph.publication_source_assets%rowtype;
begin
  if new.asset_role <> 'source_surface' then
    return new;
  end if;

  if jsonb_typeof(new.source_locator) <> 'object' then
    raise exception 'WNPH source surface: source_locator must be an object';
  end if;

  if coalesce(new.storage_uri,'') = ''
     and coalesce(new.source_locator->>'image_uri','') = ''
     and coalesce(new.source_locator->>'iiif_canvas_uri','') = ''
     and coalesce(new.source_locator->>'iiif_image_service_uri','') = '' then
    raise exception 'WNPH source surface: requires storage_uri, image_uri, iiif_canvas_uri, or iiif_image_service_uri';
  end if;

  if new.supersedes_asset_id is not null then
    select * into v_old
    from wnph.publication_source_assets
    where id=new.supersedes_asset_id;

    if v_old.id is null or v_old.asset_role <> 'source_surface' then
      raise exception 'WNPH source surface: superseded asset must be a source_surface';
    end if;
    if v_old.source_package_id <> new.source_package_id or v_old.asset_key <> new.asset_key then
      raise exception 'WNPH source surface: supersession must preserve package and asset_key';
    end if;
    if exists(select 1 from wnph.publication_source_assets a where a.supersedes_asset_id=v_old.id) then
      raise exception 'WNPH source surface: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1
    from wnph.publication_source_assets a
    where a.source_package_id=new.source_package_id
      and a.asset_key=new.asset_key
      and a.asset_role='source_surface'
      and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
  ) then
    raise exception 'WNPH source surface: duplicate active asset_key %',new.asset_key;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_surface_asset_v1() from public,anon,authenticated,service_role;

create trigger publication_source_assets_surface_validation_v1
before insert on wnph.publication_source_assets
for each row execute function wnph.validate_publication_source_surface_asset_v1();

create or replace function wnph.validate_publication_source_observation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_asset wnph.publication_source_assets%rowtype;
  v_old wnph.publication_source_observations%rowtype;
begin
  select * into v_asset
  from wnph.publication_source_assets
  where id=new.source_asset_id;

  if v_asset.id is null or v_asset.asset_role <> 'source_surface' then
    raise exception 'WNPH source observation: source_asset_id must identify a source_surface asset';
  end if;

  if coalesce(new.processor->>'provider','')='' or coalesce(new.processor->>'engine','')='' then
    raise exception 'WNPH source observation: processor requires provider and engine';
  end if;

  if new.observation_kind in ('page_text','line','word','symbol') and coalesce(btrim(new.text_candidate),'')='' then
    raise exception 'WNPH source observation: text-bearing observation requires text_candidate';
  end if;

  if new.supersedes_observation_id is not null then
    select * into v_old
    from wnph.publication_source_observations
    where id=new.supersedes_observation_id;

    if v_old.id is null or v_old.source_asset_id <> new.source_asset_id or v_old.observation_key <> new.observation_key then
      raise exception 'WNPH source observation: supersession must preserve source asset and observation_key';
    end if;
    if exists(select 1 from wnph.publication_source_observations o where o.supersedes_observation_id=v_old.id) then
      raise exception 'WNPH source observation: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1
    from wnph.publication_source_observations o
    where o.source_asset_id=new.source_asset_id
      and o.observation_key=new.observation_key
      and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
  ) then
    raise exception 'WNPH source observation: duplicate active observation_key %',new.observation_key;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_observation_v1() from public,anon,authenticated,service_role;

create trigger publication_source_observations_insert_validation_v1
before insert on wnph.publication_source_observations
for each row execute function wnph.validate_publication_source_observation_v1();

create trigger publication_source_observations_append_only
before update or delete on wnph.publication_source_observations
for each row execute function wnph.reject_append_only_mutation();

with basis as (
  select p.id as source_package_id,
         s.id as source_surrogate_id,
         a.evidence_source_id
  from wnph.publication_source_packages p
  join wnph.surrogates s on s.canonical_key='wish-fairy-dewy-dear:loc-digital'
  join wnph.publication_source_assets a
    on a.source_package_id=p.id and a.asset_key='historical-source-surrogate'
  where p.id='7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid
  limit 1
), leaves(loc_image,printed_page,pixel_width,pixel_height) as (
  values
    (11,7,1736,2378),(12,8,1719,2412),(13,9,1719,2412),(14,10,1719,2412),(15,11,1719,2412),
    (16,12,1719,2412),(17,13,1719,2412),(18,14,1719,2412),(19,15,1719,2412),(20,16,1719,2412)
)
insert into wnph.publication_source_assets(
  source_package_id,asset_key,asset_role,source_surrogate_id,evidence_source_id,source_locator,storage_uri,media_type,metadata
)
select b.source_package_id,
       format('dewy:loc:source-surface:%s',lpad(l.loc_image::text,4,'0')),
       'source_surface',
       b.source_surrogate_id,
       b.evidence_source_id,
       jsonb_build_object(
         'repository','Library of Congress',
         'item_uri','https://www.loc.gov/item/22008427/',
         'loc_image',l.loc_image,
         'printed_page',l.printed_page,
         'source_pdf_page',l.loc_image,
         'pixel_width',l.pixel_width,
         'pixel_height',l.pixel_height,
         'iiif_image_service_uri',format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s',lpad(l.loc_image::text,4,'0')),
         'iiif_info_uri',format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s/info.json',lpad(l.loc_image::text,4,'0')),
         'image_uri',format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s/full/max/0/default.jpg',lpad(l.loc_image::text,4,'0')),
         'alto_uri',format('https://tile.loc.gov/text-services/word-coordinates-service?segment=/public/gdcmassbookdig/wishfairydewydea00colv/wishfairydewydea00colv_%s.alto.xml&format=alto_xml&full_text=1',lpad(l.loc_image::text,4,'0'))
       ),
       null,
       'image/jpeg',
       jsonb_build_object(
         'remote_custody',true,
         'byte_copy_required',false,
         'addressing_standard','iiif_image_api',
         'fixture_scope','dewy_chapter_1'
       )
from basis b cross join leaves l;

insert into wnph.publication_source_observations(
  source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
  derivation_method,source_format,processor,external_locator,metadata
)
select a.id,
       'loc-alto:page-text:v1',
       'page_text',
       0,
       $ocr$hind the mountains. It was out
of sight before he reached it, and,
sure enough, just as it disappeared,
a great big white puffy cloud
popped its head up over the edge
of the world. It was colored in
wonderful colors; mostly shades of
pink and orange and purple and
red, but by the time the weary
eagle had reached it, the color had
faded and it was just a thick gray
and white heap.
The eagle tumbled down in it
and rested on its edge. Miss Wish
Fairy hopped off his back and
made her way straight to the
centre of the cloud. Here she saw
dimly through the mist, seated on
his throne, the King of the Clouds,
and about him were his gray-clad
Rain Fairies. They all stopped
their dancing and prancing to the
soft musical sound of raindrops, as
the Wish Fairy came near, and
11$ocr$,
       'surface',
       'imported_repository_ocr_without_semantic_normalization',
       'alto_xml',
       jsonb_build_object('provider','library_of_congress','engine','upstream_ocr','version','unknown'),
       jsonb_build_object('alto_uri',a.source_locator->>'alto_uri'),
       jsonb_build_object('reading_authority','machine_observation_only','canonical_text_asserted',false)
from wnph.publication_source_assets a
where a.source_package_id='7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid
  and a.asset_key='dewy:loc:source-surface:0015';

do $verify$
declare
  v_surfaces integer;
  v_observations integer;
  v_bad_survived integer;
begin
  select count(*) into v_surfaces
  from wnph.publication_source_assets
  where source_package_id='7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid
    and asset_role='source_surface'
    and metadata->>'fixture_scope'='dewy_chapter_1';

  select count(*) into v_observations
  from wnph.publication_source_observations o
  join wnph.publication_source_assets a on a.id=o.source_asset_id
  where a.source_package_id='7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid;

  if v_surfaces<>10 or v_observations<>1 then
    raise exception 'WNPH source-surface fixture parity failed: surfaces %, observations %',v_surfaces,v_observations;
  end if;

  begin
    insert into wnph.publication_source_observations(
      source_asset_id,observation_key,observation_kind,text_candidate,coordinate_unit,
      derivation_method,source_format,processor
    )
    select a.id,'invalid-processor-fixture','page_text','fake','surface','test','plain_text','{}'::jsonb
    from wnph.publication_source_assets a
    where a.asset_key='dewy:loc:source-surface:0015';
    raise exception 'WNPH source observation negative control unexpectedly admitted invalid processor';
  exception when others then
    if sqlerrm='WNPH source observation negative control unexpectedly admitted invalid processor' then
      raise;
    end if;
  end;

  select count(*) into v_bad_survived
  from wnph.publication_source_observations
  where observation_key='invalid-processor-fixture';

  if v_bad_survived<>0 then
    raise exception 'WNPH source observation negative control left surviving rows';
  end if;
end;
$verify$;