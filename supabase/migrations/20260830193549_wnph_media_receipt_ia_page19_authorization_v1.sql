create or replace function public.wnph_commit_publication_media_source_receipt_v2(p_request_id uuid, p_token text, p_receipt_key text, p_fetch_uri text, p_media_type text, p_byte_length bigint, p_sha256 text, p_evidence jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','wnph','public'
as $function$
declare
  v_req wnph.publication_media_receipt_requests%rowtype;
  v_p wnph.publication_expression_media_placements%rowtype;
  v_a wnph.publication_source_assets%rowtype;
  v_old wnph.publication_expression_media_source_receipts%rowtype;
  v_id uuid;
  v_expected_uri text;
begin
  if coalesce(p_sha256,'') !~ '^[0-9a-f]{64}$' or coalesce(p_byte_length,0)<=0 or coalesce(p_media_type,'')<>'image/jpeg' then
    raise exception 'WNPH media receipt v2: malformed byte receipt' using errcode='22023';
  end if;
  select * into v_req from wnph.publication_media_receipt_requests where id=p_request_id for update;
  if v_req.id is null or v_req.consumed_at is not null or v_req.expires_at<=now() or v_req.token_sha256<>encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') then
    raise exception 'WNPH media receipt v2 unauthorized, expired, or consumed' using errcode='42501';
  end if;
  select * into v_p from wnph.publication_expression_media_placements
  where id=v_req.placement_id
    and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=publication_expression_media_placements.id);
  select * into v_a from wnph.publication_source_assets
  where id=v_p.source_asset_id
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=publication_source_assets.id);
  if v_p.id is null or v_a.id is null then
    raise exception 'WNPH media receipt v2 lost governed placement or source asset' using errcode='55000';
  end if;

  if p_receipt_key='publication-raster:ia-bookreader-w1600:v1' then
    if v_p.placement_key='dewy:plate:page-9' and v_a.asset_key='dewy:loc:source-surface:0013' then
      v_expected_uri:='https://archive.org/download/wishfairydewydea00colv/page/n12_w1600.jpg';
    elsif v_p.placement_key='dewy:plate:page-19' and v_a.asset_key='dewy:loc:source-surface:0023' then
      v_expected_uri:='https://archive.org/download/wishfairydewydea00colv/page/n22_w1600.jpg';
    else
      raise exception 'WNPH IA raster v1 is not authorized for this Dewy placement/source pair' using errcode='55000';
    end if;
  else
    raise exception 'WNPH media receipt v2 unsupported receipt contract' using errcode='55000';
  end if;

  if p_fetch_uri is distinct from v_expected_uri then
    raise exception 'WNPH media receipt v2 fetch URI outside governed rendition contract' using errcode='55000';
  end if;

  select * into v_old from wnph.publication_expression_media_source_receipts r
  where r.expression_id=v_req.expression_id
    and r.placement_id=v_p.id
    and r.receipt_key=p_receipt_key
    and not exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=r.id)
  order by r.created_at desc limit 1;

  if v_old.id is not null and v_old.sha256=p_sha256 and v_old.byte_length=p_byte_length and v_old.fetch_uri=p_fetch_uri then
    update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id;
    return jsonb_build_object('receipt_id',v_old.id,'action','unchanged','receipt_key',p_receipt_key,'sha256',v_old.sha256,'byte_length',v_old.byte_length);
  end if;

  insert into wnph.publication_expression_media_source_receipts(
    expression_id,placement_id,source_asset_id,receipt_key,fetch_uri,media_type,byte_length,sha256,request_id,evidence,supersedes_receipt_id
  ) values(
    v_req.expression_id,v_p.id,v_a.id,p_receipt_key,p_fetch_uri,p_media_type,p_byte_length,p_sha256,v_req.id,
    coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object(
      'byte_receipt',true,
      'source_asset_key',v_a.asset_key,
      'placement_key',v_p.placement_key,
      'same_surrogate_derivative',true,
      'historical_witness_count_delta',0,
      'source_image_verification_claim',false
    ),v_old.id
  ) returning id into v_id;

  update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id;
  return jsonb_build_object(
    'receipt_id',v_id,
    'action',case when v_old.id is null then 'created' else 'superseded' end,
    'receipt_key',p_receipt_key,
    'sha256',p_sha256,
    'byte_length',p_byte_length,
    'supersedes_receipt_id',v_old.id
  );
end;
$function$;