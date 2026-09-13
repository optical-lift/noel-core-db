-- Canonical behavioral postconditions for Atlas Ledger Graph v1.
-- Runs only in the disposable production-schema clone after fixture + candidate migration.

do $proof$
declare
  p1 constant uuid := '11111111-1111-4111-8111-111111111112'::uuid;
  p2 constant uuid := '22222222-2222-4222-8222-222222222222'::uuid;
  p3 constant uuid := '33333333-3333-4333-8333-333333333332'::uuid;
  p4 constant uuid := '44444444-4444-4444-8444-444444444442'::uuid;
  p5 constant uuid := '55555555-5555-4555-8555-555555555552'::uuid;
  u1 constant uuid := '11111111-1111-4111-8111-111111111111'::uuid;
  practitioner_uid constant uuid := '99999999-9999-4999-8999-999999999991'::uuid;
  org_alpha constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid;
  org_beta constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid;
  org_zero constant uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid;
  pre_authority constant uuid := 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaa1'::uuid;
  pre_entry constant uuid := 'aaaaaaaa-2222-4222-8222-aaaaaaaaaaa2'::uuid;
  commercial_case constant uuid := '66666666-6666-4666-8666-666666666611'::uuid;
  commercial_entitlement constant uuid := '66666666-6666-4666-8666-666666666641'::uuid;
  commercial_institution constant uuid := '66666666-6666-4666-8666-666666666631'::uuid;
  commercial_scope constant uuid := '66666666-6666-4666-8666-666666666632'::uuid;
  v_pre_ledger uuid;
  v_beta_ledger uuid;
  v_pre_revision bigint;
  v_person1 uuid;
  v_result jsonb;
  v_retry jsonb;
  v_ledgers uuid[] := '{}'::uuid[];
  v_shared uuid;
  v_independent uuid;
  v_new_org uuid;
  v_new_org_ledger uuid;
  v_new_org_key text;
  v_new_ledger_key text;
  v_rel_a jsonb;
  v_rel_b jsonb;
  v_sym_a jsonb;
  v_sym_b jsonb;
  v_corr_a jsonb;
  v_corr_b jsonb;
  v_corr_sym_a jsonb;
  v_corr_sym_b jsonb;
  v_failed boolean;
  v_org_count bigint;
  v_ledger_count bigint;
  v_entry_revision bigint;
  i integer;
begin
  select (metadata->>'validationPreGraphLedgerId')::uuid,
         (metadata->>'validationPreGraphEntryRevision')::bigint
  into v_pre_ledger,v_pre_revision
  from atlas.organizations where id=org_alpha;

  select (metadata->>'validationPreGraphLedgerId')::uuid
  into v_beta_ledger
  from atlas.organizations where id=org_beta;

  select person_id into v_person1 from atlas.principals where id=p1;

  if v_pre_ledger is null or v_beta_ledger is null or v_person1 is null then
    raise exception 'Pre-graph fixture identity is unavailable.';
  end if;

  if not exists (
    select 1 from atlas.ledgers l
    where l.id=v_pre_ledger
      and l.organization_id=org_alpha
      and l.name='Ledger Graph Fixture Alpha'
      and l.stable_key='ledger_graph_fixture_alpha'
  ) then
    raise exception 'Preexisting Ledger identity/history was not preserved.';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities a
    where a.id=pre_authority and a.principal_id=p1 and a.ledger_id=v_pre_ledger
      and a.authority_kind='root_governing' and a.status='active'
  ) then
    raise exception 'Preexisting Principal -> Ledger authority was not preserved.';
  end if;

  select revision into v_entry_revision
  from atlas.organization_ledger_entries where id=pre_entry;
  if v_entry_revision is distinct from v_pre_revision
     or not exists (
       select 1 from atlas.organization_ledger_entries e
       where e.id=pre_entry and e.organization_id=org_alpha and e.ledger_id=v_pre_ledger
     ) then
    raise exception 'Preexisting Organization Ledger entry identity/revision changed.';
  end if;

  if not exists (
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=v_pre_ledger and p.organization_id=org_alpha
      and p.participation_kind='governing' and p.status='active'
      and p.is_compatibility_primary
  ) then
    raise exception 'Historical Organization/Ledger association was not backfilled into participation.';
  end if;

  if atlas.primary_ledger_for_organization_v1(org_alpha) is distinct from v_pre_ledger then
    raise exception 'Compatibility-primary Ledger lookup changed for legacy Organization.';
  end if;

  insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
  values (
    org_zero,'cccccccccccc4ccc8cccccccccccccc1','Organization With No Ledger',
    'active','{"validation_fixture":true}'::jsonb,'ready'
  );

  if exists (
    select 1 from atlas.ledger_organization_participations p where p.organization_id=org_zero
  ) or exists (
    select 1 from atlas.ledgers l where l.organization_id=org_zero
  ) then
    raise exception 'Organization insert still manufactured a Ledger.';
  end if;

  for i in 1..8 loop
    v_result := atlas.establish_ledger_for_principal_v1(
      p1,v_person1,
      'Ledger Graph Proof '||i,
      case when i=1 then 'venue_operations' when i=2 then 'farm_production' else 'governed_reality_'||i end,
      'ledger_graph_validation',
      jsonb_build_object('validation_fixture',true,'proof_index',i)
    );
    v_ledgers := array_append(v_ledgers,(v_result->'ledger'->>'id')::uuid);

    if (v_result->'ledger'->>'stable_key') !~ '^[0-9a-f]{32}$' then
      raise exception 'New Ledger stable key is not opaque: %',v_result;
    end if;
    if exists (
      select 1 from atlas.ledgers l
      where l.id=(v_result->'ledger'->>'id')::uuid and l.organization_id is not null
    ) then
      raise exception 'Independent Ledger unexpectedly carries Organization ownership.';
    end if;
  end loop;

  select count(*) into v_ledger_count from atlas.ledgers;
  if v_ledger_count<>10 then
    raise exception 'Expected exactly ten Ledgers before organization-establishment proof, found %.',v_ledger_count;
  end if;

  v_shared := v_ledgers[1];
  v_independent := v_ledgers[2];

  perform atlas.establish_ledger_organization_participation_v1(
    v_shared,org_alpha,'operating',false,
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );

  if (select count(distinct ledger_id) from atlas.ledger_organization_participations
      where organization_id=org_alpha and status='active')<2 then
    raise exception 'One Organization could not participate in multiple Ledgers.';
  end if;

  perform atlas.establish_ledger_organization_participation_v1(
    v_shared,org_beta,'shared_service',false,
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );

  if (select count(distinct organization_id) from atlas.ledger_organization_participations
      where ledger_id=v_shared and status='active')<>2 then
    raise exception 'One Ledger could not involve multiple Organizations.';
  end if;

  if exists (
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=v_independent and p.status='active'
  ) then
    raise exception 'Independent Ledger unexpectedly acquired Organization participation.';
  end if;

  insert into atlas.organization_ledger_entries(
    id,organization_id,event_key,source_domain,semantic_type,occurred_at,title,detail,
    payload,provenance,correlation,ledger_id
  ) values (
    'aaaaaaaa-3333-4333-8333-aaaaaaaaaaa3'::uuid,
    org_alpha,'ledger_graph_fixture:secondary_ledger_event','validation_fixture','secondary_event',now(),
    'Secondary Ledger event','Explicit non-primary participated Ledger.',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,v_shared
  );

  v_failed:=false;
  begin
    insert into atlas.organization_ledger_entries(
      id,organization_id,event_key,source_domain,semantic_type,occurred_at,title,
      payload,provenance,correlation,ledger_id
    ) values (
      'aaaaaaaa-4444-4444-8444-aaaaaaaaaaa4'::uuid,
      org_alpha,'ledger_graph_fixture:invalid_ledger_event','validation_fixture','invalid_event',now(),
      'Must fail','{}'::jsonb,'{}'::jsonb,'{}'::jsonb,v_independent
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Organization Ledger entry accepted a Ledger without active participation.';
  end if;

  insert into atlas.principal_ledger_authorities(
    principal_id,ledger_id,authority_kind,status,basis,metadata
  )
  select p.id,l.id,'root_governing','active','ledger_graph_validation_matrix','{"validation_fixture":true}'::jsonb
  from atlas.principals p
  cross join atlas.ledgers l
  where p.id in (p1,p2,p3,p4,p5)
    and not exists (
      select 1 from atlas.principal_ledger_authorities a
      where a.principal_id=p.id and a.ledger_id=l.id
        and a.authority_kind='root_governing' and a.status='active'
    );

  if (select count(*) from atlas.principal_ledger_authorities a
      where a.principal_id in (p1,p2,p3,p4,p5) and a.status='active'
        and a.authority_kind='root_governing')<>50 then
    raise exception 'Five-Principals / ten-Ledgers root authority matrix was not established.';
  end if;

  v_rel_a := atlas.establish_ledger_relationship_v1(
    v_ledgers[3],v_ledgers[4],'depends_on','directed',
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  v_rel_b := atlas.establish_ledger_relationship_v1(
    v_ledgers[4],v_ledgers[3],'depends_on','directed',
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  if (v_rel_a->>'relationshipId')=(v_rel_b->>'relationshipId') then
    raise exception 'Directed reciprocal Ledger relationships collapsed incorrectly.';
  end if;

  v_sym_a := atlas.establish_ledger_relationship_v1(
    v_ledgers[5],v_ledgers[6],'sibling_of','symmetric',
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  v_sym_b := atlas.establish_ledger_relationship_v1(
    v_ledgers[6],v_ledgers[5],'sibling_of','symmetric',
    '{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  if (v_sym_a->>'relationshipId') is distinct from (v_sym_b->>'relationshipId')
     or coalesce((v_sym_b->>'alreadyEstablished')::boolean,false)=false then
    raise exception 'Symmetric Ledger relationship reverse retry was not idempotent.';
  end if;

  v_corr_a := atlas.establish_ledger_correlation_v1(
    '77777777-7777-4777-8777-777777777701'::uuid,
    v_ledgers[3],'production_lot','88888888-8888-4888-8888-888888888801'::uuid,null,'harvest',
    v_ledgers[4],'supply_lot',null,'FG-SUPPLY-1','received',
    'supplied_as','directed','{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  v_corr_b := atlas.establish_ledger_correlation_v1(
    '77777777-7777-4777-8777-777777777701'::uuid,
    v_ledgers[3],'production_lot','88888888-8888-4888-8888-888888888801'::uuid,null,'harvest',
    v_ledgers[4],'supply_lot',null,'FG-SUPPLY-1','received',
    'supplied_as','directed','{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  if (v_corr_a->>'correlationId') is distinct from (v_corr_b->>'correlationId')
     or coalesce((v_corr_b->>'alreadyEstablished')::boolean,false)=false then
    raise exception 'Same cross-Ledger correlation retry was not idempotent.';
  end if;

  v_failed:=false;
  begin
    perform atlas.establish_ledger_correlation_v1(
      '77777777-7777-4777-8777-777777777701'::uuid,
      v_ledgers[3],'production_lot','88888888-8888-4888-8888-888888888801'::uuid,null,'harvest',
      v_ledgers[4],'supply_lot',null,'FG-SUPPLY-1','different_path',
      'supplied_as','directed','{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
    );
  exception when sqlstate '23514' then
    v_failed:=true;
    if position('Correlation identity contradiction.' in sqlerrm)=0 then
      raise exception 'Correlation contradiction used unexpected error: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Contradictory retry reused a correlation key without failing closed.';
  end if;

  v_corr_sym_a := atlas.establish_ledger_correlation_v1(
    '77777777-7777-4777-8777-777777777702'::uuid,
    v_ledgers[7],'responsibility',null,'RESP-A',null,
    v_ledgers[8],'responsibility',null,'RESP-B',null,
    'corresponds_to','symmetric','{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  v_corr_sym_b := atlas.establish_ledger_correlation_v1(
    '77777777-7777-4777-8777-777777777702'::uuid,
    v_ledgers[8],'responsibility',null,'RESP-B',null,
    v_ledgers[7],'responsibility',null,'RESP-A',null,
    'corresponds_to','symmetric','{"source":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
  );
  if (v_corr_sym_a->>'correlationId') is distinct from (v_corr_sym_b->>'correlationId') then
    raise exception 'Symmetric correlation reverse retry was not normalized.';
  end if;

  perform set_config('request.jwt.claim.sub',u1::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u1::text,'role','authenticated')::text,true);

  v_result := atlas.establish_organization_self_api_v1('Very Semantic Elm Farm Name');
  v_new_org := (v_result->'organization'->>'id')::uuid;
  v_new_org_ledger := (v_result->'ledger'->>'id')::uuid;
  v_new_org_key := v_result->'organization'->>'stable_key';
  v_new_ledger_key := v_result->'ledger'->>'stable_key';

  if v_new_org is null or v_new_org_ledger is null
     or v_new_org_key !~ '^[0-9a-f]{32}$'
     or v_new_ledger_key !~ '^[0-9a-f]{32}$'
     or v_new_org_key=v_new_ledger_key then
    raise exception 'New Organization/Ledger identity is not opaque and independent: %',v_result;
  end if;

  if exists (select 1 from atlas.ledgers l where l.id=v_new_org_ledger and l.organization_id is not null) then
    raise exception 'New initial Ledger still carries Organization ownership.';
  end if;

  if not exists (
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=v_new_org_ledger and p.organization_id=v_new_org
      and p.participation_kind='governing' and p.status='active'
      and p.is_compatibility_primary
  ) then
    raise exception 'New Organization establishment did not create explicit primary participation.';
  end if;

  if not atlas.principal_has_ledger_authority_v1(p1,v_new_org_ledger) then
    raise exception 'New initial Ledger did not receive Principal root authority.';
  end if;

  select count(*) into v_org_count from atlas.organizations;
  select count(*) into v_ledger_count from atlas.ledgers;

  perform set_config('request.jwt.claim.sub',practitioner_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',practitioner_uid::text,'role','authenticated')::text,true);

  v_result := atlas.bind_implementation_ledger_entitlement_self_api_v1(
    commercial_case,commercial_institution,commercial_scope,commercial_entitlement,
    null,v_independent
  );

  if (v_result->>'bindingId') is null or (v_result->>'ledgerId')::uuid<>v_independent then
    raise exception 'Commercial binding did not target the independent Ledger.';
  end if;
  if exists (
    select 1 from atlas.ledger_entitlement_bindings b
    where b.id=(v_result->>'bindingId')::uuid
      and (b.organization_id is not null or b.ledger_id<>v_independent)
  ) then
    raise exception 'Commercial binding manufactured or required Organization scope.';
  end if;
  if (select count(*) from atlas.organizations)<>v_org_count
     or (select count(*) from atlas.ledgers)<>v_ledger_count then
    raise exception 'Commercial binding changed institutional identity counts.';
  end if;

  perform set_config('request.jwt.claim.sub',u1::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u1::text,'role','authenticated')::text,true);
  v_result := atlas.principal_ledgers_self_api_v1();

  if not exists (
    select 1 from jsonb_array_elements(v_result->'items') x
    where (x->>'ledgerId')::uuid=v_independent
      and jsonb_array_length(x->'organizations')=0
  ) then
    raise exception 'Principal Ledger projection lost independent Ledger visibility: %',v_result;
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_result->'items') x
    where (x->>'ledgerId')::uuid=v_shared
      and jsonb_array_length(x->'organizations')>=2
  ) then
    raise exception 'Principal Ledger projection did not expose multi-Organization participation.';
  end if;

  if has_table_privilege('anon','atlas.ledger_organization_participations','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_organization_participations','SELECT')
     or has_table_privilege('anon','atlas.ledger_relationships','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_relationships','SELECT')
     or has_table_privilege('anon','atlas.ledger_correlations','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_correlations','SELECT') then
    raise exception 'Ledger graph tables widened browser read access.';
  end if;

  if has_function_privilege('authenticated','atlas.establish_ledger_for_principal_v1(uuid,uuid,text,text,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.establish_ledger_organization_participation_v1(uuid,uuid,text,boolean,jsonb,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.establish_ledger_relationship_v1(uuid,uuid,text,text,jsonb,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.establish_ledger_correlation_v1(uuid,uuid,text,uuid,text,text,uuid,text,uuid,text,text,text,text,jsonb,jsonb)','EXECUTE') then
    raise exception 'Internal Ledger graph mutation functions are browser executable.';
  end if;

  if has_function_privilege('anon','atlas.principal_ledgers_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','atlas.principal_ledgers_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Governed browser API grants are incorrect.';
  end if;

  if (select is_nullable from information_schema.columns
      where table_schema='atlas' and table_name='ledgers' and column_name='organization_id')<>'YES' then
    raise exception 'Ledger.organization_id is still mandatory.';
  end if;
end;
$proof$;
