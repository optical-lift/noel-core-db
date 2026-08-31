create unique index if not exists publication_manifestation_derivations_one_root_per_expression_profile_manifestation_uidx
on wnph.publication_manifestation_derivations(publication_expression_id,render_profile_id,manifestation_id)
where supersedes_derivation_id is null and publication_expression_id is not null;

create unique index if not exists publication_manifestation_derivations_one_child_uidx
on wnph.publication_manifestation_derivations(supersedes_derivation_id)
where supersedes_derivation_id is not null;

create or replace function public.wnph_refresh_expression_manifestation_derivations_v1(p_expression_key text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_expression wnph.expressions%rowtype;
  v_snapshot jsonb;
  v_current_hash text;
  v_old record;
  v_new_id uuid;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  select * into v_expression from wnph.expressions where canonical_key=p_expression_key;
  if v_expression.id is null then
    raise exception 'WNPH manifestation fanout: Expression not found' using errcode='P0002';
  end if;

  v_snapshot:=public.wnph_publication_expression_snapshot_v1(p_expression_key);
  v_current_hash:=v_snapshot->>'render_master_sha256';
  if coalesce(v_current_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'WNPH manifestation fanout: Expression snapshot hash missing or malformed' using errcode='55000';
  end if;

  for v_old in
    select d.*,r.canonical_key as render_profile_key,r.output_family,m.canonical_key as manifestation_key
    from wnph.publication_manifestation_derivations d
    join wnph.publication_render_profiles r on r.id=d.render_profile_id
    join wnph.manifestations m on m.id=d.manifestation_id
    where d.publication_expression_id=v_expression.id
      and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id)
    order by r.canonical_key,m.canonical_key
  loop
    v_count:=v_count+1;
    if coalesce(v_old.build_metadata->'master_snapshot'->>'render_master_sha256','')=v_current_hash then
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'render_profile_key',v_old.render_profile_key,
        'manifestation_key',v_old.manifestation_key,
        'derivation_id',v_old.id,
        'action','unchanged',
        'render_master_sha256',v_current_hash
      ));
    else
      insert into wnph.publication_manifestation_derivations(
        source_package_id,publication_expression_id,render_profile_id,manifestation_id,
        derivation_status,build_metadata,supersedes_derivation_id
      ) values(
        null,v_expression.id,v_old.render_profile_id,v_old.manifestation_id,
        'planned',
        coalesce(v_old.build_metadata,'{}'::jsonb)||jsonb_build_object(
          'master_snapshot',v_snapshot,
          'master_authority','publication_expression',
          'source_image_verification_is_parallel_not_blocking',true,
          'fanout_contract','wnph_refresh_expression_manifestation_derivations_v1',
          'output_family',v_old.output_family,
          'supersession_reason','publication_expression_snapshot_changed',
          'previous_render_master_sha256',v_old.build_metadata->'master_snapshot'->>'render_master_sha256',
          'refreshed_at',now()
        ),
        v_old.id
      ) returning id into v_new_id;

      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'render_profile_key',v_old.render_profile_key,
        'manifestation_key',v_old.manifestation_key,
        'derivation_id',v_new_id,
        'supersedes_derivation_id',v_old.id,
        'action','superseded_to_current_snapshot',
        'render_master_sha256',v_current_hash
      ));
    end if;
  end loop;

  if v_count=0 then
    raise exception 'WNPH manifestation fanout: no active manifestation derivations are attached to Expression %',p_expression_key using errcode='P0002';
  end if;

  return jsonb_build_object(
    'contract_version','wnph_refresh_expression_manifestation_derivations_v1',
    'expression_key',p_expression_key,
    'master_snapshot',v_snapshot,
    'manifestation_count',v_count,
    'results',v_results
  );
end;
$$;

revoke all on function public.wnph_refresh_expression_manifestation_derivations_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_refresh_expression_manifestation_derivations_v1(text) to service_role;

comment on function public.wnph_refresh_expression_manifestation_derivations_v1(text) is 'Atomically fans one current Publication Expression snapshot out to every attached active Manifestation derivation by append-only supersession. A single Expression edit therefore advances paperback, print PDF, EPUB, web, and future render profiles together without rewriting historical derivations.';

do $block$
begin
  perform public.wnph_refresh_expression_manifestation_derivations_v1('wish-fairy-dewy-dear:wnph-publication-e1');
end;
$block$;