create or replace function atlas.production_next_propagation_operation_v1(p_crop_profile_id uuid, p_after_stage text)
returns table(stage_key text, stage_order integer, timing_min_days integer, timing_max_days integer, rule_payload jsonb, contract_source text)
language sql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
  with boundary as (
    select case lower(coalesce(p_after_stage,''))
      when 'germination' then 30
      when 'seedling_care' then 40
      when 'pot_up' then 50
      when 'grow_out' then 60
      when 'harden' then 70
      else 0 end as stage_order
  ), candidates as (
    select c.*,
           case
             when c.stage_key='harden'
                  and lower(coalesce(p_after_stage,'')) in ('pot_up','grow_out')
                  and c.disposition='conditional'
               then 'required'
             else c.disposition
           end as effective_disposition
    from atlas.v_crop_lifecycle_contract_v1 c, boundary b
    where c.crop_profile_id=p_crop_profile_id
      and c.stage_order>b.stage_order
      and c.stage_key in ('pot_up','grow_out','harden','transplant')
      and (
        c.disposition='unknown'
        or (c.stage_key in ('pot_up','harden','transplant') and c.disposition='required')
        or (c.stage_key='harden'
            and lower(coalesce(p_after_stage,'')) in ('pot_up','grow_out')
            and c.disposition='conditional')
      )
  ), first_blocking as (
    select * from candidates order by stage_order limit 1
  )
  select f.stage_key,f.stage_order,f.timing_min_days,f.timing_max_days,
         coalesce(f.rule_payload,'{}'::jsonb)||jsonb_build_object('_disposition',f.effective_disposition,'_pathPromotion',
           case when f.disposition='conditional' and f.effective_disposition='required' then 'actual_upstream_stage_selected' else null end),
         case when f.disposition='conditional' and f.effective_disposition='required' then 'actual_path_state' else f.contract_source end
  from first_blocking f
  where f.effective_disposition='required';
$function$;