begin;

-- Structural acceptance proof for the Position -> Responsibility definition command.
-- Execute after installing the candidate in a disposable production-schema clone.

do $validation$
declare
  v_preview oid:=to_regprocedure('atlas.preview_implementation_reality_position_responsibility_definition_v1(uuid)');
  v_promote oid:=to_regprocedure('atlas.promote_implementation_reality_position_responsibility_definition_v1(uuid)');
  v_establish oid:=to_regprocedure('atlas.establish_position_responsibility_definition_from_reality_v1(uuid,uuid,jsonb)');
  v_render oid:=to_regprocedure('atlas.render_organization_position_responsibility_definition_v1(uuid,uuid)');
  v_public_preview oid:=to_regprocedure('public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid)');
  v_public_promote oid:=to_regprocedure('public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid)');
  v_preview_source text;
  v_promote_source text;
  v_establish_source text;
begin
  if v_preview is null or v_promote is null or v_establish is null or v_render is null
     or v_public_preview is null or v_public_promote is null then
    raise exception 'Position Responsibility definition command surface is incomplete.';
  end if;

  select pg_get_functiondef(v_preview) into v_preview_source;
  select pg_get_functiondef(v_promote) into v_promote_source;
  select pg_get_functiondef(v_establish) into v_establish_source;

  if position('position_responsibility_definition.establish' in v_preview_source)=0 then
    raise exception 'Preview is not pinned to the admitted operation.';
  end if;
  if position('relationshipKind' in v_preview_source)=0
     or position('accountable' in v_preview_source)=0 then
    raise exception 'Operation semantics must explicitly establish accountable Position responsibility.';
  end if;
  if position('position.organization_id' in replace(v_preview_source,'v_',''))>0 then
    null;
  end if;
  if position('v_position.organization_id<>v_organization_id' in v_preview_source)=0
     or position('v_responsibility.organization_id<>v_organization_id' in v_preview_source)=0 then
    raise exception 'Preview must require Position, Responsibility, and context Organization to share scope.';
  end if;
  if position('principal_has_ledger_authority_v1' in v_preview_source)=0
     or position('setup_sponsor' in v_preview_source)=0 then
    raise exception 'Preview must preserve verified setup-sponsor ledger authority.';
  end if;
  if position('establishment_basis_required' in v_preview_source)=0 then
    raise exception 'Preview must require governed establishment basis.';
  end if;
  if position('canonical_relation_exists' in v_preview_source)=0 then
    raise exception 'Preview must recognize an already-established canonical relation.';
  end if;

  if position('insert into atlas.organization_position_responsibilities' in lower(v_establish_source))=0 then
    raise exception 'Establishment service does not write the canonical Position Responsibility carrier.';
  end if;
  if position('on conflict (position_id,responsibility_id) do nothing' in lower(v_establish_source))=0 then
    raise exception 'Establishment service must remain idempotent at the canonical pair boundary.';
  end if;
  if position('relationship_kind' in lower(v_establish_source))=0
     or position('accountable' in lower(v_establish_source))=0 then
    raise exception 'Establishment service must preserve accountable semantics.';
  end if;

  if position('candidate_state=''promoted''' in v_promote_source)=0
     or position('canonical_consequence_kind=''organization_position_responsibility_definition''' in v_promote_source)=0
     or position('promotionReceipt' in v_promote_source)=0 then
    raise exception 'Promotion must bind candidate custody to the durable canonical consequence and receipt.';
  end if;

  if has_function_privilege('anon','public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid)','EXECUTE') then
    raise exception 'anon must not execute Position Responsibility definition commands.';
  end if;
  if not has_function_privilege('authenticated','public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid)','EXECUTE') then
    raise exception 'authenticated must execute the public Position Responsibility definition membranes.';
  end if;
  if has_function_privilege('authenticated','atlas.preview_implementation_reality_position_responsibility_definition_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.promote_implementation_reality_position_responsibility_definition_v1(uuid)','EXECUTE') then
    raise exception 'authenticated must not bypass public membranes to internal command functions.';
  end if;

  if not exists(select 1 from pg_proc where oid=v_preview and provolatile='s' and prosecdef) then
    raise exception 'Preview must be STABLE SECURITY DEFINER.';
  end if;
  if not exists(select 1 from pg_proc where oid=v_promote and prosecdef) then
    raise exception 'Promotion must be SECURITY DEFINER.';
  end if;
end;
$validation$;

rollback;
