-- Disposable clone only, not a replacement for signed GoTrue HTTP proof.
begin;
do $check$
declare p uuid; a uuid; b uuid; n integer;
begin
 select id into p from atlas.principals where status='active' and user_id is not null
 order by id limit 1;
 if p is not null then
   a:=atlas.ensure_person_health_collection_v1(p);
   b:=atlas.ensure_person_health_collection_v1(p);
   if a is distinct from b then raise exception 'Seed is not idempotent'; end if;
   select count(*) into n from atlas.notebook_spread_instances
     where principal_id=p and spread_key='personal.health';
   if n<>1 then raise exception 'More than one Health Collection'; end if;
 end if;
end;
$check$;
rollback;

-- Separately required real signed HTTP sessions (NOT forged SQL claims):
-- Person A/B each sees exactly one private Health in Index.
-- Person A captures raw note, files explicitly, signed rereads same capture ID,
-- same event receipt and Today movement, without any copied text.
-- Retry does not duplicate binding or receipt.
-- A moves source to another authorized private Person Collection and back.
-- A cannot read B's collection, source, receipt or move B's source;
-- B cannot infer A's address. Anonymous calls fail.
-- Unknown, unapproved, revoked and preapproval capture do not auto-file.
-- Different concurrent actions on same capture serialize; one active location.
-- Confirm historical source remains after move and receipt is append-only.
