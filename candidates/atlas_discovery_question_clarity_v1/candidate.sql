-- Code-owned Atlas question catalog correction; no Person evidence rewritten.
-- Historical source: 20261006174500_atlas_reality_discovery_world_position_scale_v1.sql.
-- Existing question keys, answer kind, signals, scores, domain edges and original option keys remain intact.
-- Review before generating a migration; no live execution from this candidate.
begin;
do $catalog$
declare
 r record;
 old_keys text;
 changed integer;
begin
 for r in
  select * from (values
      ('property.relationship', 'Property?', 'What kind of property are you responsible for managing or maintaining?', 'Choose the arrangement that best describes your responsibility, not merely property you visit or live near.', 'home,rentals,client,mixed', '[{"key":"none","label":"No property responsibility"},{"key":"other","label":"Another property arrangement"}]'::jsonb),
      ('hobbies.kind', 'Hobbies?', 'Which kind of hobby or recurring personal interest, if any, takes a place in your life?', 'Choose the closest fit for your main interest. This helps Atlas understand what activities, equipment, projects or commitments might matter. If you do not have one, say so.', 'creative,outdoors,sports,other', '[{"key":"none","label":"None"}]'::jsonb),
      ('community.kind', 'Community?', 'What kind of organized community or group, if any, are you regularly involved with?', 'Think of groups that create relationships, events, service or other commitments. Casual contact does not count as a commitment.', 'church,nonprofit,club,other', '[{"key":"none","label":"None"}]'::jsonb),
      ('projects.kind', 'Projects?', 'What kind of ongoing project, if any, are you currently carrying?', 'Choose the closest fit for your main project. An idea you are not pursuing does not have to count.', 'home,creative,business,other', '[{"key":"none","label":"None at present"}]'::jsonb),
      ('money.scope', 'Money?', 'Which financial responsibilities are most relevant to the way you use Atlas?', 'Personal finances, shared household finances, business finances, or a combination.', 'personal,household,business,mixed', '[]'::jsonb),
      ('family.children_stage', 'Children?', 'Do you have children, and are they minors or adults?', 'Include children outside your household. This answer does not establish who lives with you.', 'none,minor,adult,both', '[]'::jsonb),
      ('property.portfolio_size', 'Rental properties?', 'How many rental properties are you responsible for?', 'Count rental properties you own or manage, not your own residence unless it is a separate rental responsibility.', 'one,two_five,six_plus', '[]'::jsonb),
      ('business.count', 'Businesses?', 'How many businesses are you responsible for operating?', 'Count distinct businesses you actually help operate, not merely ideas or employers.', 'one,several', '[]'::jsonb),
      ('work.client_responsibility', 'Clients?', 'Are you personally responsible for client relationships or client commitments in your work?', 'Answer yes only if those relationships or commitments are part of what you carry.', 'yes,no', '[]'::jsonb)
  ) as proposal(question_key,old_prompt,new_prompt,new_help,old_option_keys,new_options)
 loop
  select string_agg(x->>'key',',' order by ord)
    into old_keys
  from atlas.reality_discovery_questions q
  cross join lateral jsonb_array_elements(q.options) with ordinality o(x,ord)
  where q.question_key=r.question_key and q.active and q.prompt=r.old_prompt;
  if old_keys is distinct from r.old_option_keys then
    raise exception 'Question catalog precondition changed for %; review source before retrying',r.question_key;
  end if;
  update atlas.reality_discovery_questions q
  set prompt=r.new_prompt,help_text=r.new_help,options=q.options||r.new_options,updated_at=now()
  where q.question_key=r.question_key and q.active and q.prompt=r.old_prompt;
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'Expected one catalog question for %',r.question_key; end if;
 end loop;
end;
$catalog$;
commit;
