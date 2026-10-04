
    create or replace function instrument.eq_skeleton(vals text[])
    returns text
    language sql
    immutable
    strict
    as $$
      with x as (
        select ord, val,
               min(ord) over(partition by val) first_ord
        from unnest(vals) with ordinality u(val,ord)
      ),
      y as (
        select ord,
               dense_rank() over(order by first_ord,val)::int label
        from x
      )
      select string_agg(label::text,'.' order by ord) from y;
    $$;
  