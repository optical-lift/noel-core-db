do $patch$
declare ddl text;
begin
 ddl := pg_get_functiondef('intelligence.get_noel_medical_lab_context_v1(text)'::regprocedure);
 if position($old$and (q='' or (rx is not null and (c.claim_title ~* rx or c.short_claim ~* rx))$old$ in ddl)=0 then raise exception 'Expected anchor not present; no changes made'; end if;
 ddl := replace(ddl,$old$and (q='' or (rx is not null and (c.claim_title ~* rx or c.short_claim ~* rx))$old$,$new$and (q='' or c.claim_key in ('n_med_001_v2','n_med_002_v2','n_med_011_v2','n_med_im_014_v2') or (rx is not null and (c.claim_title ~* rx or c.short_claim ~* rx))$new$);
 execute ddl;
end;
$patch$;