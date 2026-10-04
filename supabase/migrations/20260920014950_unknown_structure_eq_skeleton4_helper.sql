
    create or replace function instrument.eq_skeleton4(h1 text,h2 text,h3 text,h4 text)
    returns text
    language sql
    immutable
    strict
    as $$
      select
        '1.' ||
        (case when h2=h1 then '1' else '2' end) || '.' ||
        (case
          when h3=h1 then '1'
          when h3=h2 then (case when h2=h1 then '1' else '2' end)
          when h2=h1 then '2'
          else '3'
        end) || '.' ||
        (case
          when h4=h1 then '1'
          when h4=h2 then (case when h2=h1 then '1' else '2' end)
          when h4=h3 then
            (case
              when h3=h1 then '1'
              when h3=h2 then (case when h2=h1 then '1' else '2' end)
              when h2=h1 then '2'
              else '3'
            end)
          else
            (case
              when h2=h1 and h3=h1 then '2'
              when h2=h1 and h3<>h1 then '3'
              when h2<>h1 and (h3=h1 or h3=h2) then '3'
              else '4'
            end)
        end);
    $$;
  