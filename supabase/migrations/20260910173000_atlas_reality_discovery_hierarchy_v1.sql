begin;

-- Deepen the adaptive Reality Discovery hierarchy after the first graph/residence proof.
-- Broad household/place-shape answers are discovery evidence used to choose better questions;
-- they do not create unnamed household members or inferred equipment/animals.

-- Make graph seed reruns/maintenance deterministic rather than accumulating duplicate logical edges.
delete from atlas.reality_discovery_edges a
using atlas.reality_discovery_edges b
where a.id>b.id
  and a.question_key=b.question_key
  and a.signal_key=b.signal_key
  and a.operator=b.operator
  and a.effect_kind=b.effect_kind
  and coalesce(a.compare_value::text,'__null__')=coalesce(b.compare_value::text,'__null__');

create unique index if not exists reality_discovery_edges_logical_uidx
  on atlas.reality_discovery_edges(
    question_key,signal_key,operator,effect_kind,(coalesce(compare_value::text,'__null__'))
  );

insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,reason_text,metadata
) values
(
  'household.people_shape','people','Who shares your home with you?',
  'This is only the broad shape for now. Atlas can learn names and exact relationships when they become useful.',
  'single_choice',
  '[{"key":"just_me","label":"just me"},{"key":"partner","label":"partner / spouse"},{"key":"partner_children","label":"partner + children"},{"key":"children","label":"children"},{"key":"roommates","label":"roommates / other adults"},{"key":"other","label":"something else"}]'::jsonb,
  90,1,75,95,'household.people_shape',
  'Household shape changes which school, caregiving, capacity, vehicle, food, cleaning, laundry, and responsibility branches are worth asking about.',
  '{}'::jsonb
),
(
  'household.child_count','people','How many children live here?',null,'single_choice',
  '[{"key":"1","label":"1"},{"key":"2","label":"2"},{"key":"3","label":"3"},{"key":"4","label":"4"},{"key":"5_plus","label":"5 or more"}]'::jsonb,
  55,1,65,80,'household.child_count',
  'Child count changes the likely scale of school, transportation, laundry, food, care, and household coordination.',
  '{}'::jsonb
),
(
  'home.setting','home','Which sounds most like where you live?',
  'Atlas asks this only when it does not already have a trustworthy place-context classification.',
  'single_choice',
  '[{"key":"dense_city","label":"dense city"},{"key":"city","label":"city"},{"key":"suburb","label":"suburb"},{"key":"small_town","label":"small town"},{"key":"rural","label":"rural / country"},{"key":"other","label":"something else"}]'::jsonb,
  65,1,55,85,'home.setting',
  'The physical setting changes which transportation, land, building, and equipment questions are plausible.',
  '{}'::jsonb
),
(
  'home.dwelling_kind','home','What kind of home is it?',null,'single_choice',
  '[{"key":"house","label":"house"},{"key":"apartment","label":"apartment"},{"key":"condo","label":"condo"},{"key":"townhome","label":"townhome"},{"key":"manufactured","label":"manufactured / mobile home"},{"key":"other","label":"something else"}]'::jsonb,
  45,1,50,70,'home.dwelling_kind',
  'Dwelling form changes which home systems and shared-building responsibilities are likely to matter.',
  '{}'::jsonb
),
(
  'grounds.scale','home','How much outdoor space are you responsible for?',null,'single_choice',
  '[{"key":"small_yard","label":"small yard"},{"key":"large_yard","label":"large yard"},{"key":"acreage","label":"acreage"},{"key":"mixed","label":"a mix"},{"key":"not_sure","label":"not sure"}]'::jsonb,
  35,1,45,65,'grounds.scale',
  'Outdoor scale helps Atlas decide whether equipment and seasonal land-care questions are worth asking next.',
  '{}'::jsonb
)
on conflict(question_key) do update set
  section_key=excluded.section_key,prompt=excluded.prompt,help_text=excluded.help_text,
  answer_kind=excluded.answer_kind,options=excluded.options,base_score=excluded.base_score,
  friction=excluded.friction,consequence_value=excluded.consequence_value,information_gain=excluded.information_gain,
  resolved_signal_key=excluded.resolved_signal_key,reason_text=excluded.reason_text,active=true,
  metadata=excluded.metadata,updated_at=now();

insert into atlas.reality_discovery_edges(question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text) values
('household.child_count','household.has_children','eq','true'::jsonb,'require',0,'Only ask child count when children are already indicated by canonical people or household-shape testimony.'),
('children.school_calendar','household.large_family','eq','true'::jsonb,'boost',30,'A larger child-bearing household raises the value of resolving shared school/calendar structure early.'),
('home.setting','home.tenure','exists',null,'require',0,'Resolve basic residence relationship before asking for physical setting when no trusted classifier has done it.'),
('home.dwelling_kind','home.tenure','exists',null,'require',0,'Dwelling form becomes useful once Atlas knows this is the household residence arrangement.'),
('grounds.responsibility','home.tenure','exists',null,'require',0,'Do not ask about grounds before the residence relationship is established.'),
('grounds.scale','grounds.responsibility','in','["yes","shared"]'::jsonb,'require',0,'Outdoor scale matters only when this household has grounds responsibility.'),
('grounds.mowing_method','grounds.scale','exists',null,'boost',25,'Known outdoor scale makes mowing method more useful.'),
('transport.vehicle_count','household.large_family','eq','true'::jsonb,'boost',25,'A larger household raises the value of resolving vehicle responsibility early.'),
('transport.vehicle_count','context.low_density_owner_household','eq','true'::jsonb,'boost',25,'A rural owner household raises the value of vehicle/admin discovery.'),
('animals.responsibility','household.large_family','eq','true'::jsonb,'boost',10,'Larger household shape modestly raises animal-care applicability without asserting an animal exists.'),
('grounds.responsibility','context.dense_urban_renter','eq','true'::jsonb,'suppress',0,'Dense-city renter context strongly suppresses ordinary private-grounds questioning.'),
('grounds.mowing_method','context.dense_urban_renter','eq','true'::jsonb,'suppress',0,'Dense-city renter context suppresses ordinary mowing questions.'),
('equipment.riding_mower_identity','context.dense_urban_renter','eq','true'::jsonb,'suppress',0,'Dense-city renter context suppresses riding-mower discovery unless materially new evidence changes the context.'),
('laundry.location','context.dense_urban_renter','eq','true'::jsonb,'boost',35,'Dense-city rental context raises the value of learning whether laundry is in-unit, shared, or external.')
on conflict do nothing;

create or replace function atlas.reality_discovery_context_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_residence atlas.household_residence_arrangements%rowtype;
  v_member_count integer:=0;
  v_named_child_count integer:=0;
  v_answers jsonb:='{}'::jsonb;
  v_candidates jsonb:='{}'::jsonb;
  v_signals jsonb:='{}'::jsonb;
  v_purchase_address jsonb;
  v_purchase_phone jsonb;
  v_people_shape text;
  v_child_count_answer text;
  v_has_children boolean:=false;
  v_large_family boolean:=false;
  v_tenure text;
  v_repairs text;
  v_setting text;
  v_dwelling_kind text;
  v_grounds text;
  v_grounds_scale text;
  v_mowing text;
  v_vehicle_count text;
  v_address_confirmed boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  select * into v_household from atlas.households where id=v_principal.active_household_id and status='active';

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where claimed_by_user_id=v_user_id and claimed_principal_id=v_principal.id
  order by purchased_at desc,id desc limit 1;

  select * into v_residence
  from atlas.household_residence_arrangements
  where household_id=v_household.id and active
  order by case when stable_key='primary-home' then 0 else 1 end,confirmed_at desc nulls last,id
  limit 1;

  v_purchase_address:=case
    when v_purchase.metadata ? 'billingAddress' and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress' else null end;
  v_purchase_phone:=case
    when nullif(trim(v_purchase.metadata->>'phone'),'') is not null then to_jsonb(trim(v_purchase.metadata->>'phone'))
    else null end;

  select count(*)::integer,
         count(*) filter(where lower(coalesce(relationship,'')) ~ '(child|daughter|son|kid)')::integer
  into v_member_count,v_named_child_count
  from atlas.household_members
  where household_id=v_household.id and active;

  v_answers:=atlas.reality_discovery_latest_answers_v1(v_principal.id);

  -- Only confirmed/promoted generic discovery evidence may become branch-driving context.
  -- Source candidates remain proposals. Purchase address/phone are separately admitted below because
  -- they are explicitly candidate evidence used to ask for confirmation, not trusted context.
  select coalesce(jsonb_object_agg(signal_key,candidate_value),'{}'::jsonb)
  into v_candidates
  from (
    select distinct on(signal_key) signal_key,candidate_value
    from atlas.reality_discovery_evidence_candidates
    where principal_id=v_principal.id
      and epistemic_state in ('human_confirmed','promoted')
    order by signal_key,
      case epistemic_state when 'promoted' then 1 else 2 end,
      updated_at desc,id desc
  ) c;

  if v_purchase_address is not null
     and coalesce(v_answers#>>'{home.confirm_purchase_address}','') <> 'no' then
    v_candidates:=v_candidates||jsonb_build_object('purchase.billing_address',v_purchase_address);
  end if;
  if v_purchase_phone is not null then
    v_candidates:=v_candidates||jsonb_build_object('purchase.phone',v_purchase_phone);
  end if;

  v_people_shape:=v_answers#>>'{household.people_shape}';
  v_child_count_answer:=v_answers#>>'{household.child_count}';
  v_has_children:=v_named_child_count>0 or v_people_shape in ('partner_children','children');
  v_large_family:=v_member_count>=5 or v_child_count_answer in ('4','5_plus');
  v_address_confirmed:=v_residence.id is not null and v_residence.address is not null;
  v_tenure:=coalesce(v_residence.tenure_kind,v_answers#>>'{home.tenure}');
  v_repairs:=coalesce(v_residence.major_repairs_responsibility,v_answers#>>'{home.major_repairs}');
  v_setting:=coalesce(v_candidates#>>'{context.residence_setting}',v_answers#>>'{home.setting}');
  v_dwelling_kind:=v_answers#>>'{home.dwelling_kind}';
  v_grounds:=v_answers#>>'{grounds.responsibility}';
  v_grounds_scale:=v_answers#>>'{grounds.scale}';
  v_mowing:=v_answers#>>'{grounds.mowing_method}';
  v_vehicle_count:=v_answers#>>'{transport.vehicle_count}';

  v_signals:=jsonb_build_object(
    'principal.exists',true,
    'household.exists',v_household.id is not null,
    'household.member_count',v_member_count,
    'household.member_count_bucket',case when v_member_count<=1 then 'one' when v_member_count<=3 then 'small' else 'large' end,
    'household.people_shape',v_people_shape,
    'household.has_children',v_has_children,
    'household.named_child_count',v_named_child_count,
    'household.child_count',v_child_count_answer,
    'household.large_family',v_large_family,
    'home.address_confirmed',v_address_confirmed,
    'home.tenure',v_tenure,
    'home.major_repairs_responsibility',v_repairs,
    'home.setting',v_setting,
    'home.dwelling_kind',v_dwelling_kind,
    'grounds.responsibility',v_grounds,
    'grounds.scale',v_grounds_scale,
    'grounds.mowing_method',v_mowing,
    'transport.vehicle_count',v_vehicle_count,
    'context.low_density_owner_household',(v_tenure='own' and v_setting='rural'),
    'context.dense_urban_renter',(v_tenure='rent' and v_setting='dense_city')
  )||v_candidates;

  return jsonb_build_object(
    'ok',true,'contractVersion','reality_discovery_context_self_api_v1',
    'principalId',v_principal.id,'householdId',v_household.id,
    'signals',v_signals,'answers',v_answers,'candidateEvidence',v_candidates,
    'canonicalResidence',case when v_residence.id is null then null else jsonb_build_object(
      'id',v_residence.id,'address',v_residence.address,'tenureKind',v_residence.tenure_kind,
      'majorRepairsResponsibility',v_residence.major_repairs_responsibility
    ) end,
    'truthBoundary',jsonb_build_object(
      'signalsAreDiscoveryContext',true,
      'householdShapeCanGuideQuestionsWithoutCreatingPeople',true,
      'purchaseContactIsCandidateEvidence',true,
      'canonicalResidenceOutranksDiscoveryAnswer',true,
      'unconfirmedSourceContextDoesNotDriveQuestions',true,
      'placeSettingMayBeHumanOrConfirmedSourceClassified',true,
      'inferenceIsNotDomainTruth',true,
      'candidateEvidenceRequiresConfirmationOrPromotion',true,
      'sensitiveTraitsNotInferred',true
    )
  );
end;
$function$;

commit;
