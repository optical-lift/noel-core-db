-- Package 4 / Flower Operations commercial command membrane v1 postcondition.
-- Runs only against the disposable production-schema clone after the candidate migration.

begin;

do $$
declare
  r record;
  v_user uuid:=gen_random_uuid();
  v_failed boolean:=false;
begin
  for r in
    select * from (values
      ('public.record_flower_demand_order_self_api_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)',
       'atlas.record_flower_demand_order_for_member_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)',
       'atlas.record_flower_demand_order_for_member_v1'),
      ('public.commit_flower_demand_order_self_api_v1(uuid,uuid,text,text)',
       'atlas.commit_flower_demand_order_for_member_v1(uuid,uuid,text,text)',
       'atlas.commit_flower_demand_order_for_member_v1'),
      ('public.record_flower_demand_line_price_self_api_v1(uuid,uuid,numeric,text,text,text)',
       'atlas.record_flower_demand_line_price_for_member_v1(uuid,uuid,numeric,text,text,text)',
       'atlas.record_flower_demand_line_price_for_member_v1'),
      ('public.record_flower_demand_allocation_self_api_v1(uuid,uuid,uuid,numeric,text,text)',
       'atlas.record_flower_demand_allocation_for_member_v1(uuid,uuid,uuid,numeric,text,text)',
       'atlas.record_flower_demand_allocation_for_member_v1'),
      ('public.release_flower_demand_allocation_self_api_v1(uuid,uuid,text,text,text)',
       'atlas.release_flower_demand_allocation_for_member_v1(uuid,uuid,text,text,text)',
       'atlas.release_flower_demand_allocation_for_member_v1'),
      ('public.record_flower_sale_from_demand_self_api_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)',
       'atlas.record_flower_sale_from_demand_for_member_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)',
       'atlas.record_flower_sale_from_demand_for_member_v1'),
      ('public.record_flower_sale_self_api_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)',
       'atlas.record_flower_sale_for_member_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)',
       'atlas.record_flower_sale_for_member_v1'),
      ('public.record_flower_fulfillment_self_api_v1(uuid,uuid,text,text)',
       'atlas.record_flower_fulfillment_for_member_v1(uuid,uuid,text,text)',
       'atlas.record_flower_fulfillment_for_member_v1')
    ) as x(public_signature,private_signature,private_target)
  loop
    if to_regprocedure(r.public_signature) is null then
      raise exception 'Missing public commercial command membrane: %',r.public_signature;
    end if;
    if not has_function_privilege('authenticated',r.public_signature,'execute') then
      raise exception 'Authenticated browser caller cannot execute public commercial command: %',r.public_signature;
    end if;
    if has_function_privilege('anon',r.public_signature,'execute') then
      raise exception 'Anonymous caller can execute public commercial command: %',r.public_signature;
    end if;
    if not has_function_privilege('service_role',r.public_signature,'execute') then
      raise exception 'Service role cannot execute public commercial command: %',r.public_signature;
    end if;
    if has_function_privilege('authenticated',r.private_signature,'execute')
       or has_function_privilege('anon',r.private_signature,'execute') then
      raise exception 'Browser caller retained direct atlas command authority: %',r.private_signature;
    end if;
    if not has_function_privilege('service_role',r.private_signature,'execute') then
      raise exception 'Service role lost private atlas command authority: %',r.private_signature;
    end if;
    if not exists (
      select 1
      from pg_catalog.pg_proc p
      where p.oid=to_regprocedure(r.public_signature)
        and p.prosecdef=true
        and p.provolatile='v'
        and p.proconfig=array['search_path=pg_catalog']::text[]
        and position(r.private_target in p.prosrc)>0
    ) then
      raise exception 'Public command is not a fixed volatile SECURITY DEFINER delegate to %',r.private_target;
    end if;
  end loop;

  -- Prove the public membrane preserves caller authority rather than inheriting
  -- the definer's farm authority. No fixture commercial truth is created.
  insert into auth.users(id) values(v_user);
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  begin
    perform public.commit_flower_demand_order_self_api_v1(
      gen_random_uuid(),gen_random_uuid(),null,'clone-authority-proof-'||gen_random_uuid()::text
    );
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Commercial command membrane did not preserve caller farm-membership enforcement.';
  end if;
end;
$$;

rollback;
