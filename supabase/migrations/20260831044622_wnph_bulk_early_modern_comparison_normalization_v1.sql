create or replace function wnph.normalize_parallel_reading_text_v1(p_text text)
returns text
language sql
immutable
set search_path=pg_catalog,wnph
as $$
  select btrim(regexp_replace(
    replace(replace(lower(translate(coalesce(p_text,''),'ſꝛꝚvj','srrui')),'⁊',' and '),'&',' and '),
    '[^a-z0-9]+',' ','g'
  ));
$$;

comment on function wnph.normalize_parallel_reading_text_v1(text) is
'Comparison-only normalization for parallel historical readings. Maps long-s to s, r-rotunda forms to r, early-modern u/v and i/j interchange to one comparison form, and both tironian/ampersand forms to and. It never rewrites admitted historical text.';