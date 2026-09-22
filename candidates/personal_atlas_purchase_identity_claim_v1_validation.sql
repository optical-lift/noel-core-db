begin;

do $validation$
declare
  v_atlas_user uuid := 'f6e10000-0000-4000-8000-000000000001'::uuid;
  v_other_user uuid := 'f6e10000-0000-4000-8000-000000000002'::uuid;
  v_purchase uuid := 'f6e10000-0000-4000-8000-000000000010'::uuid;
  v_issued jsonb;
  v_token text;
  v_ticket_id uuid;
  v_claimed jsonb;
  v_status jsonb;
  v_begun jsonb;
begin
  v_issued:=atlas.issue_personal_atlas_purchase_claim_ticket_service_v1(
    'cs_validation_personal_purchase_identity_claim_v1',
    1800,
    '{"source":"validation_fixture"}'::jsonb
  );
  v_token:=v_issued->>'claimToken';
  v_ticket_id:=nullif(v_issued->>'ticketId','')::uuid;

  if v_ticket_id is null or v_token !~ '^pat_[0-9a-f]{64}$' then
    raise exception 'Claim ticket was not issued correctly: %',v_issued;
  end if;

  if exists(
    select 1
    from atlas.personal_atlas_purchase_claim_tickets t
    where t.id=v_ticket_id
      and t.token_sha256=v_token
  ) then
    raise exception 'Raw claim token was stored instead of its hash.';
  end if;

  v_claimed:=atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(
    v_token,
    v_atlas_user,
    '{"source":"validation_fixture"}'::jsonb
  );

  if coalesce((v_claimed->>'changed')::boolean,false) is not true then
    raise exception 'Claim ticket did not claim the purchase: %',v_claimed;
  end if;

  if not exists(
    select 1
    from atlas.personal_atlas_purchases p
    where p.id=v_purchase
      and p.purchaser_email='payer@example.invalid'
      and p.claimed_by_user_id=v_atlas_user
      and p.claimed_at is not null
  ) then
    raise exception 'Purchase payer evidence or Atlas-user claim is incorrect.';
  end if;

  v_claimed:=atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(
    v_token,
    v_atlas_user,
    '{"source":"validation_retry"}'::jsonb
  );
  if coalesce((v_claimed->>'alreadyClaimed')::boolean,false) is not true
     or coalesce((v_claimed->>'changed')::boolean,true) is not false then
    raise exception 'Same-user claim-ticket retry was not idempotent: %',v_claimed;
  end if;

  begin
    perform atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(
      v_token,
      v_other_user,
      '{"source":"validation_wrong_user"}'::jsonb
    );
    raise exception 'Consumed ticket was accepted for another Atlas user.';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub',v_atlas_user::text,true);

  v_status:=atlas.personal_atlas_access_status_self_api_v1();
  if coalesce((v_status->>'eligible')::boolean,false) is not true
     or v_status->>'accessBasis'<>'personal_atlas_purchase'
     or nullif(v_status->>'purchaseId','')::uuid<>v_purchase then
    raise exception 'Claimed user did not receive Personal Atlas access: %',v_status;
  end if;

  v_begun:=atlas.begin_personal_atlas_self_api_v1(
    'Claimed Atlas Human',
    'America/Chicago'
  );

  if coalesce((v_begun->>'ok')::boolean,false) is not true
     or v_begun->>'accessBasis'<>'personal_atlas_purchase'
     or nullif(v_begun->>'purchaseId','')::uuid<>v_purchase then
    raise exception 'Different-email claimed purchase could not establish Atlas: %',v_begun;
  end if;

  if not exists(
    select 1
    from atlas.principals p
    where p.user_id=v_atlas_user
      and p.name='Claimed Atlas Human'
  ) then
    raise exception 'Claimed Atlas human Principal was not established.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.issue_personal_atlas_purchase_claim_ticket_service_v1(text,integer,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(text,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Purchase claim service functions are directly executable by authenticated.';
  end if;
end;
$validation$;

rollback;
