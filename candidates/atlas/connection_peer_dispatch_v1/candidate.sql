-- Universal connected-Person Ledger correspondence. Draft for governed validation only.
begin;

create table atlas.ledger_person_dispatches (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references atlas.organizations(id),
 ledger_id uuid not null references atlas.ledgers(id),
 sender_person_id uuid not null references reality.entities(id),
 recipient_person_id uuid not null references reality.entities(id),
 source_action_id text not null,
 dispatch_kind text not null check (dispatch_kind in ('notice','work_request')),
 body text not null check (length(btrim(body)) between 1 and 500),
 dispatch_state text not null default 'pending'
   check (dispatch_state in ('pending','acknowledged','declined')),
 created_at timestamptz not null default now(),
 responded_at timestamptz,
 check (sender_person_id <> recipient_person_id),
 check (length(btrim(source_action_id)) between 1 and 128),
 check (
   (dispatch_state='pending' and responded_at is null)
   or (dispatch_state='acknowledged' and dispatch_kind='notice' and responded_at is not null)
   or (dispatch_state='declined' and dispatch_kind='work_request' and responded_at is not null)
 ),
 unique(sender_person_id,source_action_id)
);
create index ledger_person_dispatches_received_idx
 on atlas.ledger_person_dispatches(recipient_person_id,created_at desc,id desc);
alter table atlas.ledger_person_dispatches enable row level security;
revoke all on atlas.ledger_person_dispatches from public,anon,authenticated;

create or replace function atlas.connected_ledger_person_choices_self_api_v1(
 p_ledger_id uuid,p_limit integer default 100,p_after_person_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_self uuid;v_items jsonb;v_next uuid;v_more boolean;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 if p_limit not between 1 and 100 then
   raise exception 'Page size out of range' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('personId',x.id,'name',x.display_name)
  order by x.id),'[]'::jsonb) into v_items from (
  select distinct e.id,e.display_name from ledger.seats s
  join reality.entities e on e.id=s.person_entity_id
  where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
   and e.entity_kind='person' and e.identity_state='canonical'
   and e.id<>v_self and (p_after_person_id is null or e.id>p_after_person_id)
  order by e.id limit p_limit) x;
 if jsonb_array_length(v_items)>0 then
   v_next:=(v_items->(jsonb_array_length(v_items)-1)->>'personId')::uuid;
   select exists(select 1 from ledger.seats s
    join reality.entities e on e.id=s.person_entity_id
    where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
     and e.entity_kind='person' and e.identity_state='canonical'
     and e.id<>v_self and e.id>v_next) into v_more;
 else v_more:=false;end if;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_person_choices_v1',
 'ledgerId',p_ledger_id,'items',v_items,'hasMore',v_more,
 'nextPersonId',case when v_more then v_next else null end,
 'rootAuthorityNotRequired',true);
end$fn$;

commit;
