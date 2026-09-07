-- Atlas Company Work retrieval API v1
-- Server-only governed read contract over atlas.company_work_ledger_v1.

begin;

create or replace function atlas.get_company_work_v1(
  p_organization_id uuid,
  p_responsibility_user_id uuid default null,
  p_responsibility_positions text[] default null,
  p_work_states text[] default null,
  p_management_positions text[] default null,
  p_operation_classes text[] default null,
  p_organization_unit_ids uuid[] default null,
  p_planning_positions text[] default null,
  p_time_lens text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_timezone_name text default null,
  p_search_text text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns setof atlas.company_work_ledger_v1
language plpgsql
stable
security invoker
set search_path = pg_catalog, atlas
as $$
declare
  v_timezone text;
  v_limit integer := least(greatest(coalesce(p_limit,100),1),500);
  v_offset integer := greatest(coalesce(p_offset,0),0);
begin
  if p_organization_id is null then
    raise exception 'p_organization_id is required';
  end if;

  if p_responsibility_positions is not null
     and exists (
       select 1 from unnest(p_responsibility_positions) x
       where x not in ('allocated','unresolved_named','unassigned')
     ) then
    raise exception 'invalid responsibility position';
  end if;

  if p_planning_positions is not null
     and exists (
       select 1 from unnest(p_planning_positions) x
       where x not in ('planned','unscheduled','conflict','waiting_dependency')
     ) then
    raise exception 'invalid planning position';
  end if;

  if p_time_lens is not null
     and p_time_lens not in (
       'overdue','hard_missed','planned_range','preferred_range',
       'latest_lawful_range','hard_finish_range'
     ) then
    raise exception 'invalid time lens';
  end if;

  if p_time_lens in ('preferred_range','latest_lawful_range','hard_finish_range') then
    if p_timezone_name is null then
      raise exception 'p_timezone_name is required for timestamp date-range lenses';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name=p_timezone_name) then
      raise exception 'invalid timezone name';
    end if;
    v_timezone := p_timezone_name;
  else
    v_timezone := coalesce(p_timezone_name,'UTC');
  end if;

  return query
  select l.*
  from atlas.company_work_ledger_v1 l
  where l.organization_id=p_organization_id
    and (p_responsibility_user_id is null or l.responsibility_user_id=p_responsibility_user_id)
    and (p_responsibility_positions is null or l.responsibility_position=any(p_responsibility_positions))
    and (p_work_states is null or l.work_state=any(p_work_states))
    and (p_management_positions is null or l.management_position=any(p_management_positions))
    and (p_operation_classes is null or l.operation_class=any(p_operation_classes))
    and (p_organization_unit_ids is null or l.organization_unit_id=any(p_organization_unit_ids))
    and (
      p_planning_positions is null
      or ('planned'=any(p_planning_positions) and l.is_planned)
      or ('unscheduled'=any(p_planning_positions) and l.is_unscheduled)
      or ('conflict'=any(p_planning_positions) and l.has_planning_conflict)
      or ('waiting_dependency'=any(p_planning_positions) and l.is_waiting_dependency)
    )
    and (
      p_time_lens is null
      or (p_time_lens='overdue' and l.is_overdue)
      or (p_time_lens='hard_missed' and l.is_hard_finish_missed)
      or (
        p_time_lens='planned_range'
        and l.planned_service_date is not null
        and (p_start_date is null or l.planned_service_date>=p_start_date)
        and (p_end_date is null or l.planned_service_date<=p_end_date)
      )
      or (
        p_time_lens='preferred_range'
        and l.preferred_end_at is not null
        and (p_start_date is null or (l.preferred_end_at at time zone v_timezone)::date>=p_start_date)
        and (p_end_date is null or (l.preferred_end_at at time zone v_timezone)::date<=p_end_date)
      )
      or (
        p_time_lens='latest_lawful_range'
        and l.latest_lawful_at is not null
        and (p_start_date is null or (l.latest_lawful_at at time zone v_timezone)::date>=p_start_date)
        and (p_end_date is null or (l.latest_lawful_at at time zone v_timezone)::date<=p_end_date)
      )
      or (
        p_time_lens='hard_finish_range'
        and l.hard_finish_at is not null
        and (p_start_date is null or (l.hard_finish_at at time zone v_timezone)::date>=p_start_date)
        and (p_end_date is null or (l.hard_finish_at at time zone v_timezone)::date<=p_end_date)
      )
    )
    and (
      nullif(btrim(p_search_text),'') is null
      or l.title ilike '%'||btrim(p_search_text)||'%'
      or coalesce(l.instructions,'') ilike '%'||btrim(p_search_text)||'%'
      or coalesce(l.responsibility_display_name,'') ilike '%'||btrim(p_search_text)||'%'
      or coalesce(l.organization_unit_name,'') ilike '%'||btrim(p_search_text)||'%'
      or coalesce(l.operation_class,'') ilike '%'||btrim(p_search_text)||'%'
    )
  order by
    case when l.work_state='open' then 0 else 1 end,
    l.planned_service_date nulls last,
    l.preferred_end_at nulls last,
    l.title,
    l.work_item_id
  limit v_limit
  offset v_offset;
end;
$$;

comment on function atlas.get_company_work_v1(
  uuid,uuid,text[],text[],text[],text[],uuid[],text[],text,date,date,text,text,integer,integer
) is
  'Governed server-side Company Work retrieval. Filters one canonical Company Work Ledger population; responsibility person includes both allocated and unresolved_named work. Timestamp-to-date lenses require explicit timezone.';

revoke all on function atlas.get_company_work_v1(
  uuid,uuid,text[],text[],text[],text[],uuid[],text[],text,date,date,text,text,integer,integer
) from public, anon, authenticated;
grant execute on function atlas.get_company_work_v1(
  uuid,uuid,text[],text[],text[],text[],uuid[],text[],text,date,date,text,text,integer,integer
) to service_role;

revoke all on atlas.company_work_ledger_v1 from public, anon, authenticated;
grant select on atlas.company_work_ledger_v1 to service_role;

revoke all on atlas.legacy_company_work_canonicalization_audit_v1 from public, anon, authenticated;
grant select on atlas.legacy_company_work_canonicalization_audit_v1 to service_role;

commit;
