do $patch$ declare ddl text; begin
ddl:=pg_get_functiondef('intelligence.get_noel_medical_lab_context_v1(text)'::regprocedure);
if position($old$q text := lower(btrim(coalesce(p_topic,'')));$old$ in ddl)=0 then raise exception 'Expected topic normalizer missing'; end if;
execute replace(ddl,$old$q text := lower(btrim(coalesce(p_topic,'')));$old$,$new$q text := case when lower(btrim(coalesce(p_topic,''))) ~ '^(interospection|medical lab|medical framework|all|overview)$' then '' else lower(btrim(coalesce(p_topic,''))) end;$new$);
end $patch$;