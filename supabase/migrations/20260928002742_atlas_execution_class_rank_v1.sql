create or replace function atlas.execution_class_rank_v1(p_execution_class text)
returns integer
language sql
immutable
strict
as $$
  select case p_execution_class
    when 'read' then 1
    when 'prepare' then 2
    when 'commit' then 3
    else 99
  end;
$$;