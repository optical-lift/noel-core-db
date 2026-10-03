create or replace function public.v46_fetch_cipher_20260907()
returns text
language sql
security definer
set search_path = pg_catalog, public, instrument
as $$
  select replace(encode(blob,'base64'), E'\n','')
  from instrument.v46_transfer_cipher_20260907
  where id=1;
$$;
revoke all on function public.v46_fetch_cipher_20260907() from public, anon, authenticated;
grant execute on function public.v46_fetch_cipher_20260907() to service_role;