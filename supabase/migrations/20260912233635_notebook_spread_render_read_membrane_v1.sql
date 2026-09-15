begin;

create or replace function atlas.notebook_spread_instance_self_api_v1(p_spread_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_spread atlas.notebook_spread_instances%rowtype;
  v_bindings jsonb := '[]'::jsonb;
  v_latest_revision jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if nullif(btrim(p_spread_key),'') is null then
    raise exception 'spread key is required.' using errcode='22023';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select * into v_spread
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key=btrim(p_spread_key)
  limit 1;

  if v_spread.id is null then
    raise exception 'Notebook spread not found.' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'bindingId',b.id,
      'sourceDomain',b.source_domain,
      'sourceKind',b.source_kind,
      'sourceId',b.source_id,
      'relationshipKind',b.relationship_kind,
      'bindingState',b.binding_state,
      'basis',b.basis,
      'metadata',b.metadata
    ) order by b.created_at,b.id
  ),'[]'::jsonb)
  into v_bindings
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_spread.id
    and b.binding_state='active'
    and b.retired_at is null;

  select jsonb_build_object(
    'revisionNo',r.revision_no,
    'compilerVersion',r.compiler_version,
    'reason',r.reason,
    'contractHash',r.contract_hash,
    'createdAt',r.created_at
  )
  into v_latest_revision
  from atlas.notebook_spread_composition_revisions r
  where r.spread_instance_id=v_spread.id
  order by r.revision_no desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_spread_instance_self_api_v1',
    'spread',jsonb_build_object(
      'spreadInstanceId',v_spread.id,
      'spreadKey',v_spread.spread_key,
      'title',v_spread.title,
      'sectionKey',v_spread.section_key,
      'scope',jsonb_build_object('kind',v_spread.scope_kind,'id',v_spread.scope_id),
      'subject',jsonb_build_object('domain',v_spread.subject_domain,'kind',v_spread.subject_kind,'id',v_spread.subject_id),
      'purposeKey',v_spread.purpose_key,
      'horizonKey',v_spread.horizon_key,
      'threadKey',v_spread.thread_key,
      'creationMode',v_spread.creation_mode,
      'spreadState',v_spread.spread_state,
      'compositionContract',v_spread.composition_contract,
      'openedAt',v_spread.opened_at,
      'closedAt',v_spread.closed_at
    ),
    'sourceBindings',v_bindings,
    'latestCompositionRevision',v_latest_revision,
    'truthBoundary',jsonb_build_object(
      'presentationReadOnly',true,
      'sourceBindingsAreDescriptorsNotCopiedFacts',true,
      'compositionContractOwnsPresentationOnly',true,
      'spreadReadDoesNotGrantSourceAuthority',true,
      'encounterSelectionIsSeparate',true
    )
  );
end;
$function$;

revoke all on function atlas.notebook_spread_instance_self_api_v1(text) from public,anon,authenticated;

create or replace function public.notebook_spread_instance_self_api_v1(p_spread_key text)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_instance_self_api_v1(p_spread_key);
$function$;

revoke all on function public.notebook_spread_instance_self_api_v1(text) from public,anon;
grant execute on function public.notebook_spread_instance_self_api_v1(text) to authenticated,service_role;

commit;