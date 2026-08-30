create or replace function public.wnph_public_library_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, wnph, public
as $$
with active_releases as (
  select r.*
  from wnph.publication_releases r
  where r.release_state='released'
    and not exists (
      select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id
    )
), books as (
  select
    r.public_slug,
    r.release_sequence,
    r.released_at,
    r.render_master_sha256,
    r.payload_sha256,
    r.public_payload->'bibliographic' as bibliographic,
    coalesce(jsonb_array_length(r.public_payload->'chapters'),0) as chapter_count,
    coalesce(jsonb_array_length(r.public_payload->'media_placements'),0) as media_count,
    coalesce(
      (
        select m->'image'
        from jsonb_array_elements(coalesce(r.public_payload->'media_placements','[]'::jsonb)) m
        where m->>'media_role'='interior_color_plate'
        order by (m->>'sequence_ordinal')::integer
        limit 1
      ),
      (
        select m->'image'
        from jsonb_array_elements(coalesce(r.public_payload->'media_placements','[]'::jsonb)) m
        order by (m->>'sequence_ordinal')::integer
        limit 1
      )
    ) as representative_image
  from active_releases r
), public_books as (
  select jsonb_build_object(
    'public_slug',public_slug,
    'release_sequence',release_sequence,
    'released_at',released_at,
    'render_master_sha256',render_master_sha256,
    'payload_sha256',payload_sha256,
    'bibliographic',bibliographic,
    'chapter_count',chapter_count,
    'media_count',media_count,
    'representative_image',representative_image
  ) as book,
  public_slug,
  released_at,
  media_count,
  bibliographic
  from books
), shelf_rows as (
  select 'newly-recovered'::text as shelf_key, 'Newly recovered'::text as shelf_title, 10 as shelf_order, public_slug from public_books
  union all
  select 'illustrated-books','Illustrated books',20,public_slug from public_books where media_count>0
  union all
  select 'childrens-books','Children''s books',30,public_slug from public_books where lower(coalesce(bibliographic->>'work_type','')) like '%child%'
), shelves as (
  select jsonb_agg(
    jsonb_build_object(
      'shelf_key',s.shelf_key,
      'title',s.shelf_title,
      'book_slugs',(
        select jsonb_agg(sr.public_slug order by pb.released_at desc, sr.public_slug)
        from shelf_rows sr
        join public_books pb on pb.public_slug=sr.public_slug
        where sr.shelf_key=s.shelf_key
      )
    ) order by s.shelf_order
  ) as data
  from (
    select distinct shelf_key,shelf_title,shelf_order from shelf_rows
  ) s
)
select jsonb_build_object(
  'contract_version','wnph_public_library_v1',
  'books',coalesce((select jsonb_agg(book order by released_at desc, public_slug) from public_books),'[]'::jsonb),
  'shelves',coalesce((select data from shelves),'[]'::jsonb)
)
$$;

revoke all on function public.wnph_public_library_v1() from public;
grant execute on function public.wnph_public_library_v1() to anon, authenticated, service_role;