-- Run only on a disposable production-shaped database clone AFTER source_candidate.sql.
-- Structural checks cannot establish real signed issuer, acceptance, revocation
-- and privacy behavior; those remain mandatory release acceptance tests.
do $check$
declare
  v_inv oid := to_regclass('atlas.universal_program_invitations_v1');
  v_part oid := to_regclass('atlas.universal_program_participations_v1');
begin
  if v_inv is null or v_part is null then
    raise exception 'Both universal invitation and participation originals required';
  end if;
  if not exists(select 1 from pg_class where oid=v_inv and relrowsecurity and relforcerowsecurity)
     or not exists(select 1 from pg_class where oid=v_part and relrowsecurity and relforcerowsecurity)
  then
    raise exception 'All private relationship custody must force RLS';
  end if;
  if has_table_privilege('anon',v_inv,'SELECT') or
     has_table_privilege('authenticated',v_inv,'SELECT') or
     has_table_privilege('service_role',v_inv,'SELECT') or
     has_table_privilege('anon',v_part,'SELECT') or
     has_table_privilege('authenticated',v_part,'SELECT') or
     has_table_privilege('service_role',v_part,'SELECT') or
     has_table_privilege('authenticated',v_part,'INSERT') or
     has_table_privilege('authenticated',v_inv,'INSERT')
  then
    raise exception 'No API table reads/writes released in source candidate';
  end if;
  if exists(
    select 1 from pg_class c,
     lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
    where c.oid in (v_inv,v_part) and acl.grantee=0
      and acl.privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
  ) then
    raise exception 'No PUBLIC privilege may bypass private subject custody';
  end if;
  if not exists(
    select 1 from pg_constraint where conrelid=v_inv
      and conname='universal_program_invitation_exact_origin_v1'
  ) or not exists(
    select 1 from pg_constraint where conrelid=v_part
      and conname='universal_program_participation_state_v1'
  ) then
    raise exception 'Version/original and participation state constraints absent';
  end if;
  if (select count(*) from pg_trigger where tgrelid=v_inv and not tgisinternal
       and tgname='universal_program_invitation_origin_guard_v1')<>1
     or (select count(*) from pg_trigger where tgrelid=v_part and not tgisinternal
       and tgname='universal_program_participation_guard_v1')<>1
  then
    raise exception 'Source continuity and consent trigger missing';
  end if;
  raise notice 'STRUCTURAL SOURCE ONLY: invitation issuance, consent and signed denials still unproven';
end $check$;
