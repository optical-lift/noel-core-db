do $patch$
declare
  v_def text;
  v_old text := $old$if coalesce(v_ws.text_candidate,'') ~ '(\{\||\|-|rowspan|colspan|style=|\[\[Page:)' then v_risks:=v_risks||'"unresolved_transcription_markup"'::jsonb; end if;$old$;
  v_new text := $new$if coalesce(v_ws.text_candidate,'') ~ '(\{\||\|-|rowspan|colspan|style=|\[\[Page:|[{}])' then v_risks:=v_risks||'"unresolved_transcription_markup"'::jsonb; end if;$new$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='wnph' and p.proname='run_bulk_parallel_reconstruction_v1';
  if position(v_old in v_def)=0 then raise exception 'WNPH human-parallel markup guard: runner patch target not found'; end if;
  execute replace(v_def,v_old,v_new);
end;
$patch$;