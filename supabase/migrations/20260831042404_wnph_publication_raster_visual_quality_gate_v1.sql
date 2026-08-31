create table if not exists wnph.publication_media_raster_quality_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  receipt_id uuid not null references wnph.publication_expression_media_source_receipts(id),
  review_status text not null check (review_status in ('accepted','rejected')),
  review_method text not null,
  rendition_width_px integer null check (rendition_width_px is null or rendition_width_px > 0),
  rendition_height_px integer null check (rendition_height_px is null or rendition_height_px > 0),
  findings jsonb not null default '{}'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  supersedes_review_id uuid null references wnph.publication_media_raster_quality_reviews(id),
  created_at timestamptz not null default now(),
  constraint publication_media_raster_quality_reviews_supersedes_uk unique(supersedes_review_id)
);

revoke all on wnph.publication_media_raster_quality_reviews from anon, authenticated;
grant select on wnph.publication_media_raster_quality_reviews to service_role;

create index if not exists publication_media_raster_quality_reviews_receipt_idx
  on wnph.publication_media_raster_quality_reviews(receipt_id, created_at desc);

create or replace function wnph.guard_publication_media_raster_quality_review_v1()
returns trigger language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare
  v_old wnph.publication_media_raster_quality_reviews%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception 'WNPH raster quality reviews are append-only; supersede explicitly' using errcode='55000';
  end if;
  if new.supersedes_review_id is null then
    if exists(
      select 1 from wnph.publication_media_raster_quality_reviews q
      where q.receipt_id=new.receipt_id
        and not exists(select 1 from wnph.publication_media_raster_quality_reviews c where c.supersedes_review_id=q.id)
    ) then
      raise exception 'WNPH raster quality review requires explicit supersession' using errcode='55000';
    end if;
  else
    select * into v_old from wnph.publication_media_raster_quality_reviews where id=new.supersedes_review_id;
    if v_old.id is null or v_old.receipt_id<>new.receipt_id then
      raise exception 'WNPH raster quality review supersession cannot cross receipt' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_media_raster_quality_reviews c where c.supersedes_review_id=v_old.id) then
      raise exception 'WNPH raster quality review supersession target is no longer active' using errcode='55000';
    end if;
  end if;
  return new;
end;$$;

drop trigger if exists trg_guard_publication_media_raster_quality_review_v1 on wnph.publication_media_raster_quality_reviews;
create trigger trg_guard_publication_media_raster_quality_review_v1
before insert or update or delete on wnph.publication_media_raster_quality_reviews
for each row execute function wnph.guard_publication_media_raster_quality_review_v1();

insert into wnph.publication_media_raster_quality_reviews(
  receipt_id,review_status,review_method,rendition_width_px,findings,evidence
)
select
  r.id,
  case when p.placement_key in ('dewy:plate:page-9','dewy:plate:page-19') then 'accepted' else 'rejected' end,
  'publication_visual_defect_audit_2026_08_30',
  coalesce(nullif(r.evidence->>'rendition_width_px','')::integer,nullif(r.evidence->>'rendition_width_request_px','')::integer),
  case
    when p.placement_key in ('dewy:plate:page-9','dewy:plate:page-19') then jsonb_build_object(
      'sharpness','accepted',
      'reason','same-surrogate Internet Archive BookReader replacement is the known sharp publication rendition'
    )
    else jsonb_build_object(
      'sharpness','rejected',
      'defect','publication_derivative_softness',
      'reason','remaining Dewy chapter plate visibly soft while using the lightweight LOC full/1800 JPEG derivative'
    )
  end,
  jsonb_build_object(
    'placement_key',p.placement_key,
    'receipt_key',r.receipt_key,
    'byte_length',r.byte_length,
    'fetch_uri',r.fetch_uri,
    'historical_witness_count_delta',0,
    'source_provenance_status','unchanged'
  )
from wnph.publication_expression_media_placements p
join wnph.publication_expression_media_raster_selections s on s.placement_id=p.id
  and not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id)
join wnph.publication_expression_media_source_receipts r on r.id=s.receipt_id
where p.placement_key in (
  'dewy:plate:page-9','dewy:plate:page-19',
  'dewy:plate:page-29','dewy:plate:page-37','dewy:plate:page-47','dewy:plate:page-55'
)
and not exists(
  select 1 from wnph.publication_media_raster_quality_reviews q
  where q.receipt_id=r.id
    and not exists(select 1 from wnph.publication_media_raster_quality_reviews c where c.supersedes_review_id=q.id)
);

create or replace function wnph.guard_publication_media_raster_selection_v1()
returns trigger language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare
  v_r wnph.publication_expression_media_source_receipts%rowtype;
  v_old wnph.publication_expression_media_raster_selections%rowtype;
  v_q wnph.publication_media_raster_quality_reviews%rowtype;
begin
  if tg_op <> 'INSERT' then raise exception 'WNPH raster selections are append-only' using errcode='55000'; end if;
  select * into v_r from wnph.publication_expression_media_source_receipts where id=new.receipt_id;
  if v_r.id is null or v_r.expression_id<>new.expression_id or v_r.placement_id<>new.placement_id then
    raise exception 'WNPH raster selection receipt must match Expression and placement' using errcode='55000';
  end if;
  if exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=v_r.id) then
    raise exception 'WNPH raster selection cannot select a superseded receipt' using errcode='55000';
  end if;

  select * into v_q
  from wnph.publication_media_raster_quality_reviews q
  where q.receipt_id=v_r.id
    and not exists(select 1 from wnph.publication_media_raster_quality_reviews c where c.supersedes_review_id=q.id)
  order by q.created_at desc
  limit 1;

  if v_q.id is null then
    raise exception 'WNPH raster selection requires an explicit visual-quality review' using errcode='55000';
  end if;
  if v_q.review_status <> 'accepted' then
    raise exception 'WNPH raster selection cannot publish a raster rejected for visual quality' using errcode='55000';
  end if;

  if new.supersedes_selection_id is null then
    if exists(select 1 from wnph.publication_expression_media_raster_selections s where s.expression_id=new.expression_id and s.placement_id=new.placement_id and not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id)) then
      raise exception 'WNPH raster selection requires explicit supersession' using errcode='55000';
    end if;
  else
    select * into v_old from wnph.publication_expression_media_raster_selections where id=new.supersedes_selection_id;
    if v_old.id is null or v_old.expression_id<>new.expression_id or v_old.placement_id<>new.placement_id then
      raise exception 'WNPH raster selection supersession cannot cross Expression or placement' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=v_old.id) then
      raise exception 'WNPH raster selection supersession target is no longer active' using errcode='55000';
    end if;
  end if;

  new.selection_reason := coalesce(new.selection_reason,'{}'::jsonb) || jsonb_build_object(
    'visual_quality_gate','publication_media_raster_quality_review_v1',
    'visual_quality_review_id',v_q.id::text,
    'visual_quality_review_status',v_q.review_status
  );
  return new;
end;$$;

create or replace view public.v_wnph_selected_publication_raster_quality_v1 as
with active_selections as (
  select s.* from wnph.publication_expression_media_raster_selections s
  where not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id)
), active_reviews as (
  select q.* from wnph.publication_media_raster_quality_reviews q
  where not exists(select 1 from wnph.publication_media_raster_quality_reviews c where c.supersedes_review_id=q.id)
)
select
  e.canonical_key as expression_key,
  p.placement_key,
  p.media_role,
  r.id as receipt_id,
  r.receipt_key,
  r.fetch_uri,
  r.byte_length,
  q.id as quality_review_id,
  coalesce(q.review_status,'unreviewed') as quality_status,
  q.review_method,
  q.rendition_width_px,
  q.rendition_height_px,
  q.findings,
  q.evidence
from active_selections s
join wnph.publication_expression_media_placements p on p.id=s.placement_id
join wnph.expressions e on e.id=s.expression_id
join wnph.publication_expression_media_source_receipts r on r.id=s.receipt_id
left join active_reviews q on q.receipt_id=r.id;

revoke all on public.v_wnph_selected_publication_raster_quality_v1 from anon,authenticated;
grant select on public.v_wnph_selected_publication_raster_quality_v1 to service_role;