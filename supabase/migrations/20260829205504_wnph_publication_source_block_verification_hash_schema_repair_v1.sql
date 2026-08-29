do $migration$
declare
  r record;
  v_definition text;
begin
  for r in
    select p.oid,n.nspname,p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname,p.proname) in (
      ('wnph','validate_publication_source_block_verification_v1'),
      ('public','wnph_source_block_verification_packet_v1'),
      ('public','wnph_record_source_block_verification_v1'),
      ('public','wnph_admit_verified_source_block_v1')
    )
  loop
    v_definition:=pg_get_functiondef(r.oid);
    if position('digest(' in v_definition)=0 then
      raise exception 'WNPH verification hash repair: expected digest call missing from %.%',r.nspname,r.proname;
    end if;
    execute replace(v_definition,'digest(','extensions.digest(');
  end loop;
end;
$migration$;