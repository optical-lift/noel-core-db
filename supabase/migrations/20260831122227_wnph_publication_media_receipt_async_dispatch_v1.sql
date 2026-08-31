create or replace function public.wnph_enqueue_publication_media_receipt_fetch_v1(
  p_expression_key text,
  p_placement_key text,
  p_rendition text default 'ia-w1600'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public','net','extensions'
as $$
declare
  v_expr uuid;
  v_placement uuid;
  v_token text;
  v_request_id uuid;
  v_exp timestamptz;
  v_net_request_id bigint;
begin
  select id into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr is null then raise exception 'WNPH async media receipt: Expression not found' using errcode='P0002'; end if;

  select p.id into v_placement
  from wnph.publication_expression_media_placements p
  where p.expression_id=v_expr
    and p.placement_key=p_placement_key
    and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id)
  order by p.created_at desc limit 1;
  if v_placement is null then raise exception 'WNPH async media receipt: active placement not found' using errcode='P0002'; end if;

  if p_rendition <> 'ia-w1600' then raise exception 'WNPH async media receipt: unsupported rendition' using errcode='22023'; end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '5 minutes';
  insert into wnph.publication_media_receipt_requests(expression_id,placement_id,token_sha256,expires_at)
  values(v_expr,v_placement,encode(extensions.digest(v_token,'sha256'),'hex'),v_exp)
  returning id into v_request_id;

  select net.http_get(
    url := 'https://zirqkouammpwxlqfbsvf.supabase.co/functions/v1/wnph-publication-media-receipt',
    params := jsonb_build_object('request_id',v_request_id::text,'token',v_token,'rendition',p_rendition),
    headers := '{}'::jsonb,
    timeout_milliseconds := 30000
  ) into v_net_request_id;

  return jsonb_build_object(
    'request_id',v_request_id,
    'net_request_id',v_net_request_id,
    'expression_key',p_expression_key,
    'placement_key',p_placement_key,
    'rendition',p_rendition,
    'expires_at',v_exp
  );
end;
$$;

revoke all on function public.wnph_enqueue_publication_media_receipt_fetch_v1(text,text,text) from public,anon,authenticated;
grant execute on function public.wnph_enqueue_publication_media_receipt_fetch_v1(text,text,text) to service_role;