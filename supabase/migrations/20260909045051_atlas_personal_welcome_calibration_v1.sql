-- Personal Welcome Calibration V1.
-- Friendly upstream onboarding that establishes real household context and feeds downstream root/model selection.

create table if not exists atlas.welcome_calibration_questions (
  question_key text primary key,
  title text not null,
  prompt text not null,
  selection_kind text not null check (selection_kind in ('multi_select','single_select')),
  position smallint not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists atlas.welcome_calibration_options (
  question_key text not null references atlas.welcome_calibration_questions(question_key) on delete cascade,
  option_key text not null,
  label text not null,
  position smallint not null,
  root_tags jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  primary key (question_key, option_key)
);

create table if not exists atlas.household_welcome_calibrations (
  household_id uuid not null references atlas.households(id) on delete cascade,
  question_key text not null references atlas.welcome_calibration_questions(question_key),
  selections jsonb not null default '[]'::jsonb,
  source text not null default 'self_reported',
  confirmed boolean not null default true,
  confirmed_by uuid,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (household_id, question_key)
);

create table if not exists atlas.household_welcome_history (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  question_key text not null,
  selections jsonb not null,
  source text not null,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists atlas.household_companions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  display_name text not null,
  species text not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table atlas.welcome_calibration_questions enable row level security;
alter table atlas.welcome_calibration_options enable row level security;
alter table atlas.household_welcome_calibrations enable row level security;
alter table atlas.household_welcome_history enable row level security;
alter table atlas.household_companions enable row level security;
revoke all on atlas.welcome_calibration_questions, atlas.welcome_calibration_options, atlas.household_welcome_calibrations, atlas.household_welcome_history, atlas.household_companions from public, anon, authenticated;

insert into atlas.welcome_calibration_questions(question_key,title,prompt,selection_kind,position) values
('people','Your people','Who are your people?','multi_select',1),
('kids','Kids','Tell Atlas about the kids.','multi_select',2),
('animals','Animals','Any animals around here?','multi_select',3),
('home','Home','What kind of place do you call home?','multi_select',4),
('week','Week','Where does everybody usually go during the week?','multi_select',5),
('busy','What keeps life busy','What keeps your household busy?','multi_select',6),
('transport','Getting around','How do you usually get around?','multi_select',7),
('food','Food','What does food look like around here?','multi_select',8),
('interests','You','What are you into?','multi_select',9),
('right_now','Right now','What is going on in life right now?','multi_select',10)
on conflict (question_key) do update set title=excluded.title,prompt=excluded.prompt,selection_kind=excluded.selection_kind,position=excluded.position,active=true;

insert into atlas.welcome_calibration_options(question_key,option_key,label,position,root_tags) values
('people','spouse_partner','spouse / partner',1,'["spouse_partner"]'),('people','kids','kids',2,'["school_age_kids"]'),('people','roommates','roommates',3,'["roommates"]'),('people','older_family','parents / older family',4,'["older_family"]'),('people','other_family','other family',5,'["extended_family_often"]'),('people','mostly_me','mostly just me',6,'["quiet_social_calendar"]'),
('kids','baby','baby',1,'["babies_toddlers","young_children"]'),('kids','toddler','toddler',2,'["babies_toddlers","young_children"]'),('kids','elementary','elementary age',3,'["school_age_kids","school"]'),('kids','middle_school','middle school age',4,'["school_age_kids","school"]'),('kids','teen','teen',5,'["teenagers","school"]'),('kids','grown','grown kids',6,'["adult_children"]'),
('animals','dog','dog',1,'["pets"]'),('animals','cat','cat',2,'["pets"]'),('animals','chickens','chickens',3,'["pets","rural_property"]'),('animals','horses','horses',4,'["pets","rural_property","acreage"]'),('animals','livestock','livestock',5,'["rural_property","acreage"]'),('animals','other','something else',6,'["pets"]'),('animals','none','none',7,'[]'),
('home','apartment','apartment',1,'["apartment","no_outdoor_upkeep"]'),('home','townhouse','townhouse / duplex',2,'["townhouse_duplex"]'),('home','house','house',3,'["ordinary_family_house"]'),('home','big_house','big house',4,'["large_house"]'),('home','farm_acreage','farm / acreage',5,'["rural_property","acreage"]'),('home','multiple_buildings','multiple buildings',6,'["multiple_buildings"]'),('home','rent','rent',7,'["rent"]'),('home','own','own',8,'["own"]'),
('week','work_away','work away from home',1,'["work_away"]'),('week','work_home','work from home',2,'["work_from_home"]'),('week','school','school',3,'["school"]'),('week','homeschool','homeschool',4,'["homeschool"]'),('week','daycare','daycare',5,'["daycare"]'),('week','college','college',6,'["school"]'),('week','mostly_home','mostly home',7,'["mostly_home_centered"]'),
('busy','sports','sports',1,'["sports_activities","sports","activity_heavy"]'),('busy','music_lessons','music / lessons',2,'["clubs_lessons","activity_heavy"]'),('busy','church','church',3,'["church","church_community_often"]'),('busy','clubs','clubs',4,'["clubs_lessons","activity_heavy"]'),('busy','appointments','therapy / appointments',5,'["frequent_appointments","medical_system"]'),('busy','volunteering','volunteering',6,'["church_community_often"]'),('busy','travel','travel',7,'["travel","frequent_travel"]'),('busy','family','lots of family stuff',8,'["extended_family_often"]'),('busy','not_much','not much right now',9,'["quiet_social_calendar"]'),
('transport','one_car','one car',1,'["one_car"]'),('transport','multiple_cars','multiple cars',2,'["multiple_cars"]'),('transport','school_bus','school bus',3,'["school_bus"]'),('transport','walk_bike','walk / bike',4,'["walk_bike"]'),('transport','transit','public transit',5,'["public_transit"]'),('transport','lots_driving','lots of driving',6,'["rural_driving"]'),('transport','rides','rides from others',7,'["rides_from_others"]'),
('food','cook','cook most meals',1,'["cook_most_meals"]'),('food','quick','quick / convenience meals',2,'["easy_convenience"]'),('food','batch','batch cook',3,'["batch_cook"]'),('food','eat_out','eat out a lot',4,'["eat_out_regularly"]'),('food','school_lunch','school / work meals',5,'["school_work_meals"]'),('food','bulk','bulk shop',6,'["bulk_shop"]'),('food','small_trips','small grocery trips',7,'["small_frequent_shops"]'),('food','special_diets','special diets',8,'["special_diets"]'),
('interests','running','running',1,'["training_fitness_goal"]'),('interests','gym','gym / fitness',2,'["training_fitness_goal"]'),('interests','gardening','gardening',3,'["home_project"]'),('interests','reading','reading',4,'["learning_hobby"]'),('interests','crafts','crafts / making things',5,'["learning_hobby"]'),('interests','gaming','gaming',6,'["learning_hobby"]'),('interests','music','music',7,'["learning_hobby"]'),('interests','outdoors','outdoors',8,'["training_fitness_goal"]'),('interests','travel','travel',9,'["vacation_trip"]'),('interests','learning','learning something new',10,'["learning_hobby"]'),('interests','none','nothing in particular',11,'[]'),
('right_now','new_baby','new baby',1,'["new_baby"]'),('right_now','moving','moving',2,'["moving"]'),('right_now','new_job','new job / work change',3,'["job_change"]'),('right_now','money_reset','money reset',4,'["financial_recovery"]'),('right_now','training','training for something',5,'["training_fitness_goal"]'),('right_now','trip','planning a trip',6,'["vacation_trip"]'),('right_now','home_project','home project',7,'["home_project"]'),('right_now','school_season','school season',8,'["school_year_change"]'),('right_now','business','starting / building a business',9,'["business_launch"]'),('right_now','nothing_major','nothing major',10,'[]')
on conflict (question_key,option_key) do update set label=excluded.label,position=excluded.position,root_tags=excluded.root_tags,active=true;

create or replace function atlas.personal_welcome_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_household_id uuid; v_questions jsonb; v_members jsonb; v_companions jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 v_household_id:=atlas.principal_current_household_id_v1(); if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('questionKey',q.question_key,'title',q.title,'prompt',q.prompt,'selectionKind',q.selection_kind,'options',(select coalesce(jsonb_agg(jsonb_build_object('optionKey',o.option_key,'label',o.label) order by o.position),'[]'::jsonb) from atlas.welcome_calibration_options o where o.question_key=q.question_key and o.active),'selected',coalesce(c.selections,'[]'::jsonb),'confirmed',coalesce(c.confirmed,false)) order by q.position),'[]'::jsonb) into v_questions from atlas.welcome_calibration_questions q left join atlas.household_welcome_calibrations c on c.household_id=v_household_id and c.question_key=q.question_key where q.active;
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'displayName',m.display_name,'relationship',m.relationship,'lifeStage',m.metadata->>'lifeStage') order by m.created_at),'[]'::jsonb) into v_members from atlas.household_members m where m.household_id=v_household_id and m.active;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'displayName',c.display_name,'species',c.species) order by c.created_at),'[]'::jsonb) into v_companions from atlas.household_companions c where c.household_id=v_household_id and c.active;
 return jsonb_build_object('ok',true,'contractVersion','personal_welcome_self_api_v1','householdId',v_household_id,'questions',v_questions,'members',v_members,'companions',v_companions);
end;$$;

create or replace function atlas.upsert_personal_welcome_response_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_household_id uuid; v_question text; v_selected jsonb; v_kind text; v_bad integer;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 v_household_id:=atlas.principal_current_household_id_v1(); if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
 v_question:=nullif(trim(p_input->>'questionKey'),''); v_selected:=coalesce(p_input->'selections','[]'::jsonb);
 if v_question is null or jsonb_typeof(v_selected)<>'array' then raise exception 'Invalid welcome response.' using errcode='22023'; end if;
 select selection_kind into v_kind from atlas.welcome_calibration_questions where question_key=v_question and active; if v_kind is null then raise exception 'Unknown welcome question.' using errcode='22023'; end if;
 select count(*) into v_bad from jsonb_array_elements_text(v_selected) t(x) where not exists(select 1 from atlas.welcome_calibration_options o where o.question_key=v_question and o.option_key=t.x and o.active); if v_bad>0 then raise exception 'Unknown welcome option.' using errcode='22023'; end if;
 insert into atlas.household_welcome_calibrations(household_id,question_key,selections,source,confirmed,confirmed_by,confirmed_at,metadata) values(v_household_id,v_question,v_selected,'self_reported',true,auth.uid(),now(),jsonb_build_object('enteredFrom','personal_welcome_v1')) on conflict(household_id,question_key) do update set selections=excluded.selections,source='self_reported',confirmed=true,confirmed_by=auth.uid(),confirmed_at=now(),updated_at=now(),metadata=atlas.household_welcome_calibrations.metadata||excluded.metadata;
 insert into atlas.household_welcome_history(household_id,question_key,selections,source,changed_by,metadata) values(v_household_id,v_question,v_selected,'self_reported',auth.uid(),jsonb_build_object('enteredFrom','personal_welcome_v1'));
 return jsonb_build_object('ok',true,'questionKey',v_question,'selections',v_selected);
end;$$;

create or replace function atlas.upsert_personal_household_member_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_household_id uuid; v_name text; v_relationship text; v_life text; v_key text; v_member atlas.household_members%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 v_household_id:=atlas.principal_current_household_id_v1(); if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
 v_name:=nullif(trim(p_input->>'displayName'),''); v_relationship:=nullif(trim(p_input->>'relationship'),''); v_life:=nullif(trim(p_input->>'lifeStage'),''); v_key:=nullif(trim(p_input->>'welcomeKey'),''); if v_name is null or v_relationship is null or v_key is null then raise exception 'Name, relationship, and welcomeKey are required.' using errcode='22023'; end if;
 select * into v_member from atlas.household_members where household_id=v_household_id and metadata->>'welcomeKey'=v_key limit 1;
 if v_member.id is null then insert into atlas.household_members(household_id,user_id,display_name,relationship,household_role,active,metadata) values(v_household_id,null,v_name,v_relationship,'member',true,jsonb_strip_nulls(jsonb_build_object('source','personal_welcome_v1','welcomeKey',v_key,'lifeStage',v_life))) returning * into v_member;
 else update atlas.household_members set display_name=v_name,relationship=v_relationship,active=true,metadata=metadata||jsonb_strip_nulls(jsonb_build_object('source','personal_welcome_v1','lifeStage',v_life)),updated_at=now() where id=v_member.id returning * into v_member; end if;
 return jsonb_build_object('ok',true,'member',jsonb_build_object('id',v_member.id,'displayName',v_member.display_name,'relationship',v_member.relationship,'lifeStage',v_member.metadata->>'lifeStage'));
end;$$;

create or replace function atlas.upsert_personal_companion_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_household_id uuid; v_name text; v_species text; v_key text; v_comp atlas.household_companions%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 v_household_id:=atlas.principal_current_household_id_v1(); if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
 v_name:=nullif(trim(p_input->>'displayName'),''); v_species:=nullif(trim(p_input->>'species'),''); v_key:=nullif(trim(p_input->>'welcomeKey'),''); if v_name is null or v_species is null or v_key is null then raise exception 'Name, species, and welcomeKey are required.' using errcode='22023'; end if;
 select * into v_comp from atlas.household_companions where household_id=v_household_id and metadata->>'welcomeKey'=v_key limit 1;
 if v_comp.id is null then insert into atlas.household_companions(household_id,display_name,species,metadata) values(v_household_id,v_name,v_species,jsonb_build_object('source','personal_welcome_v1','welcomeKey',v_key)) returning * into v_comp; else update atlas.household_companions set display_name=v_name,species=v_species,active=true,updated_at=now() where id=v_comp.id returning * into v_comp; end if;
 return jsonb_build_object('ok',true,'companion',jsonb_build_object('id',v_comp.id,'displayName',v_comp.display_name,'species',v_comp.species));
end;$$;

create or replace function atlas.personal_kernel_models_self_api_v1(p_kernel_key text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare v_household_id uuid; v_version integer; v_context text[] := '{}'; v_models jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 v_household_id := atlas.principal_current_household_id_v1(); if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
 select max(version) into v_version from atlas.world_kernel_definitions where kernel_key=p_kernel_key and active; if v_version is null then raise exception 'Unknown world kernel.' using errcode='22023'; end if;
 select coalesce(array_agg(distinct tag),'{}'::text[]) into v_context from (select x as tag from atlas.household_root_calibrations c, lateral jsonb_array_elements_text(c.selections) t(x) where c.household_id=v_household_id and c.confirmed union all select rt.tag from atlas.household_welcome_calibrations wc join lateral jsonb_array_elements_text(wc.selections) s(sel) on true join atlas.welcome_calibration_options wo on wo.question_key=wc.question_key and wo.option_key=s.sel join lateral jsonb_array_elements_text(wo.root_tags) rt(tag) on true where wc.household_id=v_household_id and wc.confirmed union all select case when lower(coalesce(m.relationship,'')) in ('child','son','daughter') then coalesce(m.metadata->>'lifeStage','school_age_kids') else null end from atlas.household_members m where m.household_id=v_household_id and m.active union all select 'pets' from atlas.household_companions c where c.household_id=v_household_id and c.active) q(tag) where tag is not null;
 select coalesce(jsonb_agg(jsonb_build_object('modelKey',q.model_key,'title',q.title,'summary',q.summary,'configuration',q.configuration,'score',q.score) order by q.score desc,q.position),'[]'::jsonb) into v_models from (select m.*,coalesce((select count(*) from jsonb_array_elements_text(m.context_tags) t(tag) where tag=any(v_context)),0) as score from atlas.world_kernel_models m where m.kernel_key=p_kernel_key and m.kernel_version=v_version and m.active order by score desc,m.position limit 3) q;
 return jsonb_build_object('ok',true,'contractVersion','personal_kernel_models_self_api_v1','kernelKey',p_kernel_key,'kernelVersion',v_version,'contextTags',to_jsonb(v_context),'models',v_models);
end;$$;

create or replace function public.personal_welcome_self_api_v1() returns jsonb language sql stable security definer set search_path=pg_catalog as $$select atlas.personal_welcome_self_api_v1();$$;
create or replace function public.upsert_personal_welcome_response_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $$select atlas.upsert_personal_welcome_response_self_api_v1(p_input);$$;
create or replace function public.upsert_personal_household_member_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $$select atlas.upsert_personal_household_member_self_api_v1(p_input);$$;
create or replace function public.upsert_personal_companion_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $$select atlas.upsert_personal_companion_self_api_v1(p_input);$$;
revoke all on function atlas.personal_welcome_self_api_v1() from public,anon,authenticated; revoke all on function atlas.upsert_personal_welcome_response_self_api_v1(jsonb) from public,anon,authenticated; revoke all on function atlas.upsert_personal_household_member_self_api_v1(jsonb) from public,anon,authenticated; revoke all on function atlas.upsert_personal_companion_self_api_v1(jsonb) from public,anon,authenticated;
revoke all on function public.personal_welcome_self_api_v1() from public,anon; revoke all on function public.upsert_personal_welcome_response_self_api_v1(jsonb) from public,anon; revoke all on function public.upsert_personal_household_member_self_api_v1(jsonb) from public,anon; revoke all on function public.upsert_personal_companion_self_api_v1(jsonb) from public,anon;
grant execute on function public.personal_welcome_self_api_v1() to authenticated,service_role; grant execute on function public.upsert_personal_welcome_response_self_api_v1(jsonb) to authenticated,service_role; grant execute on function public.upsert_personal_household_member_self_api_v1(jsonb) to authenticated,service_role; grant execute on function public.upsert_personal_companion_self_api_v1(jsonb) to authenticated,service_role;