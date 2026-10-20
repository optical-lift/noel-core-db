-- Postconditions: no real data is fabricated and no mail is sent.
do $verify$
declare
  v_def text;
begin
  if to_regprocedure('atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(uuid,uuid)') is null
    or to_regprocedure('public.person_contact_inquiry_route_preflight_owner_self_api_v1(uuid,uuid)') is null then
    raise exception 'Person inquiry route preflight is missing';
  end if;
  if has_function_privilege('anon',
     'public.person_contact_inquiry_route_preflight_owner_self_api_v1(uuid,uuid)',
     'EXECUTE') or not has_function_privilege('authenticated',
     'public.person_contact_inquiry_route_preflight_owner_self_api_v1(uuid,uuid)',
     'EXECUTE') then
    raise exception 'Route preflight access boundary invalid';
  end if;
  select pg_get_functiondef(
    'atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(uuid,uuid)'::regprocedure)
    into v_def;
  if position('person_contact_inquiry_intent_owner_self_api_v1' in v_def)=0
    or position('entity_evidence_claims' in v_def)=0
    or position('entity_contact_suppressions' in v_def)=0
    or position('v_contactability_v1' in v_def)=0
    or position('reality.entities' in v_def)=0
    or position('directory_display' in v_def)=0
    or position('public_contactable' in v_def)=0
    or position('canSend' in v_def)=0
    or position('crossLedgerPrivateLookupPerformed' in v_def)=0 then
    raise exception 'Preflight missing identity, privacy, contact route or no-send safeguards';
  end if;
  if exists(select 1 from atlas.person_contact_inquiry_intents) then
    raise exception 'Schema-only preflight migration inserted a real Person inquiry';
  end if;
end $verify$;
select 'atlas_person_inquiry_public_route_preflight_v1' as contract,
 count(*) as existing_source_inquiries from atlas.person_contact_inquiry_intents;
