begin;

do $validation$
declare
  v_def text;
begin
  if to_regprocedure('public.personal_atlas_purchase_identity_candidate_self_api_v1()') is null
     or to_regprocedure('public.begin_personal_atlas_from_purchase_self_api_v1(text,text)') is null
     or to_regprocedure('public.reality_discovery_identity_anchor_self_api_v1()') is null
     or to_regprocedure('public.set_reality_discovery_identity_anchor_self_api_v1(jsonb)') is null then
    raise exception 'First Encounter identity RPCs are incomplete.';
  end if;

  if has_function_privilege('anon','public.personal_atlas_purchase_identity_candidate_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.begin_personal_atlas_from_purchase_self_api_v1(text,text)','EXECUTE')
     or has_function_privilege('anon','public.reality_discovery_identity_anchor_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.set_reality_discovery_identity_anchor_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Anonymous role must not execute first Encounter identity RPCs.';
  end if;

  if not has_function_privilege('authenticated','public.personal_atlas_purchase_identity_candidate_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.begin_personal_atlas_from_purchase_self_api_v1(text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.reality_discovery_identity_anchor_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.set_reality_discovery_identity_anchor_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Authenticated role must execute first Encounter identity RPCs.';
  end if;

  select pg_get_functiondef('atlas.personal_atlas_purchase_identity_candidate_self_api_v1()'::regprocedure)
  into v_def;
  if position('purchaserName' in v_def)=0
     or position('billingAddress' in v_def)=0
     or position('billingAddressIsNotHomeUntilHumanSaysSo' in v_def)=0 then
    raise exception 'Purchase identity reader does not preserve candidate-evidence boundary.';
  end if;

  select pg_get_functiondef('atlas.begin_personal_atlas_from_purchase_self_api_v1(text,text)'::regprocedure)
  into v_def;
  if position('candidateName' in v_def)=0
     or position('begin_personal_atlas_self_api_v1' in v_def)=0
     or position('purchase did not provide one' in v_def)=0 then
    raise exception 'Purchase-backed Principal establishment may invent or discard name evidence.';
  end if;

  select pg_get_functiondef('atlas.set_reality_discovery_identity_anchor_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('identity.birth_date' in v_def)=0
     or position('identity.purchase_address_role' in v_def)=0
     or position('upsert_personal_residence_arrangement_self_api_v1' in v_def)=0
     or position('v_address_role=''home''' in replace(v_def,' ',''))=0
     or position('birthDateChangesQuestionPriorityNotBiography' in v_def)=0 then
    raise exception 'Identity anchor writer does not preserve chronology/address authority boundaries.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='identity.birth_date'
      and active=false
      and metadata->>'identityAnchor'='true'
  ) then
    raise exception 'DOB anchor question is not isolated from ordinary Discovery admission.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='identity.purchase_address_role'
      and active=false
      and options @> '[{"key":"home"},{"key":"work"},{"key":"mailing"},{"key":"other"}]'::jsonb
  ) then
    raise exception 'Purchase-address role vocabulary is incomplete.';
  end if;

  if exists(
    select 1 from atlas.reality_discovery_questions
    where question_key='home.confirm_purchase_address' and active
  ) then
    raise exception 'Superseded yes/no purchase-address confirmation remains active.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_orientation_profile_self_api_v1()'::regprocedure)
  into v_def;
  if position('orientation_version=3' in replace(v_def,' ',''))=0
     or position('field_position_scale' in v_def)=0
     or position('fieldLocatesRelevantLifeArenas' in v_def)=0 then
    raise exception 'FIELD / POSITION / SCALE reader is not version-isolated.';
  end if;

  select pg_get_functiondef('atlas.set_reality_discovery_orientation_profile_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('orientation_version' in v_def)=0
     or position('v_world' in v_def)=0
     or position('v_positions' in v_def)=0
     or position('v_scale' in v_def)=0
     or position('field_position_scale' in v_def)=0
     or position('first_day_orientation_field_position_scale_v1' in v_def)=0 then
    raise exception 'FIELD / POSITION / SCALE writer is not structurally complete.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_questions q
    join atlas.reality_discovery_encounter_admission a using(question_key)
    where q.question_key='family.children_stage'
      and q.active
      and a.first_day_disposition='admit'
      and q.metadata->'orientationPositionPairs' ? 'family:parent'
      and q.options @> '[{"key":"minor"},{"key":"adult"},{"key":"both"}]'::jsonb
  ) then
    raise exception 'Parent child-stage discriminator is missing from first-day Discovery.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_edges
    where question_key='family.children_stage'
      and signal_key='orientation.family_parent'
      and effect_kind='require'
  ) then
    raise exception 'Child-stage question is not gated by explicit parent POSITION.';
  end if;

  if not exists(
    select 1 from atlas.reality_discovery_edges
    where question_key='family.children_stage'
      and signal_key='identity.age_band'
      and effect_kind='boost'
      and weight>0
  ) then
    raise exception 'DOB chronology does not influence first-day question priority.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_context_self_api_v1()'::regprocedure)
  into v_def;
  if position('identity.age_band' in v_def)=0
     or position('orientation.family_parent' in v_def)=0
     or position('family.children_stage' in v_def)=0
     or position('birthDateEstablishesChronologyNotBiography' in v_def)=0
     or position('v_children_stage' in v_def)=0 then
    raise exception 'Discovery context does not separate chronology, parent relation, and child life stage.';
  end if;

  if position('v_children_stage in' in lower(v_def))>0 then
    raise exception 'Child age stage must not be used as evidence that children live in the household.';
  end if;

  if not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.reality_discovery_identity_anchor_self_api_v1()'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Identity anchor read RPC is missing from authenticated registry.';
  end if;
end;
$validation$;

rollback;
