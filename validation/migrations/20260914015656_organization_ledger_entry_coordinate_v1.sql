-- Behavioral postconditions for Organization Ledger entry coordinate v1.
-- Run only in a disposable production-schema clone after fixture + candidate.

do $proof$
declare
  owner_uid constant uuid := 'c2100000-0000-4000-8000-000000000001'::uuid;
  outsider_uid constant uuid := 'c2100000-0000-4000-8000-000000000099'::uuid;
  organization_id constant uuid := 'c2400000-0000-4000-8000-000000000001'::uuid;
  ledger_id constant uuid := 'c2200000-0000-4000-8000-000000000001'::uuid;
  entry_id constant uuid := 'c2500000-0000-4000-8000-000000000001'::uuid;
  v_result jsonb;
  v_item jsonb;
  v_failed boolean;
begin
  if has_function_privilege('anon','atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer)','EXECUTE') then
    raise exception 'Anon retained Organization Ledger owner-window execution.';
  end if;
  if not has_function_privilege('authenticated','atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer)','EXECUTE') then
    raise exception 'Authenticated lost Organization Ledger owner-window execution.';
  end if;

  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_result:=atlas.organization_ledger_owner_window_api_v1(
    organization_id,
    '2026-09-13 19:00:00-05'::timestamptz,
    '2026-09-13 21:00:00-05'::timestamptz,
    0,
    50
  );

  if v_result->>'contractVersion'<>'organization_ledger_owner_window_api_v1'
     or (v_result->>'organizationId')::uuid<>organization_id then
    raise exception 'Organization Ledger window contract identity changed unexpectedly: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'items','[]'::jsonb))<>1 then
    raise exception 'Coordinate proof window did not return exactly one fixture entry: %',v_result;
  end if;

  v_item:=(v_result->'items')->0;
  if (v_item->>'entryId')::uuid<>entry_id then
    raise exception 'Organization Ledger entry identity was not preserved: %',v_item;
  end if;
  if (v_item->>'ledgerId')::uuid<>ledger_id then
    raise exception 'Organization Ledger governing Ledger coordinate was absent or incorrect: %',v_item;
  end if;
  if v_item->>'title'<>'Coordinate proof entry'
     or v_item->>'semanticType'<>'coordinate_proof' then
    raise exception 'Existing owner-window item semantics changed while adding the Ledger coordinate: %',v_item;
  end if;

  perform set_config('request.jwt.claim.sub',outsider_uid::text,true);
  v_failed:=false;
  begin
    perform atlas.organization_ledger_owner_window_api_v1(
      organization_id,
      '2026-09-13 19:00:00-05'::timestamptz,
      '2026-09-13 21:00:00-05'::timestamptz,
      0,
      50
    );
  exception when sqlstate '42501' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Organization owner membrane weakened while adding the Ledger coordinate.';
  end if;
end;
$proof$;
