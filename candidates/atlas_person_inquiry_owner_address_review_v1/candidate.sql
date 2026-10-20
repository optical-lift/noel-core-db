begin;

-- Option C: explicit Ledger-owner review of one already-observed private
-- address. This is evidence of the requester's claimed source and willingness
-- to proceed to a separate Correspondence review, NOT route consent or send
-- permission, and NEVER an email or canonical identity/relationship effect.

create table atlas.person_contact_inquiry_owner_address_reviews (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references atlas.person_contact_inquiry_intents(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  reviewed_by_person_id uuid not null references reality.entities(id) on delete restrict,
  decision text not null,
  source_basis text,
  evidence_note text not null,
  reviewed_at timestamptz not null default now(),
  constraint inquiry_address_review_decision_v1 check (
    decision in ('owner_source_reviewed','owner_withdrew_inquiry')
  ),
  constraint inquiry_address_review_basis_v1 check (
    (decision='owner_source_reviewed' and source_basis in (
      'provided_by_subject','prior_direct_correspondence',
      'ledger_source_record','publicly_published_by_subject','other_explained'))
    or (decision='owner_withdrew_inquiry' and source_basis is null)
  ),
  constraint inquiry_address_review_note_v1 check (
    length(btrim(evidence_note)) between 20 and 1200
  ),
  constraint inquiry_address_review_once_per_decision_v1 unique (inquiry_id,decision)
);
comment on table atlas.person_contact_inquiry_owner_address_reviews is
 'Append-only owner testimony about source of one private email; not recipient consent, deliverability, opt-out clearance, send permission, Person proof, institution affiliation, membership or Work authority.';
create index person_inquiry_owner_address_review_ledger_v1
  on atlas.person_contact_inquiry_owner_address_reviews(ledger_id,reviewed_by_person_id,reviewed_at desc);
alter table atlas.person_contact_inquiry_owner_address_reviews enable row level security;
alter table atlas.person_contact_inquiry_owner_address_reviews force row level security;
revoke all on atlas.person_contact_inquiry_owner_address_reviews
 from public,anon,authenticated,service_role;

create function atlas.prevent_person_inquiry_address_review_rewrite_v1()
returns trigger language plpgsql security invoker set search_path to ''
as $fn$
begin
  raise exception 'Person inquiry source testimony is append-only'
    using errcode='23514';
end $fn$;
revoke all on function atlas.prevent_person_inquiry_address_review_rewrite_v1()
 from public,anon,authenticated,service_role;
create trigger person_inquiry_address_review_immutable_v1
 before update or delete on atlas.person_contact_inquiry_owner_address_reviews
 for each row execute function atlas.prevent_person_inquiry_address_review_rewrite_v1();

create function atlas.review_person_inquiry_owner_address_self_api_v1(
  p_ledger_id uuid,
  p_inquiry_id uuid,
  p_decision text,
  p_source_basis text,
  p_evidence_note text
) returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_owner jsonb;
  v_person uuid;
  v_note text:=btrim(coalesce(p_evidence_note,''));
  v_basis text:=nullif(btrim(coalesce(p_source_basis,'')),'');
  v_old atlas.person_contact_inquiry_owner_address_reviews%rowtype;
  v_review_id uuid;
  v_withdrawn boolean;
begin
  -- This already-live self API enforces the real authenticated Person,
  -- canonical governing Principal, active native Ledger seat, exact owner
  -- and exact Ledger scope. It does not expose another Ledger's contact.
  v_owner:=atlas.person_contact_inquiry_intent_owner_self_api_v1(
    p_ledger_id,p_inquiry_id);
  v_person:=atlas.current_person_id_v1();
  if v_person is null or p_decision not in
     ('owner_source_reviewed','owner_withdrew_inquiry')
     or length(v_note) not between 20 and 1200
     or (p_decision='owner_source_reviewed'
       and coalesce(v_basis,'') not in (
        'provided_by_subject','prior_direct_correspondence',
        'ledger_source_record','publicly_published_by_subject',
        'other_explained'))
     or (p_decision='owner_withdrew_inquiry' and v_basis is not null) then
    raise exception 'Exact owner address review decision and supporting note required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.person_address_review:'||p_inquiry_id::text,0));

  select * into v_old from atlas.person_contact_inquiry_owner_address_reviews r
  where r.inquiry_id=p_inquiry_id and r.decision=p_decision;
  if v_old.id is not null then
    if v_old.ledger_id is distinct from p_ledger_id or
       v_old.reviewed_by_person_id is distinct from v_person or
       v_old.source_basis is distinct from v_basis or
       v_old.evidence_note is distinct from v_note then
      raise exception 'Earlier address testimony cannot be silently rewritten'
        using errcode='23505';
    end if;
    return jsonb_build_object('reviewId',v_old.id,'inquiryId',p_inquiry_id,
      'decision',p_decision,'changed',false,'contactAuthorized',false,
      'canSend',false,'messageSent',false,'personIdentified',false,
      'relationshipEstablished',false);
  end if;

  select exists(
    select 1 from atlas.person_contact_inquiry_owner_address_reviews r
      where r.inquiry_id=p_inquiry_id
      and r.decision='owner_withdrew_inquiry'
  ) into v_withdrawn;
  if v_withdrawn then
    raise exception 'This inquiry has been withdrawn; create a distinct justified inquiry'
      using errcode='23514';
  end if;
  if p_decision='owner_withdrew_inquiry' and not exists(
    select 1 from atlas.person_contact_inquiry_owner_address_reviews r
      where r.inquiry_id=p_inquiry_id
        and r.decision='owner_source_reviewed'
  ) then
    raise exception 'Nothing approved for source review exists to withdraw'
      using errcode='23514';
  end if;

  insert into atlas.person_contact_inquiry_owner_address_reviews(
    inquiry_id,ledger_id,reviewed_by_person_id,decision,source_basis,evidence_note)
  values(p_inquiry_id,p_ledger_id,v_person,p_decision,v_basis,v_note)
  returning id into v_review_id;

  return jsonb_build_object('reviewId',v_review_id,'inquiryId',p_inquiry_id,
    'decision',p_decision,'changed',true,
    'next',case when p_decision='owner_source_reviewed'
      then 'separate_sender_endpoint_and_recipient_contact_review_required'
      else 'withdrawn_no_further_contact'
    end,
    'contactAuthorized',false,'canSend',false,'messageSent',false,
    'personIdentified',false,'relationshipEstablished',false);
end $fn$;
revoke all on function atlas.review_person_inquiry_owner_address_self_api_v1(
 uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function atlas.review_person_inquiry_owner_address_self_api_v1(
 uuid,uuid,text,text,text) to authenticated;

create function atlas.person_inquiry_owner_address_review_self_api_v1(
 p_ledger_id uuid,p_inquiry_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
 v_owned jsonb;
 v_review jsonb;
 v_withdrawn boolean;
begin
 v_owned:=atlas.person_contact_inquiry_intent_owner_self_api_v1(p_ledger_id,p_inquiry_id);
 select coalesce(jsonb_agg(jsonb_build_object(
   'reviewId',r.id,'decision',r.decision,'sourceBasis',r.source_basis,
   'evidenceNote',r.evidence_note,'reviewedAt',r.reviewed_at)
   order by r.reviewed_at),'[]'::jsonb)
 into v_review from atlas.person_contact_inquiry_owner_address_reviews r
 where r.ledger_id=p_ledger_id and r.inquiry_id=p_inquiry_id
   and r.reviewed_by_person_id=atlas.current_person_id_v1();
 select exists(select 1 from atlas.person_contact_inquiry_owner_address_reviews r
   where r.inquiry_id=p_inquiry_id and r.ledger_id=p_ledger_id
     and r.decision='owner_withdrew_inquiry') into v_withdrawn;
 return jsonb_build_object(
  'inquiryId',p_inquiry_id,'reviews',v_review,'withdrawn',v_withdrawn,
  'contactAuthorized',false,'canSend',false,'messageSent',false,
  'recipientIdentityVerified',false,'relationshipEstablished',false);
end $fn$;
revoke all on function atlas.person_inquiry_owner_address_review_self_api_v1(
 uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.person_inquiry_owner_address_review_self_api_v1(
 uuid,uuid) to authenticated;

create function public.review_person_inquiry_owner_address_self_api_v1(
 p_ledger_id uuid,p_inquiry_id uuid,p_decision text,
 p_source_basis text,p_evidence_note text
) returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.review_person_inquiry_owner_address_self_api_v1(
 p_ledger_id,p_inquiry_id,p_decision,p_source_basis,p_evidence_note) $fn$;
revoke all on function public.review_person_inquiry_owner_address_self_api_v1(
 uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.review_person_inquiry_owner_address_self_api_v1(
 uuid,uuid,text,text,text) to authenticated;

create function public.person_inquiry_owner_address_review_self_api_v1(
 p_ledger_id uuid,p_inquiry_id uuid
) returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.person_inquiry_owner_address_review_self_api_v1(
 p_ledger_id,p_inquiry_id) $fn$;
revoke all on function public.person_inquiry_owner_address_review_self_api_v1(
 uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.person_inquiry_owner_address_review_self_api_v1(
 uuid,uuid) to authenticated;

commit;
