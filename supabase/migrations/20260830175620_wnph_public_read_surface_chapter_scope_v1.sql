create or replace function public.wnph_public_title_v1(p_public_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','wnph','public'
as $function$
declare
  v_release wnph.publication_releases%rowtype;
  v_payload jsonb;
begin
  select r.* into v_release
  from wnph.publication_releases r
  where r.public_slug=p_public_slug
    and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id)
  order by r.release_sequence desc
  limit 1;

  if v_release.id is null or v_release.release_state <> 'released' then
    raise exception 'WNPH public title not found' using errcode='P0002';
  end if;

  v_payload:=v_release.public_payload;

  return jsonb_build_object(
    'contract_version','wnph_public_title_v1',
    'release',jsonb_build_object(
      'release_key',v_release.release_key,
      'public_slug',v_release.public_slug,
      'release_sequence',v_release.release_sequence,
      'released_at',v_release.released_at,
      'render_master_sha256',v_release.render_master_sha256,
      'payload_sha256',v_release.payload_sha256
    ),
    'bibliographic',v_payload->'bibliographic',
    'rights',coalesce(v_payload->'rights','[]'::jsonb),
    'chapters',coalesce(v_payload->'chapters','[]'::jsonb),
    'public_provenance',coalesce(v_payload->'public_provenance','{}'::jsonb)
  );
end;
$function$;

create or replace function public.wnph_public_read_chapter_v1(p_public_slug text,p_chapter_number integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','wnph','public'
as $function$
declare
  v_release wnph.publication_releases%rowtype;
  v_payload jsonb;
  v_chapter jsonb;
  v_chapter_key text;
  v_chapter_path text;
  v_blocks jsonb;
  v_media jsonb;
  v_chapter_count integer;
begin
  if p_chapter_number is null or p_chapter_number < 1 then
    raise exception 'WNPH public chapter number invalid' using errcode='22023';
  end if;

  select r.* into v_release
  from wnph.publication_releases r
  where r.public_slug=p_public_slug
    and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id)
  order by r.release_sequence desc
  limit 1;

  if v_release.id is null or v_release.release_state <> 'released' then
    raise exception 'WNPH public chapter not found' using errcode='P0002';
  end if;

  v_payload:=v_release.public_payload;

  select c.value into v_chapter
  from jsonb_array_elements(coalesce(v_payload->'chapters','[]'::jsonb)) c(value)
  where (c.value->>'chapter_number')::integer=p_chapter_number
  limit 1;

  if v_chapter is null then
    raise exception 'WNPH public chapter not found' using errcode='P0002';
  end if;

  v_chapter_key:=v_chapter->>'chapter_block_key';

  select b.value->>'render_path' into v_chapter_path
  from jsonb_array_elements(coalesce(v_payload->'ordered_blocks','[]'::jsonb)) b(value)
  where b.value->>'block_key'=v_chapter_key
  limit 1;

  if v_chapter_path is null then
    raise exception 'WNPH public chapter structure unresolved' using errcode='P0001';
  end if;

  select coalesce(jsonb_agg(b.value order by b.ord),'[]'::jsonb) into v_blocks
  from jsonb_array_elements(coalesce(v_payload->'ordered_blocks','[]'::jsonb)) with ordinality b(value,ord)
  where b.value->>'render_path'=v_chapter_path
     or b.value->>'render_path' like v_chapter_path||'.%';

  select coalesce(jsonb_agg(m.value order by m.ord),'[]'::jsonb) into v_media
  from jsonb_array_elements(coalesce(v_payload->'media_placements','[]'::jsonb)) with ordinality m(value,ord)
  where (m.value->'anchor_data'->>'chapter_number')::integer=p_chapter_number;

  v_chapter_count:=jsonb_array_length(coalesce(v_payload->'chapters','[]'::jsonb));

  return jsonb_build_object(
    'contract_version','wnph_public_read_chapter_v1',
    'release',jsonb_build_object(
      'release_key',v_release.release_key,
      'public_slug',v_release.public_slug,
      'release_sequence',v_release.release_sequence,
      'released_at',v_release.released_at,
      'render_master_sha256',v_release.render_master_sha256
    ),
    'bibliographic',v_payload->'bibliographic',
    'chapter',v_chapter,
    'chapter_count',v_chapter_count,
    'previous_chapter',case when p_chapter_number>1 then p_chapter_number-1 else null end,
    'next_chapter',case when p_chapter_number<v_chapter_count then p_chapter_number+1 else null end,
    'blocks',v_blocks,
    'media_placements',v_media
  );
end;
$function$;

revoke all on function public.wnph_publication_release_v1(text) from public, anon, authenticated;
grant execute on function public.wnph_publication_release_v1(text) to service_role;

revoke all on function public.wnph_public_title_v1(text) from public;
grant execute on function public.wnph_public_title_v1(text) to anon, authenticated, service_role;

revoke all on function public.wnph_public_read_chapter_v1(text,integer) from public;
grant execute on function public.wnph_public_read_chapter_v1(text,integer) to anon, authenticated, service_role;