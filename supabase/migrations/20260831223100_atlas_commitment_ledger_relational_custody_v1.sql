BEGIN;

-- Every child record in the Commitment Ledger must remain inside the same plan.
-- The single-column foreign keys protect existence; these composite constraints
-- protect custody so a future adapter cannot cross-wire valid IDs from two plans.

alter table atlas.commitment_plan_generations
  add constraint commitment_plan_generations_id_plan_uq
  unique (id, plan_id);

alter table atlas.commitment_plan_generations
  add constraint commitment_plan_generations_supersedes_same_plan_fk
  foreign key (supersedes_generation_id, plan_id)
  references atlas.commitment_plan_generations(id, plan_id)
  on delete restrict;

alter table atlas.commitment_items
  add constraint commitment_items_generation_plan_fk
  foreign key (generation_id, plan_id)
  references atlas.commitment_plan_generations(id, plan_id)
  on delete restrict;

alter table atlas.commitment_items
  add constraint commitment_items_id_plan_generation_uq
  unique (id, plan_id, generation_id);

alter table atlas.commitment_events
  add constraint commitment_events_item_requires_generation_ck
  check (item_id is null or generation_id is not null);

alter table atlas.commitment_events
  add constraint commitment_events_generation_plan_fk
  foreign key (generation_id, plan_id)
  references atlas.commitment_plan_generations(id, plan_id)
  on delete restrict;

alter table atlas.commitment_events
  add constraint commitment_events_item_plan_generation_fk
  foreign key (item_id, plan_id, generation_id)
  references atlas.commitment_items(id, plan_id, generation_id)
  on delete restrict;

comment on constraint commitment_plan_generations_supersedes_same_plan_fk on atlas.commitment_plan_generations is
  'A plan generation may supersede only a generation belonging to the same immutable plan identity.';
comment on constraint commitment_items_generation_plan_fk on atlas.commitment_items is
  'A commitment item and its generation must share the same plan custody envelope.';
comment on constraint commitment_events_item_plan_generation_fk on atlas.commitment_events is
  'An item transition event must reference the exact plan and generation that owns the immutable item snapshot.';

COMMIT;
