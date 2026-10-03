create or replace function public.v46_fetch_cipher_token_20260908(p_token text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, instrument
as $$
begin
  if p_token is distinct from '0fcd53368c78de4c066ae3a002412b796b614b138e41d3c31c03ff5873df09c6' then
    raise exception 'not authorized';
  end if;
  return public.v46_fetch_cipher_20260907();
end;
$$;
revoke all on function public.v46_fetch_cipher_token_20260908(text) from public, authenticated;
grant execute on function public.v46_fetch_cipher_token_20260908(text) to anon;