BEGIN;

-- Shared-domain boundary: one Person identity, one optional commercial origin.
-- No individual user rows, Stripe receipts, Ledger grants, or fabricated
-- onboarding evidence are written by this migration.

ALTER TABLE atlas.implementation_cases
  ALTER COLUMN implementation_purchase_id DROP NOT NULL;

ALTER TABLE atlas.implementation_cases
  ADD COLUMN case_origin text NOT NULL DEFAULT 'paid_institutional',
  ADD COLUMN personal_subject_person_entity_id uuid
    REFERENCES reality.entities(id) ON DELETE RESTRICT;

ALTER TABLE atlas.implementation_cases
  ADD CONSTRAINT implementation_cases_exact_origin_v1 CHECK (
    (case_origin = 'paid_institutional'
     AND implementation_purchase_id IS NOT NULL
     AND personal_subject_person_entity_id IS NULL)
    OR
    (case_origin = 'personal_atlas'
     AND implementation_purchase_id IS NULL
     AND personal_subject_person_entity_id IS NOT NULL)
  );

CREATE UNIQUE INDEX implementation_personal_case_per_person_uq
  ON atlas.implementation_cases(personal_subject_person_entity_id)
  WHERE case_origin='personal_atlas';

CREATE INDEX implementation_cases_origin_state_idx
  ON atlas.implementation_cases(case_origin,state,opened_at DESC);

-- The real legacy Person and credential are admitted with their exact UUIDs,
-- not replaced with a new UUID and not inferred from email or display name.
CREATE OR REPLACE FUNCTION atlas.admit_existing_person_identity_self_v1()
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','reality','compatibility','auth'
AS $admit$
DECLARE
 v_uid uuid := auth.uid();
 v_p atlas.principals%rowtype;
 v_c atlas.person_auth_credentials%rowtype;
 v_display_name text;
 v_binding reality.auth_person_bindings%rowtype;
 v_entity reality.entities%rowtype;
 v_lineage compatibility.legacy_bindings%rowtype;
BEGIN
 IF v_uid IS NULL THEN
   RAISE EXCEPTION 'Authenticated human required' USING errcode='42501';
 END IF;
 PERFORM 1 FROM auth.users u
 WHERE u.id=v_uid AND u.deleted_at IS NULL
   AND u.email_confirmed_at IS NOT NULL
   AND (u.banned_until IS NULL OR u.banned_until<=now())
 FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Verified Atlas credential required' USING errcode='42501';
 END IF;
 SELECT * INTO STRICT v_p FROM atlas.principals
 WHERE user_id=v_uid AND status='active';
 IF v_p.person_id IS NULL THEN
   RAISE EXCEPTION 'Existing Principal Person identity required' USING errcode='23514';
 END IF;
 SELECT * INTO STRICT v_c FROM atlas.person_auth_credentials
 WHERE auth_user_id=v_uid AND person_id=v_p.person_id
   AND credential_kind='supabase_auth_user' AND status='active'
   AND retired_at IS NULL;
 SELECT coalesce(nullif(btrim(a.display_name),''),nullif(btrim(v_p.name),''))
 INTO v_display_name FROM atlas.people a
 WHERE a.id=v_p.person_id AND a.status='active';
 IF v_display_name IS NULL THEN
   RAISE EXCEPTION 'Existing Person display identity missing' USING errcode='23514';
 END IF;

 SELECT * INTO v_binding FROM reality.auth_person_bindings
 WHERE auth_user_id=v_uid AND binding_state='active' AND retired_at IS NULL
 LIMIT 1;
 IF v_binding.id IS NOT NULL AND
    (v_binding.person_entity_id<>v_p.person_id OR v_binding.id<>v_c.id) THEN
   RAISE EXCEPTION 'Conflicting canonical Auth Person binding' USING errcode='23514';
 END IF;
 -- A legitimately admitted existing Person may have a different canonical
 -- stable-key scheme. Exact UUID + kind/state, not one historical key prefix,
 -- governs identity; an actual collision on the prospective key remains fatal.
 IF EXISTS (SELECT 1 FROM reality.entities e
            WHERE e.stable_key='legacy-atlas-person:'||v_p.person_id::text
              AND e.id<>v_p.person_id) THEN
   RAISE EXCEPTION 'Canonical Person stable key collision' USING errcode='23514';
 END IF;
 SELECT * INTO v_entity FROM reality.entities WHERE id=v_p.person_id;
 IF v_entity.id IS NOT NULL AND
    (v_entity.entity_kind<>'person' OR v_entity.identity_state<>'canonical') THEN
   RAISE EXCEPTION 'Existing Person UUID is not a canonical Person' USING errcode='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM reality.auth_person_bindings b
           WHERE b.id=v_c.id AND b.auth_user_id<>v_uid) THEN
   RAISE EXCEPTION 'Existing credential ID belongs to another Auth identity' USING errcode='23514';
 END IF;
 IF v_entity.id IS NULL THEN
   INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
   VALUES(v_p.person_id,'legacy-atlas-person:'||v_p.person_id::text,'person',v_display_name,'canonical',
     jsonb_build_object('admissionState','admit_as_is','legacyAtlasPeopleId',v_p.person_id,
                        'admissionBasis','verified existing Principal and legacy Auth credential',
                        'admittedAt',now()));
 END IF;
 IF v_binding.id IS NULL THEN
   INSERT INTO reality.auth_person_bindings(id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at)
   VALUES(v_c.id,v_uid,v_p.person_id,'active',
     jsonb_build_object('admissionState','admit_as_is','source','atlas.person_auth_credentials',
                        'legacyCredentialId',v_c.id,'legacyProvenance',v_c.provenance),
     v_c.bound_at);
 END IF;
 -- Explicit lineage must not contradict an existing mapping.
 SELECT * INTO v_lineage FROM compatibility.legacy_bindings
 WHERE legacy_schema='atlas' AND legacy_table='people' AND legacy_key=v_p.person_id::text;
 IF v_lineage.id IS NOT NULL AND
   (v_lineage.new_schema<>'reality' OR v_lineage.new_table<>'entities' OR v_lineage.new_id<>v_p.person_id) THEN
   RAISE EXCEPTION 'Person compatibility lineage contradiction' USING errcode='23514';
 END IF;
 IF v_lineage.id IS NULL THEN
   INSERT INTO compatibility.legacy_bindings(legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis)
   VALUES('atlas','people',v_p.person_id::text,'maps_to','reality','entities',v_p.person_id,
     jsonb_build_object('basis','admit_as_is verified identity'));
 END IF;
 SELECT * INTO v_lineage FROM compatibility.legacy_bindings
 WHERE legacy_schema='atlas' AND legacy_table='person_auth_credentials' AND legacy_key=v_c.id::text;
 IF v_lineage.id IS NOT NULL AND
   (v_lineage.new_schema<>'reality' OR v_lineage.new_table<>'auth_person_bindings' OR v_lineage.new_id<>v_c.id) THEN
   RAISE EXCEPTION 'Credential compatibility lineage contradiction' USING errcode='23514';
 END IF;
 IF v_lineage.id IS NULL THEN
   INSERT INTO compatibility.legacy_bindings(legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis)
   VALUES('atlas','person_auth_credentials',v_c.id::text,'maps_to','reality','auth_person_bindings',v_c.id,
     jsonb_build_object('basis','admit_as_is verified Auth credential'));
 END IF;
 IF NOT EXISTS(SELECT 1 FROM personal.atlases a
               WHERE a.person_entity_id=v_p.person_id AND a.native AND a.atlas_state='active') THEN
   RAISE EXCEPTION 'Canonical Person admission did not establish native Personal Atlas' USING errcode='23514';
 END IF;
 RETURN v_p.person_id;
END;
$admit$;

-- A user's own verified credential can establish an onboarding case only
-- AFTER canonical Person admission and active Atlas entitlement.
CREATE OR REPLACE FUNCTION atlas.ensure_personal_implementation_case_self_v1()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','reality','auth'
AS $case$
DECLARE
 v_uid uuid := auth.uid();
 v_principal_id uuid;
 v_person_id uuid;
 v_case_id uuid;
 v_created boolean := false;
 v_access jsonb;
BEGIN
 IF v_uid IS NULL THEN
   RAISE EXCEPTION 'Authenticated Atlas human required' USING errcode='42501';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid
                AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL
                AND (u.banned_until IS NULL OR u.banned_until<=now())) THEN
   RAISE EXCEPTION 'Verified active Atlas credential required' USING errcode='42501';
 END IF;
 v_person_id:=atlas.current_person_id_v1();
 v_principal_id:=atlas.current_principal_id_v1();
 IF v_person_id IS NULL OR v_principal_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM atlas.principals p WHERE p.id=v_principal_id
    AND p.user_id=v_uid AND p.person_id=v_person_id AND p.status='active'
 ) THEN
   RAISE EXCEPTION 'Canonical active Principal required' USING errcode='42501';
 END IF;
 v_access:=atlas.personal_atlas_access_status_self_api_v1();
 IF v_access->>'accessState'<>'active'
   OR coalesce((v_access->>'eligible')::boolean,false)=false
   OR coalesce((v_access->>'hasPrincipal')::boolean,false)=false THEN
   RAISE EXCEPTION 'Active Personal Atlas access required' USING errcode='42501';
 END IF;
 INSERT INTO atlas.implementation_cases(
   implementation_purchase_id,case_origin,personal_subject_person_entity_id,state,metadata
 ) VALUES (
   NULL,'personal_atlas',v_person_id,'in_implementation',
   jsonb_build_object('onboardingCaseVersion',1,'subjectKind','person',
                      'admissionBasis','verified_canonical_person_principal_and_entitlement')
 )
 ON CONFLICT (personal_subject_person_entity_id)
   WHERE case_origin='personal_atlas' DO NOTHING
 RETURNING id INTO v_case_id;
 IF v_case_id IS NOT NULL THEN v_created:=true; END IF;
 IF v_case_id IS NULL THEN
   SELECT c.id INTO STRICT v_case_id FROM atlas.implementation_cases c
   WHERE c.case_origin='personal_atlas' AND c.personal_subject_person_entity_id=v_person_id;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'implementationCaseId',v_case_id,'caseOrigin','personal_atlas',
   'created',v_created,'principalId',v_principal_id,
   'ledgerEntitlementCreated',false,'purchaseCreated',false,
   'practitionerAssigned',false
 );
END;
$case$;

-- Explicit self-service command can reconcile an existing, fully admitted
-- account after a reviewed release; reading the home screen does not write.
CREATE OR REPLACE FUNCTION public.ensure_personal_implementation_case_self_api_v1()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $rpc$ SELECT atlas.ensure_personal_implementation_case_self_v1(); $rpc$;

-- No browser role gets raw case access or generic privileged admission.
REVOKE ALL ON FUNCTION atlas.admit_existing_person_identity_self_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.ensure_personal_implementation_case_self_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ensure_personal_implementation_case_self_api_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_personal_implementation_case_self_api_v1() TO authenticated;

CREATE OR REPLACE FUNCTION atlas.begin_personal_atlas_self_api_v1(p_name text, p_timezone text DEFAULT 'America/Chicago'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_email text;
  v_name text;
  v_timezone text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_implementation_case_id uuid;
  v_implementation_purchase_id uuid;
  v_access_source text;
  v_complimentary_invite_id uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_name:=nullif(trim(p_name),'');
  v_timezone:=coalesce(nullif(trim(p_timezone),''),'America/Chicago');
  if v_name is null then raise exception 'Name required.' using errcode='22023'; end if;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then raise exception 'Unknown timezone.' using errcode='22023'; end if;

  select lower(email) into v_email from auth.users where id=v_user_id;
  select * into v_principal from atlas.principals where user_id=v_user_id limit 1;
  if v_principal.id is not null then
    -- Existing Principals must not bypass canonical Person admission.
    perform atlas.admit_existing_person_identity_self_v1();
    -- Only entitled users earn active personal onboarding cases.
    if coalesce((atlas.personal_atlas_access_status_self_api_v1()->>'eligible')::boolean,false) then
      perform atlas.ensure_personal_implementation_case_self_v1();
    end if;
    return jsonb_build_object('ok',true,'alreadyEstablished',true,'principalId',v_principal.id,'householdId',v_principal.active_household_id);
  end if;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where purchaser_email=v_email
    and purchase_state='active'
    and (claimed_by_user_id is null or claimed_by_user_id=v_user_id)
  order by purchased_at desc,id desc
  limit 1
  for update;

  if v_purchase.id is not null then
    v_access_source := 'personal_atlas_purchase';
  else
    select i.id into v_complimentary_invite_id
    from atlas.personal_atlas_complimentary_test_invitations i
    where i.claimed_by_user_id=v_user_id
      and i.email=v_email
      and i.state='issued'
      and i.claimed_at is not null
    limit 1;
    if v_complimentary_invite_id is not null then
      v_access_source := 'complimentary_testing';
    else
    select c.id,p.id
      into v_implementation_case_id,v_implementation_purchase_id
    from atlas.implementation_case_participants sponsor
    join atlas.implementation_cases c on c.id=sponsor.implementation_case_id
    join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
    where sponsor.human_user_id=v_user_id
      and sponsor.relationship_kind='setup_sponsor'
      and sponsor.active
      and c.state not in ('closed','cancelled')
      and p.purchase_state='active'
    order by p.purchased_at desc,c.id desc
    limit 1;

    if v_implementation_case_id is null then
      raise exception 'Active Atlas access required.' using errcode='42501';
    end if;
    v_access_source := 'organization_implementation_setup_sponsor';
    end if;
  end if;

  insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
  values(
    v_user_id,
    'person:'||v_user_id::text,
    v_name,
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id,
      'implementationPurchaseId',v_implementation_purchase_id
    ))
  )
  returning * into v_principal;

  insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
  values(
    v_principal.id,
    'home',
    'Home',
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  )
  returning * into v_household;

  update atlas.principals
  set active_household_id=v_household.id,updated_at=now()
  where id=v_principal.id
  returning * into v_principal;

  insert into atlas.household_members(household_id,user_id,display_name,relationship,household_role,active,metadata)
  values(
    v_household.id,
    v_user_id,
    v_name,
    'self',
    'principal',
    true,
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  );

  if v_purchase.id is not null then
    update atlas.personal_atlas_purchases
    set claimed_by_user_id=v_user_id,
        claimed_principal_id=v_principal.id,
        claimed_at=coalesce(claimed_at,now()),
        updated_at=now()
    where id=v_purchase.id;
  end if;

  if v_complimentary_invite_id is not null then
    perform public.grant_personal_atlas_access_v1(
      v_principal.id,'complimentary_testing',
      jsonb_build_object('authority','verified_email_invitation',
                         'invitationId',v_complimentary_invite_id)
    );
  end if;

  -- Complete exactly one canonical identity and personal case in this transaction.
  perform atlas.admit_existing_person_identity_self_v1();
  perform atlas.ensure_personal_implementation_case_self_v1();

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'alreadyEstablished',false,
    'principalId',v_principal.id,
    'householdId',v_household.id,
    'purchaseId',v_purchase.id,
    'implementationCaseId',v_implementation_case_id,
    'accessBasis',v_access_source
  ));
end;
$function$;


-- Paid purchases are deliberately untouched. Versioned Workbench projection
-- can represent both real commercial and real Personal Atlas cases.
CREATE OR REPLACE FUNCTION atlas.implementation_workbench_self_api_v2()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $workbench$
  WITH allowed AS (
    SELECT atlas.implementation_practitioner_authorized_self_v1() AS ok
  ), cases AS (
    SELECT c.id,c.state,c.case_origin,c.opened_at,
      p.starting_label AS commercial_label,
      e.display_name AS person_label,
      p.payment_option,p.setup_contract_amount_cents,p.monthly_ledger_unit_price_cents,
      p.purchased_at,
      EXISTS(SELECT 1 FROM atlas.implementation_case_participants cp
             WHERE cp.implementation_case_id=c.id AND cp.relationship_kind='setup_sponsor' AND cp.active)
             AS has_setup_sponsor,
      (SELECT count(*) FROM atlas.ledger_entitlements le WHERE le.implementation_case_id=c.id)
             AS entitlement_count,
      (SELECT count(*) FROM atlas.ledger_entitlements le WHERE le.implementation_case_id=c.id
             AND le.state='activated') AS activated_entitlement_count,
      EXISTS(SELECT 1 FROM atlas.implementation_case_participants cp
             WHERE cp.implementation_case_id=c.id AND cp.relationship_kind='practitioner'
             AND cp.active AND cp.human_user_id=auth.uid()) AS assigned_to_me,
      EXISTS(SELECT 1 FROM atlas.implementation_case_participants cp
             WHERE cp.implementation_case_id=c.id AND cp.relationship_kind='practitioner'
             AND cp.active) AS has_practitioner
    FROM atlas.implementation_cases c
    LEFT JOIN atlas.implementation_purchases p ON p.id=c.implementation_purchase_id
    LEFT JOIN reality.entities e ON e.id=c.personal_subject_person_entity_id
      AND e.entity_kind='person' AND e.identity_state='canonical'
    WHERE (c.case_origin='personal_atlas' AND c.state<>'cancelled')
       OR (c.case_origin='paid_institutional'
           AND c.state NOT IN ('closed','cancelled') AND p.purchase_state='active')
  )
  SELECT CASE WHEN NOT (SELECT ok FROM allowed)
    THEN jsonb_build_object('ok',false,'code','practitioner_authority_required','items','[]'::jsonb)
    ELSE jsonb_build_object('ok',true,'contractVersion','implementation_workbench_self_api_v2',
      'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'implementationCaseId',c.id,'caseOrigin',c.case_origin,'state',c.state,
        'startingLabel',CASE WHEN c.case_origin='personal_atlas'
          THEN coalesce(c.person_label,'Personal Atlas') ELSE c.commercial_label END,
        'paymentOption',c.payment_option,
        'setupContractAmountCents',c.setup_contract_amount_cents,
        'monthlyLedgerUnitPriceCents',c.monthly_ledger_unit_price_cents,
        'purchasedAt',c.purchased_at,'openedAt',c.opened_at,
        'hasSetupSponsor',c.has_setup_sponsor,
        'requiresSetupSponsor',c.case_origin='paid_institutional',
        'ledgerEntitlementCount',c.entitlement_count,
        'activatedLedgerEntitlementCount',c.activated_entitlement_count,
        'assignedToMe',c.assigned_to_me,'hasPractitioner',c.has_practitioner,
        'attentionState',CASE
           WHEN c.case_origin='personal_atlas' AND c.state='closed' THEN 'complete'
           WHEN c.case_origin='personal_atlas' AND NOT c.has_practitioner THEN 'atlas_handling'
           WHEN c.case_origin='personal_atlas' THEN 'in_implementation'
           WHEN NOT c.has_setup_sponsor THEN 'waiting_on_person'
           WHEN NOT c.has_practitioner THEN 'needs_practitioner'
           ELSE 'in_implementation' END
      ) ORDER BY CASE WHEN c.case_origin='paid_institutional' THEN 0 ELSE 1 END,
        coalesce(c.purchased_at,c.opened_at) DESC,c.id)
      FROM cases c),'[]'::jsonb))
  END;
$workbench$;

CREATE OR REPLACE FUNCTION public.implementation_workbench_self_api_v2()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $rpc$ SELECT atlas.implementation_workbench_self_api_v2(); $rpc$;

REVOKE ALL ON FUNCTION atlas.implementation_workbench_self_api_v2() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.implementation_workbench_self_api_v2() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.implementation_workbench_self_api_v2() TO authenticated;


CREATE OR REPLACE FUNCTION atlas.implementation_case_self_api_v2(p_implementation_case_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_case_self_api_v1',
    'case',jsonb_build_object(
      'id',c.id,'state',c.state,'openedAt',c.opened_at,
      'caseOrigin',c.case_origin,
      'startingLabel',CASE WHEN c.case_origin='personal_atlas' THEN coalesce(e.display_name,'Personal Atlas') ELSE p.starting_label END,
      'personalCase',c.case_origin='personal_atlas',
      'purchase',case when c.case_origin='paid_institutional' then jsonb_build_object(
        'id',p.id,'startingLabel',p.starting_label,'paymentOption',p.payment_option,
        'setupContractAmountCents',p.setup_contract_amount_cents,
        'monthlyLedgerUnitPriceCents',p.monthly_ledger_unit_price_cents,
        'purchasedAt',p.purchased_at,'purchaseState',p.purchase_state
      ) else null end,
      'participants',coalesce((select jsonb_agg(jsonb_build_object(
        'id',cp.id,'relationshipKind',cp.relationship_kind,'active',cp.active,
        'verifiedAt',cp.verified_at,'startedAt',cp.started_at,
        'isMe',cp.human_user_id=auth.uid()
      ) order by cp.started_at,cp.id) from atlas.implementation_case_participants cp where cp.implementation_case_id=c.id),'[]'::jsonb),
      'ledgerEntitlements',coalesce((select jsonb_agg(jsonb_build_object(
        'id',le.id,'number',le.entitlement_number,'state',le.state,
        'priceClass',le.price_class,'setupPriceCents',le.setup_price_cents,
        'monthlyPriceCents',le.monthly_price_cents,'recurringStartsAt',le.recurring_starts_at,
        'binding',(
          select jsonb_build_object(
            'id',b.id,'state',b.state,'organizationId',b.organization_id,
            'organizationName',o.name,
            'organizationUnitId',b.organization_unit_id,'organizationUnitName',ou.name,
            'boundAt',b.bound_at,'activatedAt',b.activated_at
          )
          from atlas.ledger_entitlement_bindings b
          join atlas.organizations o on o.id=b.organization_id
          left join atlas.organization_units ou on ou.id=b.organization_unit_id and ou.organization_id=b.organization_id
          where b.ledger_entitlement_id=le.id and b.ended_at is null limit 1
        )
      ) order by le.entitlement_number) from atlas.ledger_entitlements le where le.implementation_case_id=c.id),'[]'::jsonb)
    )
  ) into v_result
  from atlas.implementation_cases c
  LEFT JOIN atlas.implementation_purchases p ON p.id=c.implementation_purchase_id
  LEFT JOIN reality.entities e ON e.id=c.personal_subject_person_entity_id
    AND e.entity_kind='person' AND e.identity_state='canonical'
  where c.id=p_implementation_case_id;

  return coalesce(v_result,jsonb_build_object('ok',false,'code','case_not_found'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.implementation_case_self_api_v2(p_implementation_case_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $rpc$ SELECT atlas.implementation_case_self_api_v2(p_implementation_case_id); $rpc$;
REVOKE ALL ON FUNCTION atlas.implementation_case_self_api_v2(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.implementation_case_self_api_v2(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.implementation_case_self_api_v2(uuid) TO authenticated;

COMMIT;
