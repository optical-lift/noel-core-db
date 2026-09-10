-- Human Reality Library v1.
-- These world-kernel definitions describe ordinary recurring human realities and their lifecycle shape.
-- Their existence in the library is NOT a claim that they apply to any particular Principal/household.
-- Reality Discovery may raise their relevance; only canonical subject/obligation authority may establish applicability.

insert into atlas.world_kernel_definitions(kernel_key,version,scope_kind,title,definition,active)
values
('household.vehicle_registration',1,'household','Vehicle registration',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('vehicle_exists','jurisdiction_known','registration_requirement_established','renewal_window','renewal_action','registration_evidence','next_cycle'),
  'dependencies',jsonb_build_array('vehicle','jurisdiction','registration_status','expiration_or_renewal_rule','required_documents','fees','inspection_or_tax_prerequisites'),
  'nonClaims',jsonb_build_array('vehicle_exists','vehicle_owned','registration_required','registration_jurisdiction','renewal_date','inspection_required','tax_due','fee_amount'),
  'autoplayGoal','Keep lawful vehicle registration from depending on human memory while asking for the smallest missing fact before the next real renewal consequence.',
  'contractVersion','human_reality_vehicle_registration_v1'
),'true'),
('household.vehicle_maintenance',1,'household','Vehicle maintenance',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('vehicle_exists','vehicle_identified','maintenance_basis_known','attention_window','service_path','service_result','usage_or_mileage_update','next_attention'),
  'dependencies',jsonb_build_array('vehicle_identity','manufacturer_guidance','usage','mileage','service_history','provider_or_diy_path'),
  'nonClaims',jsonb_build_array('vehicle_exists','vehicle_make','vehicle_model','vehicle_year','mileage','oil_interval','service_due','service_provider'),
  'autoplayGoal','Advance each confirmed vehicle from service evidence to the next appropriate maintenance attention without recreating the cycle as tasks.',
  'contractVersion','human_reality_vehicle_maintenance_v1'
),'true'),
('household.residence_maintenance',1,'household','Residence maintenance',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('residence_exists','responsibility_boundary','systems_discovered','care_requirements','attention_windows','care_or_escalation','result','next_attention'),
  'dependencies',jsonb_build_array('residence_arrangement','dwelling_form','repair_responsibility','actual_systems','actual_equipment','climate_or_season_when_relevant'),
  'nonClaims',jsonb_build_array('home_owned','major_repairs_are_principal_responsibility','hvac_exists','water_heater_type','well_exists','septic_exists','yard_exists','specific_cadence'),
  'autoplayGoal','Carry only the home systems this household is actually responsible for, and route landlord/property-manager issues differently from owner maintenance.',
  'contractVersion','human_reality_residence_maintenance_v1'
),'true'),
('household.property_tax_administration',1,'household','Property tax administration',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('taxable_property_relationship','jurisdiction','obligation_applicability','assessment_or_notice','review','payment_or_dispute','receipt','next_cycle'),
  'dependencies',jsonb_build_array('property_relationship','jurisdiction','taxing_authority','assessment_or_notice','due_rule'),
  'nonClaims',jsonb_build_array('property_owned','property_tax_due','personal_property_tax_due','jurisdiction','amount','due_date'),
  'autoplayGoal','Recognize and carry confirmed property-tax cycles without treating home ownership alone as proof of a specific tax obligation.',
  'contractVersion','human_reality_property_tax_v1'
),'true'),
('person.income_tax_filing',1,'person','Income tax filing',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('filing_context','documents_expected','documents_received','prepare_or_provider','review','file','pay_or_refund','confirmation','retain_records','next_tax_year'),
  'dependencies',jsonb_build_array('jurisdiction','filing_context','income_evidence','tax_documents','provider_or_self_prepare_path','filing_deadline'),
  'nonClaims',jsonb_build_array('filing_required','filing_status','income_source','tax_due','refund_due','deadline_extension','provider'),
  'autoplayGoal','Carry the administrative tax cycle from expected records through filing evidence without inventing tax advice or liability.',
  'contractVersion','human_reality_income_tax_v1'
),'true'),
('person.identity_document_renewal',1,'person','Identity document renewal',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('document_exists','document_identity','expiration_or_validity_rule','renewal_window','requirements','renewal_action','new_document_evidence','next_cycle'),
  'dependencies',jsonb_build_array('document_type','issuing_authority','expiration','renewal_requirements'),
  'nonClaims',jsonb_build_array('driver_license_exists','passport_exists','document_expiration','renewal_eligibility','required_documents','fee_amount'),
  'autoplayGoal','Ask for document details only when they let Atlas prevent a renewal from becoming an emergency.',
  'contractVersion','human_reality_identity_document_renewal_v1'
),'true'),
('household.hvac_filter_care',1,'household','HVAC filter care',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('system_exists','responsibility_boundary','filter_present','filter_identity','replacement_basis','supply_ready','replace','result','next_attention'),
  'dependencies',jsonb_build_array('hvac_system','responsibility','filter_type_or_size','manufacturer_or_household_basis','inventory'),
  'nonClaims',jsonb_build_array('hvac_exists','filter_exists','filter_size','replacement_interval','household_responsible'),
  'autoplayGoal','Carry filter replacement only after the actual system, filter, responsibility, and useful replacement basis are established.',
  'contractVersion','human_reality_hvac_filter_v1'
),'true'),
('household.water_heater_care',1,'household','Water heater care',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('system_exists','responsibility_boundary','system_type','care_guidance','attention_window','care_or_provider','result','next_attention'),
  'dependencies',jsonb_build_array('water_heater','tenure_or_repair_responsibility','system_type','manufacturer_or_provider_guidance'),
  'nonClaims',jsonb_build_array('water_heater_exists','tank_or_tankless','household_responsible','flush_required','specific_interval'),
  'autoplayGoal','Keep water-heater care with the responsible party and never turn ordinary homeowner advice into a claimed requirement for a renter.',
  'contractVersion','human_reality_water_heater_v1'
),'true'),
('household.smoke_co_safety',1,'household','Smoke and carbon-monoxide safety',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('devices_or_requirement_discovered','responsibility_boundary','device_identity_or_location','test_or_replacement_basis','attention','result','next_attention'),
  'dependencies',jsonb_build_array('residence','actual_devices','local_requirement_when_relevant','device_guidance','responsibility'),
  'nonClaims',jsonb_build_array('device_exists','device_count','battery_type','replacement_interval','co_detector_required','principal_responsible'),
  'autoplayGoal','Carry confirmed household safety-device testing/replacement without fabricating devices or local requirements.',
  'contractVersion','human_reality_smoke_co_v1'
),'true'),
('household.animal_veterinary_care',1,'household','Animal veterinary care',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('animal_exists','animal_identity','care_responsibility','provider_or_care_path','preventive_requirements','attention_window','visit_or_treatment','result','next_attention'),
  'dependencies',jsonb_build_array('animal','species','age_when_relevant','vet_provider','vaccination_or_medication_evidence','jurisdiction_when_licensing_matters'),
  'nonClaims',jsonb_build_array('animal_exists','species','vaccination_required','license_required','medication','provider','specific_interval'),
  'autoplayGoal','Carry only the care cycles established for actual animals in the household.',
  'contractVersion','human_reality_animal_vet_v1'
),'true'),
('household.school_calendar_administration',1,'household','School calendar administration',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('student_relationship','school_or_program','calendar_source','dates_and_breaks','forms_or_requirements','household_capacity_effects','changes','next_term'),
  'dependencies',jsonb_build_array('child_or_dependent','school_or_program','calendar_source','responsibility','transport_or_activity_constraints'),
  'nonClaims',jsonb_build_array('child_exists','school_enrollment','school_identity','calendar_dates','parental_responsibility','transport_required'),
  'autoplayGoal','Let one confirmed school/calendar source answer many future household scheduling questions.',
  'contractVersion','human_reality_school_calendar_v1'
),'true'),
('person.preventive_dental_care',1,'person','Preventive dental care',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('care_path_exists','provider_or_search','recommended_or_personal_interval','attention_window','schedule','appointment','result','next_attention'),
  'dependencies',jsonb_build_array('person','provider_or_search_path','explicit_care_interval_or_visit_result'),
  'nonClaims',jsonb_build_array('provider_exists','six_month_interval','appointment_due','insurance_coverage','clinical_need'),
  'autoplayGoal','Carry appointment logistics from confirmed care history or explicit preference without diagnosing or inventing a clinical schedule.',
  'contractVersion','human_reality_dental_v1'
),'true'),
('person.preventive_vision_care',1,'person','Preventive vision care',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('care_path_exists','provider_or_search','recommended_or_personal_interval','attention_window','schedule','appointment','result','next_attention'),
  'dependencies',jsonb_build_array('person','provider_or_search_path','explicit_care_interval_or_visit_result'),
  'nonClaims',jsonb_build_array('provider_exists','annual_interval','appointment_due','glasses_or_contacts','insurance_coverage','clinical_need'),
  'autoplayGoal','Carry vision-care logistics only from confirmed care reality, not from an assumed medical need.',
  'contractVersion','human_reality_vision_v1'
),'true'),
('household.recurring_bills',1,'household','Recurring bills',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('obligation_observed','obligation_identity','amount_or_rule','payment_path','due_window','paid_or_failed','reconcile','next_cycle'),
  'dependencies',jsonb_build_array('provider_or_payee','account_or_contract','payment_evidence','due_rule','responsibility'),
  'nonClaims',jsonb_build_array('bill_exists','amount','due_date','autopay','principal_responsible','account_balance'),
  'autoplayGoal','Learn recurring obligations preferentially from evidence and ask only for the missing responsibility or timing detail needed to keep them safe.',
  'contractVersion','human_reality_recurring_bills_v1'
),'true'),
('household.insurance_renewal',1,'household','Insurance renewal',jsonb_build_object(
  'ordinary',true,
  'topology',jsonb_build_array('policy_exists','insured_subject','responsibility','coverage_term','renewal_window','review_or_shop','renew','evidence','next_term'),
  'dependencies',jsonb_build_array('policy','insured_subject','provider','term_dates','responsibility'),
  'nonClaims',jsonb_build_array('policy_exists','coverage_required','provider','premium','renewal_date','adequacy_of_coverage'),
  'autoplayGoal','Carry confirmed policy renewal logistics without deciding coverage adequacy or inventing insurance requirements.',
  'contractVersion','human_reality_insurance_renewal_v1'
),'true')
on conflict(kernel_key,version) do update set
  scope_kind=excluded.scope_kind,title=excluded.title,definition=excluded.definition,active=true;

-- Discovery relevance rules are proposals about what may be worth learning, never kernel-instance authority.
create table if not exists atlas.reality_discovery_kernel_rules (
  id uuid primary key default gen_random_uuid(),
  kernel_key text not null,
  kernel_version integer not null,
  signal_key text not null,
  match_operator text not null check (match_operator in ('exists','eq','neq','in','not_in')),
  compare_value jsonb,
  effect_kind text not null check (effect_kind in ('require','boost','suppress')),
  weight integer not null default 0,
  reason_text text,
  created_at timestamptz not null default now(),
  foreign key(kernel_key,kernel_version) references atlas.world_kernel_definitions(kernel_key,version) on delete cascade
);

create unique index if not exists reality_discovery_kernel_rules_logical_uidx
  on atlas.reality_discovery_kernel_rules(
    kernel_key,kernel_version,signal_key,match_operator,effect_kind,(coalesce(compare_value::text,'__null__'))
  );

alter table atlas.reality_discovery_kernel_rules enable row level security;
revoke all on atlas.reality_discovery_kernel_rules from public,anon,authenticated;

insert into atlas.reality_discovery_kernel_rules(kernel_key,kernel_version,signal_key,match_operator,compare_value,effect_kind,weight,reason_text) values
('household.vehicle_registration',1,'transport.vehicle_count','in','["one","two_plus","other"]'::jsonb,'require',0,'Vehicle registration is worth discovering only after vehicle responsibility exists.'),
('household.vehicle_maintenance',1,'transport.vehicle_count','in','["one","two_plus","other"]'::jsonb,'require',0,'Vehicle maintenance is worth discovering only after vehicle responsibility exists.'),
('household.residence_maintenance',1,'home.tenure','exists',null,'require',0,'Residence maintenance begins from a real residence relationship.'),
('household.residence_maintenance',1,'home.major_repairs_responsibility','eq','"landlord"'::jsonb,'boost',-40,'Landlord responsibility shifts the lifecycle toward report/follow-up rather than owner maintenance.'),
('household.property_tax_administration',1,'home.tenure','eq','"own"'::jsonb,'require',0,'Ownership makes property-tax applicability worth resolving but does not prove tax is due.'),
('household.hvac_filter_care',1,'home.major_repairs_responsibility','in','["me","shared","depends"]'::jsonb,'require',0,'Ask about HVAC/filter care only when household responsibility remains plausible.'),
('household.water_heater_care',1,'home.major_repairs_responsibility','in','["me","shared","depends"]'::jsonb,'require',0,'Ask about water-heater care only when household responsibility remains plausible.'),
('household.smoke_co_safety',1,'home.tenure','exists',null,'require',0,'Residence existence makes safety-device applicability worth resolving.'),
('household.animal_veterinary_care',1,'animals.responsibility','not_in','["none",null]'::jsonb,'require',0,'Animal-care kernels require actual animal responsibility testimony.'),
('household.school_calendar_administration',1,'children.school_calendar','eq','"yes"'::jsonb,'require',0,'School-calendar administration requires explicit school/preschool/daycare applicability.'),
('household.recurring_bills',1,'household.exists','eq','true'::jsonb,'boost',15,'Every household may have recurring obligations, but evidence should establish the actual bills.'),
('person.income_tax_filing',1,'principal.exists','eq','true'::jsonb,'boost',10,'Tax filing is a common administrative possibility but still requires jurisdiction/filing applicability.'),
('person.identity_document_renewal',1,'principal.exists','eq','true'::jsonb,'boost',10,'Identity documents are common possibilities but must be individually established.'),
('person.preventive_dental_care',1,'principal.exists','eq','true'::jsonb,'boost',5,'Preventive dental logistics may be useful but clinical need/cadence is never inferred.'),
('person.preventive_vision_care',1,'principal.exists','eq','true'::jsonb,'boost',5,'Preventive vision logistics may be useful but clinical need/cadence is never inferred.'),
('household.insurance_renewal',1,'household.exists','eq','true'::jsonb,'boost',5,'Insurance policies must be established from actual policy/evidence before renewal consequences exist.')
on conflict do nothing;

create or replace function atlas.reality_discovery_kernel_relevance_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_signals jsonb;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);

  with library as (
    select d.kernel_key,d.version,d.scope_kind,d.title,d.definition
    from atlas.world_kernel_definitions d
    where d.active and coalesce((d.definition->>'ordinary')::boolean,false)=true
  ), evaluated as (
    select
      l.*,
      coalesce(bool_and(atlas.reality_discovery_edge_matches_v1(v_signals->r.signal_key,r.match_operator,r.compare_value))
        filter(where r.effect_kind='require'),true) as requirements_met,
      coalesce(bool_or(atlas.reality_discovery_edge_matches_v1(v_signals->r.signal_key,r.match_operator,r.compare_value))
        filter(where r.effect_kind='suppress'),false) as suppressed,
      coalesce(sum(r.weight) filter(
        where r.effect_kind='boost'
          and atlas.reality_discovery_edge_matches_v1(v_signals->r.signal_key,r.match_operator,r.compare_value)
      ),0)::integer as relevance_score,
      coalesce(jsonb_agg(r.reason_text) filter(
        where r.reason_text is not null
          and atlas.reality_discovery_edge_matches_v1(v_signals->r.signal_key,r.match_operator,r.compare_value)
      ),'[]'::jsonb) as matched_reasons
    from library l
    left join atlas.reality_discovery_kernel_rules r
      on r.kernel_key=l.kernel_key and r.kernel_version=l.version
    group by l.kernel_key,l.version,l.scope_kind,l.title,l.definition
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kernelKey',e.kernel_key,
    'version',e.version,
    'scopeKind',e.scope_kind,
    'title',e.title,
    'relevanceState',case when e.suppressed or not e.requirements_met then 'latent' else 'worth_discovering' end,
    'relevanceScore',e.relevance_score,
    'matchedReasons',e.matched_reasons,
    'autoplayGoal',e.definition->>'autoplayGoal',
    'nonClaims',coalesce(e.definition->'nonClaims','[]'::jsonb)
  ) order by
    case when e.suppressed or not e.requirements_met then 1 else 0 end,
    e.relevance_score desc,e.kernel_key),'[]'::jsonb)
  into v_items
  from evaluated e;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_kernel_relevance_self_api_v1',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'libraryDefinitionDoesNotEstablishApplicability',true,
      'worthDiscoveringDoesNotCreateKernelInstance',true,
      'kernelApplicabilityRequiresOwningDomainTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_kernel_relevance_self_api_v1() from public,anon;
grant execute on function atlas.reality_discovery_kernel_relevance_self_api_v1() to authenticated,service_role;

create or replace function public.reality_discovery_kernel_relevance_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.reality_discovery_kernel_relevance_self_api_v1(); $function$;
revoke all on function public.reality_discovery_kernel_relevance_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_kernel_relevance_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values(
  'atlas.reality_discovery_kernel_relevance_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object('purpose','Project which latent Human Reality Library kernels are worth discovering from current confirmed/candidate discovery context without instantiating them.'),now()
)
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();
