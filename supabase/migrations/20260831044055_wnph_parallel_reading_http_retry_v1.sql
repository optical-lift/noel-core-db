create or replace function wnph.http_get_with_retry_v1(p_uri text,p_max_attempts integer default 5,p_initial_delay_ms integer default 750)
returns extensions.http_response
language plpgsql
volatile
set search_path=pg_catalog,wnph,extensions
as $$
declare
  v_response extensions.http_response;
  v_attempt integer:=0;
  v_delay numeric:=greatest(0,p_initial_delay_ms)::numeric/1000;
begin
  if p_max_attempts<1 or p_max_attempts>8 then raise exception 'WNPH HTTP retry attempts must be 1..8'; end if;
  loop
    v_attempt:=v_attempt+1;
    v_response:=extensions.http_get(p_uri::varchar);
    if v_response.status<>429 and v_response.status<500 then return v_response; end if;
    if v_attempt>=p_max_attempts then return v_response; end if;
    perform pg_sleep(v_delay);
    v_delay:=least(v_delay*2,6);
  end loop;
end;
$$;

do $$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='wnph' and p.proname='harvest_parallel_reading_evidence_v1';
  v_old:='v_resp:=extensions.http_get(v_api::varchar);';
  v_new:='v_resp:=wnph.http_get_with_retry_v1(v_api,5,750);';
  if position(v_old in v_def)=0 then raise exception 'WNPH retry patch target not found in harvester definition'; end if;
  execute replace(v_def,v_old,v_new);
end;
$$;

revoke execute on function wnph.http_get_with_retry_v1(text,integer,integer) from public,anon,authenticated;