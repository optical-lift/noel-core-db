-- Nonprofit fundraising record state hardening v1.
-- Terminal financial-history states cannot be silently reopened by an idempotent replay.

create or replace function atlas.guard_fundraising_financial_state_transition_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_table_name='fundraising_contributions' then
    if old.record_state='voided' and new.record_state<>'voided' then
      raise exception 'Voided contribution is terminal; establish an explicit replacement record.' using errcode='55000';
    end if;
  elsif tg_table_name='fundraising_pledges' then
    if old.pledge_state in ('fulfilled','cancelled','expired') and new.pledge_state<>old.pledge_state then
      raise exception 'Terminal pledge state cannot be silently reopened.' using errcode='55000';
    end if;
  elsif tg_table_name='fundraising_grant_awards' then
    if old.award_state in ('closed','cancelled') and new.award_state<>old.award_state then
      raise exception 'Closed/cancelled grant award cannot be silently reopened.' using errcode='55000';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_fundraising_financial_state_transition_v1()
  from public,anon,authenticated;

drop trigger if exists fundraising_contributions_state_transition_guard_v1 on atlas.fundraising_contributions;
create trigger fundraising_contributions_state_transition_guard_v1
before update of record_state on atlas.fundraising_contributions
for each row execute function atlas.guard_fundraising_financial_state_transition_v1();

drop trigger if exists fundraising_pledges_state_transition_guard_v1 on atlas.fundraising_pledges;
create trigger fundraising_pledges_state_transition_guard_v1
before update of pledge_state on atlas.fundraising_pledges
for each row execute function atlas.guard_fundraising_financial_state_transition_v1();

drop trigger if exists fundraising_grant_awards_state_transition_guard_v1 on atlas.fundraising_grant_awards;
create trigger fundraising_grant_awards_state_transition_guard_v1
before update of award_state on atlas.fundraising_grant_awards
for each row execute function atlas.guard_fundraising_financial_state_transition_v1();
