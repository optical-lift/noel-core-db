do $verify$
declare v_fn text;
begin
 if to_regclass('atlas.person_contact_inquiry_owner_address_reviews') is null
  or to_regprocedure('public.review_person_inquiry_owner_address_self_api_v1(uuid,uuid,text,text,text)') is null
  or to_regprocedure('public.person_inquiry_owner_address_review_self_api_v1(uuid,uuid)') is null then
   raise exception 'Person inquiry owner source review absent';
 end if;
 if not (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    where c.oid='atlas.person_contact_inquiry_owner_address_reviews'::regclass) then
   raise exception 'Source-review privacy guard absent';
 end if;
 if has_table_privilege('authenticated','atlas.person_contact_inquiry_owner_address_reviews','SELECT')
  or has_table_privilege('anon','atlas.person_contact_inquiry_owner_address_reviews','SELECT')
  or has_function_privilege('anon',
   'public.review_person_inquiry_owner_address_self_api_v1(uuid,uuid,text,text,text)','EXECUTE')
  or not has_function_privilege('authenticated',
   'public.review_person_inquiry_owner_address_self_api_v1(uuid,uuid,text,text,text)','EXECUTE') then
   raise exception 'Review private table/RPC grants invalid';
 end if;
 if not exists (select 1 from pg_trigger where tgrelid=
     'atlas.person_contact_inquiry_owner_address_reviews'::regclass
     and tgname='person_inquiry_address_review_immutable_v1' and tgenabled='O') then
   raise exception 'Append-only source-review guard absent';
 end if;
 v_fn:=pg_get_functiondef(
  'atlas.review_person_inquiry_owner_address_self_api_v1(uuid,uuid,text,text,text)'::regprocedure);
 if position('person_contact_inquiry_intent_owner_self_api_v1' in v_fn)=0
   or position('pg_advisory_xact_lock' in v_fn)=0
   or position('owner_withdrew_inquiry' in v_fn)=0
   or position('messageSent' in v_fn)=0
   or position('contactAuthorized' in v_fn)=0 then
   raise exception 'Canonical owner / idempotency / no-send source-review boundary absent';
 end if;
 if (select count(*) from atlas.person_contact_inquiry_owner_address_reviews)<>0 then
   raise exception 'This schema-only migration fabricated owner consent';
 end if;
end $verify$;
select 'atlas_person_inquiry_owner_address_review_v1' as contract,
 count(*) as initial_owner_reviews from atlas.person_contact_inquiry_owner_address_reviews;