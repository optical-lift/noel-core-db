create schema if not exists newsroom;

create table if not exists newsroom.market_editions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  observed_at timestamptz not null,
  values jsonb not null,
  block text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists market_editions_workspace_observed_idx
  on newsroom.market_editions (workspace_id, observed_at desc, created_at desc);

alter table newsroom.market_editions enable row level security;
revoke all on newsroom.market_editions from anon, authenticated;

create or replace function public.newsroom_record_markets_edition(
  target_workspace uuid,
  edition_observed_at timestamptz,
  edition_values jsonb,
  edition_block text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  latest newsroom.market_editions%rowtype;
  current_row newsroom.market_editions%rowtype;
  previous_row newsroom.market_editions%rowtype;
begin
  if actor is null then
    raise exception 'authentication required';
  end if;

  if not exists (
    select 1
    from transcript_core.workspace_memberships wm
    where wm.workspace_id = target_workspace
      and wm.user_id = actor
  ) then
    raise exception 'workspace access denied';
  end if;

  select * into latest
  from newsroom.market_editions
  where workspace_id = target_workspace
  order by observed_at desc, created_at desc
  limit 1;

  if latest.id is null or latest.values is distinct from edition_values then
    insert into newsroom.market_editions (
      workspace_id,
      observed_at,
      values,
      block,
      created_by
    ) values (
      target_workspace,
      edition_observed_at,
      edition_values,
      edition_block,
      actor
    )
    returning * into current_row;
  else
    current_row := latest;
  end if;

  select * into previous_row
  from newsroom.market_editions
  where workspace_id = target_workspace
    and id <> current_row.id
  order by observed_at desc, created_at desc
  limit 1;

  return jsonb_build_object(
    'current_id', current_row.id,
    'current_observed_at', current_row.observed_at,
    'previous_id', previous_row.id,
    'previous_observed_at', previous_row.observed_at,
    'previous_values', previous_row.values
  );
end;
$$;

revoke all on function public.newsroom_record_markets_edition(uuid, timestamptz, jsonb, text) from public, anon;
grant execute on function public.newsroom_record_markets_edition(uuid, timestamptz, jsonb, text) to authenticated;