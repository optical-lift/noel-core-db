-- Read-only postconditions for disposable-clone source validation.
begin;
do $check$
declare r record;
begin
 for r in select * from (values
      ('property.relationship','What kind of property are you responsible for managing or maintaining?','Choose the arrangement that best describes your responsibility, not merely property you visit or live near.','home,rentals,client,mixed,none,other'),
      ('hobbies.kind','Which kind of hobby or recurring personal interest, if any, takes a place in your life?','Choose the closest fit for your main interest. This helps Atlas understand what activities, equipment, projects or commitments might matter. If you do not have one, say so.','creative,outdoors,sports,other,none'),
      ('community.kind','What kind of organized community or group, if any, are you regularly involved with?','Think of groups that create relationships, events, service or other commitments. Casual contact does not count as a commitment.','church,nonprofit,club,other,none'),
      ('projects.kind','What kind of ongoing project, if any, are you currently carrying?','Choose the closest fit for your main project. An idea you are not pursuing does not have to count.','home,creative,business,other,none'),
      ('money.scope','Which financial responsibilities are most relevant to the way you use Atlas?','Personal finances, shared household finances, business finances, or a combination.','personal,household,business,mixed'),
      ('family.children_stage','Do you have children, and are they minors or adults?','Include children outside your household. This answer does not establish who lives with you.','none,minor,adult,both'),
      ('property.portfolio_size','How many rental properties are you responsible for?','Count rental properties you own or manage, not your own residence unless it is a separate rental responsibility.','one,two_five,six_plus'),
      ('business.count','How many businesses are you responsible for operating?','Count distinct businesses you actually help operate, not merely ideas or employers.','one,several'),
      ('work.client_responsibility','Are you personally responsible for client relationships or client commitments in your work?','Answer yes only if those relationships or commitments are part of what you carry.','yes,no')
 ) as expected(question_key,prompt,help_text,option_keys)
 loop
  if not exists(select 1 from atlas.reality_discovery_questions q
   where q.question_key=r.question_key and q.active and q.prompt=r.prompt and q.help_text=r.help_text
    and (select string_agg(x->>'key',',' order by ord) from jsonb_array_elements(q.options) with ordinality o(x,ord))=r.option_keys)
  then raise exception 'Revised source question/options not verified: %',r.question_key; end if;
 end loop;
 -- None is a distinct recorded answer, not a pause, and cannot admit rental portfolio questions.
 if exists(select 1 from atlas.reality_discovery_edges where signal_key in ('hobbies.kind','community.kind','projects.kind') or (signal_key='property.relationship' and (compare_value ? 'none' or compare_value ? 'other')))
 then raise exception 'New answer values have unreviewed downstream edges'; end if;
 if has_function_privilege('anon','public.answer_reality_discovery_question_self_api_v1(jsonb)','EXECUTE') then raise exception 'Anonymous answer authority is forbidden'; end if;
end;
$check$;
rollback;
