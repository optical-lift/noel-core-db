do $$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='wnph' and p.proname='harvest_parallel_reading_evidence_v1';
  v_old:='v_api:=''https://en.wikisource.org/w/api.php?action=parse&page=''||extensions.urlencode((''Page:''||p_wikisource_file_title||''/''||v_page)::varchar)||''&prop=wikitext&format=json&formatversion=2'';
    v_resp:=wnph.http_get_with_retry_v1(v_api,5,750);
    if v_resp.status<>200 then raise exception ''WNPH parallel harvest: Wikisource page % returned %'',v_page,v_resp.status; end if;
    v_j:=v_resp.content::jsonb; v_raw:=v_j#>>''{parse,wikitext}'';
    if v_raw is null then raise exception ''WNPH parallel harvest: Wikisource page % lacked wikitext'',v_page; end if;';
  v_new:='v_api:=''https://en.wikisource.org/w/index.php?title=''||extensions.urlencode((''Page:''||p_wikisource_file_title||''/''||v_page)::varchar)||''&action=raw'';
    v_resp:=wnph.http_get_with_retry_v1(v_api,5,750);
    if v_resp.status<>200 then raise exception ''WNPH parallel harvest: Wikisource raw page % returned %'',v_page,v_resp.status; end if;
    v_raw:=v_resp.content;
    if v_raw is null or btrim(v_raw)='''' then raise exception ''WNPH parallel harvest: Wikisource raw page % lacked wikitext'',v_page; end if;';
  if position(v_old in v_def)=0 then raise exception 'WNPH Wikisource raw transport patch target not found'; end if;
  execute replace(v_def,v_old,v_new);
end;
$$;