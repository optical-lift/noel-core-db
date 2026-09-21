begin;

do $validation$
declare
  v_practitioner_user uuid:=gen_random_uuid();
  v_other_user uuid:=gen_random_uuid();
  v_org uuid:=gen_random_uuid();
  v_other_org uuid:=gen_random_uuid();
  v_purchase uuid:=gen_random_uuid();
  v_case uuid:=gen_random_uuid();
  v_participant uuid:=gen_random_uuid();
  v_entitlement uuid:=gen_random_uuid();
  v_ledger uuid;
  v_thread uuid:=gen_random_uuid();
  v_governed_finding uuid:=gen_random_uuid();
  v_rejected_finding uuid:=gen_random_uuid();

  v_item uuid;
  v_machine_item uuid;
  v_person_item uuid;
  v_unit_item uuid;
  v_position_item uuid;
  v_responsibility_item uuid;
  v_relation_item uuid;
  v_appointment_item uuid;
  v_org_item uuid;
  v_cross_org_item uuid;

  v_unit uuid;
  v_person uuid;
  v_ipr uuid;
  v_position uuid;
  v_responsibility uuid;
  v_appointment uuid;

  v_preview jsonb;
  v_result jsonb;
  v_read jsonb;
  v_begins timestamptz:='2026-09-21 12:00:00+00'::timestamptz;
  v_before_people integer;
  v_before_credentials integer;
  v_before_memberships integer;
  v_before_seats integer;
  v_sig text;
begin
  -- -----------------------------------------------------------------------
  -- Schema + authority shape.
  -- -----------------------------------------------------------------------

  if to_regclass('atlas.institutional_person_records') is null then
    raise exception 'Reality Sentence proof requires Institutional Person Record prerequisite.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas'
      and table_name='implementation_establishment_items'
      and column_name='reality_operation_key'
  ) then
    raise exception 'Reality Sentence candidate columns are missing.';
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(atlas.reality_establishment_registry_v1()->'operations') op
    where op->>'operationKey'='position_appointment.establish.v1'
      and op->>'owningDomain'='organization_structure'
  ) then
    raise exception 'Establishment Registry does not expose the first proving grammar.';
  end if;

  foreach v_sig in array array[
    'atlas.establish_institutional_person_record_internal_v1(uuid,text,uuid,text,jsonb)',
    'atlas.establish_organization_unit_internal_v1(uuid,uuid,text,text,text,jsonb)',
    'atlas.establish_organization_position_internal_v1(uuid,uuid,text,text,text,jsonb)',
    'atlas.establish_organization_responsibility_internal_v1(uuid,text,text,text,jsonb)',
    'atlas.establish_position_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb)',
    'atlas.establish_position_appointment_internal_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,jsonb)'
  ] loop
    if to_regprocedure(v_sig) is null then
      raise exception 'Missing Reality Sentence internal command: %',v_sig;
    end if;
    if has_function_privilege('anon',to_regprocedure(v_sig),'execute')
       or has_function_privilege('authenticated',to_regprocedure(v_sig),'execute')
       or has_function_privilege('service_role',to_regprocedure(v_sig),'execute') then
      raise exception 'Reality Sentence owning command is directly executable outside governed orchestrator: %',v_sig;
    end if;
  end loop;

  foreach v_sig in array array[
    'public.implementation_reality_establishment_registry_self_api_v1()',
    'public.create_implementation_reality_sentence_self_api_v1(uuid,text,text,jsonb,text,uuid,text)',
    'public.preview_implementation_reality_sentence_self_api_v1(uuid)',
    'public.establish_implementation_reality_sentence_self_api_v1(uuid)',
    'public.implementation_reality_sentences_self_api_v1(uuid)'
  ] loop
    if to_regprocedure(v_sig) is null then
      raise exception 'Missing Reality Sentence browser membrane: %',v_sig;
    end if;
    if has_function_privilege('anon',to_regprocedure(v_sig),'execute')
       or not has_function_privilege('authenticated',to_regprocedure(v_sig),'execute') then
      raise exception 'Reality Sentence browser membrane privilege mismatch: %',v_sig;
    end if;
  end loop;

  -- -----------------------------------------------------------------------
  -- Synthetic practitioner + exact Implementation Case/Ledger scope.
  -- -----------------------------------------------------------------------

  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_practitioner_user,'reality-practitioner-'||substr(v_practitioner_user::text,1,8)||'@example.test',now(),now()),
    (v_other_user,'reality-other-'||substr(v_other_user::text,1,8)||'@example.test',now(),now());

  insert into atlas.implementation_practitioners(
    human_user_id,status,authorization_basis,metadata
  ) values(
    v_practitioner_user,'active',
    '{"proof":"reality_sentence_establishment_v1"}'::jsonb,
    '{}'::jsonb
  );

  insert into atlas.implementation_purchases(
    id,provider,provider_checkout_session_id,offer_key,starting_label,payment_option,
    purchase_state,currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,
    metadata
  ) values(
    v_purchase,'stripe','reality-sentence-proof-'||v_purchase::text,
    'reality_sentence_validation','Reality Sentence Validation','pay_in_full',
    'active','usd',0,0,'{}'::jsonb
  );

  insert into atlas.implementation_cases(
    id,implementation_purchase_id,state,metadata
  ) values(
    v_case,v_purchase,'in_implementation','{}'::jsonb
  );

  insert into atlas.implementation_case_participants(
    id,implementation_case_id,human_user_id,relationship_kind,active,basis,metadata
  ) values(
    v_participant,v_case,v_practitioner_user,'practitioner',true,
    '{"proof":"assigned_practitioner"}'::jsonb,'{}'::jsonb
  );

  insert into atlas.organizations(id,stable_key,name)
  values
    (v_org,'reality-proof-'||substr(v_org::text,1,8),'Reality Proof Organization'),
    (v_other_org,'reality-other-'||substr(v_other_org::text,1,8),'Other Reality Organization');

  select l.id into strict v_ledger
  from atlas.ledgers l
  where l.organization_id=v_org and l.status='active';

  if not exists(
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=v_ledger and p.organization_id=v_org
      and p.status='active' and p.ended_at is null
  ) then
    insert into atlas.ledger_organization_participations(
      ledger_id,organization_id,participation_kind,is_compatibility_primary,
      status,basis,metadata
    ) values(
      v_ledger,v_org,'governing',true,'active',
      '{"proof":"reality_sentence_establishment_v1"}'::jsonb,'{}'::jsonb
    );
  end if;

  insert into atlas.ledger_entitlements(
    id,implementation_case_id,source_purchase_id,entitlement_number,
    entitlement_kind,price_class,state,setup_price_cents,monthly_price_cents,
    commercial_basis,metadata
  ) values(
    v_entitlement,v_case,v_purchase,1,
    'atlas_ledger','baseline_first','bound',0,0,
    '{"proof":"reality_sentence_establishment_v1"}'::jsonb,'{}'::jsonb
  );

  insert into atlas.ledger_entitlement_bindings(
    implementation_case_id,ledger_entitlement_id,organization_id,
    organization_unit_id,bound_by_participant_id,state,binding_basis,metadata,ledger_id
  ) values(
    v_case,v_entitlement,v_org,null,v_participant,'bound',
    '{"proof":"reality_sentence_establishment_v1","institutionalRealityPreexisting":true}'::jsonb,
    '{}'::jsonb,v_ledger
  );

  perform set_config('request.jwt.claim.sub',v_practitioner_user::text,true);

  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Synthetic Reality Sentence practitioner did not resolve as authorized.';
  end if;

  -- Generic legacy saver may not manufacture Reality Sentence establishment.
  begin
    perform atlas.save_implementation_establishment_item_self_api_v1(
      v_case,'reality_sentence','Invalid generic Reality Sentence','', 'proposed'
    );
    raise exception 'Generic establishment saver unexpectedly accepted reality_sentence.';
  exception when sqlstate '22023' then
    null;
  end;

  -- -----------------------------------------------------------------------
  -- Candidate before truth: Organization Unit.
  -- -----------------------------------------------------------------------

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Reality Proof Organization has Production.',
    'organization_unit.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'stableKey','production',
      'name','Production',
      'unitKind','operating_unit'
    ),
    'manual_structured',
    null,
    'Validation candidate-before-truth proof.'
  );
  v_unit_item:=(v_result->>'establishmentItemId')::uuid;

  if exists(
    select 1 from atlas.organization_units u
    where u.organization_id=v_org and u.stable_key='production'
  ) then
    raise exception 'Reality Sentence candidate creation wrote Organization Unit truth before promotion.';
  end if;

  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_unit_item);
  if v_preview->>'state'<>'ready'
     or v_preview#>>'{consequence,kind}'<>'organization_unit'
     or v_preview#>>'{consequence,mode}'<>'create' then
    raise exception 'Organization Unit preview did not resolve deterministic create consequence: %',v_preview;
  end if;

  if exists(
    select 1 from atlas.organization_units u
    where u.organization_id=v_org and u.stable_key='production'
  ) then
    raise exception 'Reality Sentence preview wrote Organization Unit truth.';
  end if;

  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_unit_item);
  if not coalesce((v_result->>'established')::boolean,false) then
    raise exception 'Organization Unit Reality Sentence did not establish: %',v_result;
  end if;
  v_unit:=(v_result#>>'{receipt,organizationUnitId}')::uuid;

  if not exists(
    select 1 from atlas.organization_units u
    where u.id=v_unit and u.organization_id=v_org
      and u.name='Production' and u.unit_kind='operating_unit'
  ) then
    raise exception 'Canonical Organization Unit consequence is missing.';
  end if;

  -- -----------------------------------------------------------------------
  -- Accountless Institutional Person: preview must not create Person.
  -- -----------------------------------------------------------------------

  select count(*) into v_before_people from atlas.people;
  select count(*) into v_before_credentials from atlas.person_auth_credentials;
  select count(*) into v_before_memberships from atlas.organization_memberships;
  select count(*) into v_before_seats from atlas.organization_employee_seats;

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Sarah is known to Reality Proof Organization.',
    'institutional_person.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'identityMode','new_person',
      'displayName','Sarah'
    ),
    'manual_structured',
    null,
    ''
  );
  v_person_item:=(v_result->>'establishmentItemId')::uuid;

  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_person_item);
  if v_preview->>'state'<>'ready'
     or v_preview#>>'{consequence,mode}'<>'create_new_person_and_relation' then
    raise exception 'New Person preview did not preserve explicit identity decision: %',v_preview;
  end if;

  if (select count(*) from atlas.people)<>v_before_people
     or (select count(*) from atlas.person_auth_credentials)<>v_before_credentials
     or (select count(*) from atlas.organization_memberships)<>v_before_memberships
     or (select count(*) from atlas.organization_employee_seats)<>v_before_seats then
    raise exception 'New Person preview mutated identity/access state.';
  end if;

  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_person_item);
  v_person:=(v_result#>>'{receipt,personId}')::uuid;
  v_ipr:=(v_result#>>'{receipt,institutionalPersonRecordId}')::uuid;

  if not exists(
    select 1 from atlas.people p where p.id=v_person and p.display_name='Sarah' and p.status='active'
  ) or not exists(
    select 1 from atlas.institutional_person_records r
    where r.id=v_ipr and r.organization_id=v_org and r.person_id=v_person and r.status='active'
  ) then
    raise exception 'Accountless Person + Institutional Person Record consequence is incomplete.';
  end if;

  if exists(select 1 from atlas.person_auth_credentials c where c.person_id=v_person)
     or exists(select 1 from atlas.organization_memberships m where m.organization_id=v_org and m.person_id=v_person)
     or exists(select 1 from atlas.organization_employee_seats s where s.organization_id=v_org and s.institutional_person_record_id=v_ipr) then
    raise exception 'Institutional Person establishment manufactured login, Membership, or employee seat.';
  end if;

  -- -----------------------------------------------------------------------
  -- Position, Responsibility, relation, Appointment.
  -- -----------------------------------------------------------------------

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Farm Steward exists in Production.',
    'organization_position.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'organizationUnitId',v_unit,
      'stableKey','farm_steward',
      'displayTitle','Farm Steward',
      'positionKind','staff'
    ),
    'manual_structured',null,''
  );
  v_position_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_position_item);
  if v_preview->>'state'<>'ready' then
    raise exception 'Position preview is not ready: %',v_preview;
  end if;
  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_position_item);
  v_position:=(v_result#>>'{receipt,positionId}')::uuid;

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Production stewardship is a responsibility of Reality Proof Organization.',
    'organization_responsibility.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'stableKey','production_stewardship',
      'name','Production stewardship',
      'responsibilityKind','stewardship'
    ),
    'manual_structured',null,''
  );
  v_responsibility_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_responsibility_item);
  if v_preview->>'state'<>'ready' then
    raise exception 'Responsibility preview is not ready: %',v_preview;
  end if;
  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_responsibility_item);
  v_responsibility:=(v_result#>>'{receipt,responsibilityId}')::uuid;

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Farm Steward carries Production stewardship.',
    'position_responsibility.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'positionId',v_position,
      'responsibilityId',v_responsibility,
      'relationshipKind','accountable'
    ),
    'manual_structured',null,''
  );
  v_relation_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_relation_item);
  if v_preview->>'state'<>'ready' then
    raise exception 'Position Responsibility preview is not ready: %',v_preview;
  end if;
  perform atlas.establish_implementation_reality_sentence_self_api_v1(v_relation_item);

  if not exists(
    select 1 from atlas.organization_position_responsibilities pr
    where pr.position_id=v_position and pr.responsibility_id=v_responsibility
      and pr.relationship_kind='accountable'
  ) then
    raise exception 'Position Responsibility consequence is missing.';
  end if;

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Sarah occupies Farm Steward.',
    'position_appointment.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'institutionalPersonRecordId',v_ipr,
      'positionId',v_position,
      'appointmentKind','primary',
      'beginsAt',v_begins
    ),
    'manual_structured',null,''
  );
  v_appointment_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_appointment_item);
  if v_preview->>'state'<>'ready' then
    raise exception 'Appointment preview is not ready: %',v_preview;
  end if;
  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_appointment_item);
  v_appointment:=(v_result#>>'{receipt,appointmentId}')::uuid;

  if not exists(
    select 1 from atlas.organization_position_appointments a
    where a.id=v_appointment
      and a.organization_id=v_org
      and a.institutional_person_record_id=v_ipr
      and a.position_id=v_position
      and a.organization_membership_id is null
      and a.identity_subject_id is null
      and a.status='active'
  ) then
    raise exception 'Accountless Position Appointment did not establish canonically.';
  end if;

  -- No work/access side effects.
  if exists(select 1 from atlas.organization_memberships m where m.organization_id=v_org and m.person_id=v_person)
     or exists(select 1 from atlas.organization_employee_seats s where s.organization_id=v_org and s.institutional_person_record_id=v_ipr)
     or exists(select 1 from atlas.work_allocations wa where wa.assignee_institutional_person_record_id=v_ipr) then
    raise exception 'Reality Sentence structural establishment created access or Company Work responsibility.';
  end if;

  -- -----------------------------------------------------------------------
  -- Organization birth remains Principal-self, not practitioner power.
  -- -----------------------------------------------------------------------

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'A New Organization exists.',
    'organization.establish.v1',
    '{}'::jsonb,
    'manual_structured',null,''
  );
  v_org_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_org_item);

  if v_preview->>'state'<>'requires_principal_self_establishment'
     or v_preview->>'canonicalCommand'<>'establish_organization_ledger_self_api_v1' then
    raise exception 'Organization birth did not remain Principal-self: %',v_preview;
  end if;

  -- -----------------------------------------------------------------------
  -- Cross-Organization browser-supplied ids fail at exact case scope.
  -- -----------------------------------------------------------------------

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Other responsibility is a responsibility of Other Reality Organization.',
    'organization_responsibility.establish.v1',
    jsonb_build_object(
      'organizationId',v_other_org,
      'stableKey','other_responsibility',
      'name','Other responsibility',
      'responsibilityKind','stewardship'
    ),
    'manual_structured',null,''
  );
  v_cross_org_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_cross_org_item);
  if v_preview->>'state'<>'outside_implementation_scope' then
    raise exception 'Cross-Organization candidate escaped exact Implementation scope: %',v_preview;
  end if;

  v_result:=atlas.establish_implementation_reality_sentence_self_api_v1(v_cross_org_item);
  if coalesce((v_result->>'established')::boolean,false)
     or exists(
       select 1 from atlas.organization_responsibilities r
       where r.organization_id=v_other_org and r.stable_key='other_responsibility'
     ) then
    raise exception 'Cross-Organization establishment unexpectedly mutated canonical reality.';
  end if;

  -- -----------------------------------------------------------------------
  -- Machine/manual convergence uses governed Finding, not AI truth authority.
  -- -----------------------------------------------------------------------

  insert into atlas.implementation_threads(
    id,implementation_case_id,work_area,title,state,author_user_id,shared_with_participants
  ) values(
    v_thread,v_case,'people','Reality Sentence Finding Proof','open',
    v_practitioner_user,false
  );

  insert into atlas.implementation_findings(
    id,implementation_thread_id,statement,status,author_user_id
  ) values
    (v_governed_finding,v_thread,'Production already exists.','governed',v_practitioner_user),
    (v_rejected_finding,v_thread,'Rejected machine claim.','rejected',v_practitioner_user);

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Reality Proof Organization has Production.',
    'organization_unit.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'stableKey','production',
      'name','Production',
      'unitKind','operating_unit'
    ),
    'machine_proposed',
    v_governed_finding,
    ''
  );
  v_machine_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_machine_item);
  if v_preview->>'state'<>'ready'
     or v_preview#>>'{consequence,mode}'<>'reuse_existing' then
    raise exception 'Governed machine finding did not converge on same command path: %',v_preview;
  end if;

  begin
    perform atlas.create_implementation_reality_sentence_self_api_v1(
      v_case,
      'Rejected machine claim.',
      'organization_unit.establish.v1',
      jsonb_build_object(
        'organizationId',v_org,
        'stableKey','rejected_machine_unit',
        'name','Rejected Machine Unit',
        'unitKind','operating_unit'
      ),
      'machine_proposed',
      v_rejected_finding,
      ''
    );
    raise exception 'Rejected Finding unexpectedly became a Reality Sentence candidate.';
  exception when sqlstate '23514' then
    null;
  end;

  -- -----------------------------------------------------------------------
  -- Established sentence is provenance; canonical projection drives display.
  -- -----------------------------------------------------------------------

  v_read:=atlas.implementation_reality_sentences_self_api_v1(v_case);
  if not exists(
    select 1
    from jsonb_array_elements(v_read->'establishedReality') e
    where (e->>'id')::uuid=v_appointment_item
      and e#>>'{realityEntry,sentence}'='Sarah occupies Farm Steward.'
  ) then
    raise exception 'Established Appointment did not rerender from canonical reality.';
  end if;

  update atlas.organization_positions
  set display_title='Operations Steward',updated_at=now()
  where id=v_position;

  v_read:=atlas.implementation_reality_sentences_self_api_v1(v_case);
  if not exists(
    select 1
    from jsonb_array_elements(v_read->'establishedReality') e
    where (e->>'id')::uuid=v_appointment_item
      and e->>'authoredSentence'='Sarah occupies Farm Steward.'
      and e#>>'{realityEntry,sentence}'='Sarah occupies Operations Steward.'
  ) then
    raise exception 'Reality Entry remained bound to authored sentence instead of canonical Position truth.';
  end if;

  -- Established receipt/bindings are immutable; supersession is the repair path.
  begin
    update atlas.implementation_establishment_items
    set semantic_bindings=semantic_bindings||'{"tampered":true}'::jsonb
    where id=v_appointment_item;
    raise exception 'Established Reality Sentence provenance was mutable.';
  exception when sqlstate '23514' then
    null;
  end;

  if not exists(
    select 1 from atlas.implementation_establishment_items e
    where e.id=v_appointment_item
      and e.status='established'
      and e.resolution_state='established'
      and e.canonical_consequence is not null
      and e.established_by_user_id=v_practitioner_user
      and e.established_at is not null
  ) then
    raise exception 'Established Reality Sentence lacks canonical receipt attribution.';
  end if;

  -- Same-name identity is never an implicit merge.
  insert into atlas.people(display_name,status,metadata)
  values('Jordan','active','{"proof":"same_name_one"}'::jsonb),
        ('Jordan','active','{"proof":"same_name_two"}'::jsonb);

  v_result:=atlas.create_implementation_reality_sentence_self_api_v1(
    v_case,
    'Jordan is known to Reality Proof Organization.',
    'institutional_person.establish.v1',
    jsonb_build_object(
      'organizationId',v_org,
      'identityMode','existing_person'
    ),
    'manual_structured',null,''
  );
  v_item:=(v_result->>'establishmentItemId')::uuid;
  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_item);
  if v_preview->>'state'<>'unresolved_identity' then
    raise exception 'Same-name Person ambiguity was silently resolved: %',v_preview;
  end if;
end;
$validation$;

rollback;
