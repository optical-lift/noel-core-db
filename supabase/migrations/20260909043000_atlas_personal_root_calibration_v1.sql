-- Personal Root Calibration V1.
-- Source-defined high-information household calibration used to rank downstream world-kernel models.

create table if not exists atlas.root_calibration_dimensions (
  dimension_key text primary key,
  title text not null,
  prompt text not null,
  selection_kind text not null check (selection_kind in ('multi_select','single_select','quantity')),
  position smallint not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists atlas.root_calibration_options (
  dimension_key text not null references atlas.root_calibration_dimensions(dimension_key) on delete cascade,
  option_key text not null,
  label text not null,
  position smallint not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  primary key (dimension_key, option_key)
);

create table if not exists atlas.household_root_calibrations (
  household_id uuid not null references atlas.households(id) on delete cascade,
  dimension_key text not null references atlas.root_calibration_dimensions(dimension_key),
  selections jsonb not null default '[]'::jsonb,
  quantity integer,
  source text not null default 'self_reported',
  confirmed boolean not null default true,
  confirmed_by uuid,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (household_id, dimension_key)
);

create table if not exists atlas.household_root_calibration_history (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  dimension_key text not null,
  selections jsonb not null,
  quantity integer,
  source text not null,
  confirmed boolean not null,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

alter table atlas.root_calibration_dimensions enable row level security;
alter table atlas.root_calibration_options enable row level security;
alter table atlas.household_root_calibrations enable row level security;
alter table atlas.household_root_calibration_history enable row level security;
revoke all on atlas.root_calibration_dimensions, atlas.root_calibration_options, atlas.household_root_calibrations, atlas.household_root_calibration_history from public, anon, authenticated;

insert into atlas.root_calibration_dimensions(dimension_key,title,prompt,selection_kind,position) values
('household_people','Household','Who is part of home life here?','multi_select',1),
('home_shape','Home','What is home like?','multi_select',2),
('week_structure','Week','What does a normal week include?','multi_select',3),
('mobility','Getting around','How does this household usually get around?','multi_select',4),
('food_pattern','Food','How does food usually work here?','multi_select',5),
('money_structure','Money','What is structurally true about household money?','multi_select',6),
('institutions','Recurring places','What recurring institutions are attached to this household?','multi_select',7),
('care_load','Care','What kinds of ongoing care responsibility exist?','multi_select',8),
('outward_life','Social life','What does life outside the house tend to look like?','multi_select',9),
('current_change','What is changing','What is changing or being pursued right now?','multi_select',10)
on conflict (dimension_key) do update set title=excluded.title,prompt=excluded.prompt,selection_kind=excluded.selection_kind,position=excluded.position,active=true;

insert into atlas.root_calibration_options(dimension_key,option_key,label,position) values
('household_people','me','me',1),('household_people','spouse_partner','spouse / partner',2),('household_people','babies_toddlers','babies / toddlers',3),('household_people','school_age_kids','school-age kids',4),('household_people','teenagers','teenagers',5),('household_people','adult_children','adult children',6),('household_people','roommates','roommates',7),('household_people','older_family','older family',8),('household_people','pets','pets',9),('household_people','something_else','something else',10),
('home_shape','apartment','apartment',1),('home_shape','townhouse_duplex','townhouse / duplex',2),('home_shape','small_house','small house',3),('home_shape','ordinary_family_house','ordinary family house',4),('home_shape','large_house','large house',5),('home_shape','rural_property','rural property',6),('home_shape','multiple_buildings','multiple buildings',7),('home_shape','rent','rent',8),('home_shape','own','own',9),('home_shape','family_owned_other','family-owned / other',10),('home_shape','no_outdoor_upkeep','no outdoor upkeep',11),('home_shape','small_yard','small yard',12),('home_shape','big_yard','big yard',13),('home_shape','acreage','land / acreage',14),
('week_structure','work_away','work away from home',1),('week_structure','work_from_home','work from home',2),('week_structure','school','school',3),('week_structure','homeschool','homeschool',4),('week_structure','daycare','daycare',5),('week_structure','shift_work','shift work',6),('week_structure','sports_activities','sports / activities',7),('week_structure','church_community','church / community',8),('week_structure','frequent_appointments','frequent appointments',9),('week_structure','travel','travel',10),
('mobility','one_car','one car',1),('mobility','multiple_cars','multiple cars',2),('mobility','public_transit','public transit',3),('mobility','walk_bike','walk / bike',4),('mobility','school_bus','school bus',5),('mobility','rural_driving','lots of rural driving',6),('mobility','frequent_flights','frequent flights',7),('mobility','rides_from_others','rides from others',8),
('food_pattern','cook_most_meals','cook most meals',1),('food_pattern','easy_convenience','easy / convenience meals',2),('food_pattern','batch_cook','batch cook',3),('food_pattern','lots_of_leftovers','lots of leftovers',4),('food_pattern','eat_out_regularly','eat out regularly',5),('food_pattern','school_work_meals','school / work meals',6),('food_pattern','bulk_shop','bulk shop',7),('food_pattern','small_frequent_shops','small frequent grocery trips',8),('food_pattern','special_diets','special diets',9),
('money_structure','steady_paycheck','steady paycheck',1),('money_structure','variable_income','income changes month to month',2),('money_structure','multiple_incomes','more than one income',3),('money_structure','shared_household_money','shared household money',4),('money_structure','some_separate_money','some money kept separate',5),('money_structure','mostly_autopay','mostly autopay',6),('money_structure','manual_bill_attention','I manually stay on top of bills',7),('money_structure','paying_down_debt','paying down debt',8),('money_structure','building_savings','building savings',9),('money_structure','planning_big_purchase_or_trip','planning for something big',10),
('institutions','employer','employer',1),('institutions','school','school',2),('institutions','daycare','daycare',3),('institutions','church','church',4),('institutions','sports','sports',5),('institutions','clubs_lessons','clubs / lessons',6),('institutions','medical_system','medical system',7),('institutions','government_programs','government programs',8),('institutions','memberships_subscriptions','memberships / subscriptions',9),('institutions','other_recurring_institution','something else recurring',10),
('care_load','young_children','young children',1),('care_load','elder_care','elder care',2),('care_load','disability_support','disability support',3),('care_load','medication_management','medication management',4),('care_load','transportation_for_others','transportation for others',5),('care_load','pets','pets',6),('care_load','high_supervision','high supervision',7),('care_load','low_care_load','not much ongoing care load',8),
('outward_life','mostly_home_centered','mostly home-centered',1),('outward_life','activity_heavy','lots of activities',2),('outward_life','frequent_hosting','we host often',3),('outward_life','extended_family_often','extended family often',4),('outward_life','church_community_often','church / community often',5),('outward_life','friends_often','friends often',6),('outward_life','frequent_travel','frequent travel',7),('outward_life','quiet_social_calendar','quiet social calendar',8),
('current_change','new_baby','new baby',1),('current_change','moving','moving',2),('current_change','job_change','job change',3),('current_change','school_year_change','school-year change',4),('current_change','financial_recovery','financial recovery',5),('current_change','saving_for_something','saving for something',6),('current_change','training_fitness_goal','training / fitness goal',7),('current_change','learning_hobby','learning a hobby',8),('current_change','home_project','home project',9),('current_change','vacation_trip','vacation / trip',10),('current_change','business_launch','business launch',11),('current_change','other_major_change','something else major',12)
on conflict (dimension_key,option_key) do update set label=excluded.label,position=excluded.position,active=true;

alter table atlas.world_kernel_models add column if not exists context_tags jsonb not null default '[]'::jsonb;

insert into atlas.world_kernel_definitions(kernel_key,version,scope_kind,title,definition,active) values
('household.cleaning',1,'household','Cleaning',jsonb_build_object('contractVersion','household_cleaning_world_kernel_v1','ordinary',true,'topology',jsonb_build_array('use_space','accumulate_disorder_soil','reset_clean','restore_ready_state'),'dependencies',jsonb_build_array('people','rooms','surfaces','supplies','care_load','hosting','property_size')),true),
('household.groceries',1,'household','Groceries',jsonb_build_object('contractVersion','household_groceries_world_kernel_v1','ordinary',true,'topology',jsonb_build_array('consume','notice_depletion','plan_replenishment','acquire','store'),'dependencies',jsonb_build_array('people','food_pattern','storage','mobility','schedule','budget')),true)
on conflict (kernel_key,version) do update set title=excluded.title,definition=excluded.definition,active=true;

insert into atlas.world_kernel_models(kernel_key,kernel_version,audience_key,model_key,title,summary,configuration,position,active,context_tags) values
('household.cleaning',1,'general','cleaning_steady_reset','Steady reset','Small resets keep ordinary rooms from tipping over.',jsonb_build_object('usualPattern','little_most_days','expectedMinutes',30,'style','steady_reset'),1,true,'["babies_toddlers","school_age_kids","activity_heavy","work_from_home"]'),
('household.cleaning',1,'general','cleaning_zone_rotation','Zone rotation','The home is divided into areas and deeper attention rotates through them.',jsonb_build_object('usualPattern','few_times_week','expectedMinutes',60,'style','zone_rotation'),2,true,'["ordinary_family_house","large_house","rural_property","multiple_buildings","acreage"]'),
('household.cleaning',1,'general','cleaning_weekly_reset','Weekly reset','Daily life is tolerated and most cleaning is concentrated into one larger reset.',jsonb_build_object('usualPattern','main_day','expectedMinutes',120,'style','weekly_reset'),3,true,'["apartment","small_house","work_away","quiet_social_calendar"]'),
('household.cleaning',1,'general','cleaning_host_ready','Host-ready rhythm','Frequent quick resets protect the rooms guests actually see.',jsonb_build_object('usualPattern','few_times_week','expectedMinutes',45,'style','host_ready'),4,true,'["frequent_hosting","extended_family_often","friends_often","church_community_often"]'),
('household.groceries',1,'general','groceries_weekly_main','Weekly main shop','One substantial grocery trip carries most of the week.',jsonb_build_object('usualPattern','weekly','expectedMinutes',90,'style','weekly_main'),1,true,'["cook_most_meals","ordinary_family_house","multiple_cars"]'),
('household.groceries',1,'general','groceries_bulk_topup','Bulk + top-ups','A larger stock-up handles staples and smaller trips refill perishables.',jsonb_build_object('usualPattern','weekly_plus_topup','expectedMinutes',120,'style','bulk_topup'),2,true,'["bulk_shop","school_age_kids","teenagers","rural_driving","cook_most_meals"]'),
('household.groceries',1,'general','groceries_frequent_small','Frequent small shops','Food is bought in smaller amounts several times as the week develops.',jsonb_build_object('usualPattern','few_times_week','expectedMinutes',45,'style','frequent_small'),3,true,'["small_frequent_shops","apartment","walk_bike","public_transit","easy_convenience"]'),
('household.groceries',1,'general','groceries_convenience_mix','Convenience mix','Groceries, prepared food, and eating out share the load.',jsonb_build_object('usualPattern','as_needed','expectedMinutes',45,'style','convenience_mix'),4,true,'["easy_convenience","eat_out_regularly","work_away","sports_activities"]')
on conflict (kernel_key,kernel_version,model_key) do update set title=excluded.title,summary=excluded.summary,configuration=excluded.configuration,position=excluded.position,active=true,context_tags=excluded.context_tags;

-- Add context tags to existing Laundry models without changing their configured semantics.
update atlas.world_kernel_models set context_tags='["apartment","small_house","quiet_social_calendar"]'::jsonb where kernel_key='household.laundry' and model_key='one_person_home_reset';
update atlas.world_kernel_models set context_tags='["apartment","public_transit","walk_bike"]'::jsonb where kernel_key='household.laundry' and model_key='one_person_laundromat';
update atlas.world_kernel_models set context_tags='["work_away","quiet_social_calendar"]'::jsonb where kernel_key='household.laundry' and model_key='one_person_handled_elsewhere';
update atlas.world_kernel_models set context_tags='["babies_toddlers","school_age_kids","teenagers","high_supervision"]'::jsonb where kernel_key='household.laundry' and model_key='family_continuous_flow';
update atlas.world_kernel_models set context_tags='["school_age_kids","sports_activities","work_away"]'::jsonb where kernel_key='household.laundry' and model_key='family_laundry_days';
update atlas.world_kernel_models set context_tags='["school_age_kids","teenagers","large_house"]'::jsonb where kernel_key='household.laundry' and model_key='family_people_lanes';

create or replace function atlas.personal_root_calibration_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare
  v_household_id uuid;
  v_dimensions jsonb;
  v_context jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'dimensionKey',d.dimension_key,'title',d.title,'prompt',d.prompt,'selectionKind',d.selection_kind,
    'options',(select coalesce(jsonb_agg(jsonb_build_object('optionKey',o.option_key,'label',o.label) order by o.position),'[]'::jsonb) from atlas.root_calibration_options o where o.dimension_key=d.dimension_key and o.active),
    'selected',coalesce(c.selections,'[]'::jsonb),'quantity',c.quantity,'source',c.source,'confirmed',coalesce(c.confirmed,false)
  ) order by d.position),'[]'::jsonb) into v_dimensions
  from atlas.root_calibration_dimensions d
  left join atlas.household_root_calibrations c on c.household_id=v_household_id and c.dimension_key=d.dimension_key
  where d.active;

  select coalesce(jsonb_agg(distinct x),'[]'::jsonb) into v_context
  from atlas.household_root_calibrations c,
       lateral jsonb_array_elements_text(c.selections) t(x)
  where c.household_id=v_household_id and c.confirmed;

  return jsonb_build_object('ok',true,'contractVersion','personal_root_calibration_self_api_v1','householdId',v_household_id,'dimensions',v_dimensions,'contextTags',v_context);
end; $$;

create or replace function atlas.upsert_personal_root_calibration_self_api_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare
  v_household_id uuid;
  v_dimension text := nullif(trim(p_input->>'dimensionKey'),'');
  v_selections jsonb := coalesce(p_input->'selections','[]'::jsonb);
  v_quantity integer := case when nullif(p_input->>'quantity','') is null then null else (p_input->>'quantity')::integer end;
  v_row atlas.household_root_calibrations%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_dimension is null or not exists(select 1 from atlas.root_calibration_dimensions where dimension_key=v_dimension and active) then raise exception 'Unknown root calibration dimension.' using errcode='22023'; end if;
  if jsonb_typeof(v_selections) <> 'array' then raise exception 'Selections must be an array.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements_text(v_selections) s(x) where not exists(select 1 from atlas.root_calibration_options o where o.dimension_key=v_dimension and o.option_key=s.x and o.active)) then raise exception 'Unsupported root calibration option.' using errcode='22023'; end if;
  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  insert into atlas.household_root_calibration_history(household_id,dimension_key,selections,quantity,source,confirmed,changed_by,metadata)
  select household_id,dimension_key,selections,quantity,source,confirmed,auth.uid(),metadata from atlas.household_root_calibrations where household_id=v_household_id and dimension_key=v_dimension;

  insert into atlas.household_root_calibrations(household_id,dimension_key,selections,quantity,source,confirmed,confirmed_by,confirmed_at,metadata)
  values(v_household_id,v_dimension,v_selections,v_quantity,'self_reported',true,auth.uid(),now(),jsonb_build_object('enteredFrom','personal_root_calibration_v1'))
  on conflict(household_id,dimension_key) do update set selections=excluded.selections,quantity=excluded.quantity,source=excluded.source,confirmed=true,confirmed_by=excluded.confirmed_by,confirmed_at=now(),metadata=atlas.household_root_calibrations.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;
  return jsonb_build_object('ok',true,'dimensionKey',v_row.dimension_key,'selected',v_row.selections,'quantity',v_row.quantity);
end; $$;

create or replace function atlas.personal_kernel_models_self_api_v1(p_kernel_key text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $$
declare
  v_household_id uuid;
  v_version integer;
  v_context text[] := '{}';
  v_models jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  select max(version) into v_version from atlas.world_kernel_definitions where kernel_key=p_kernel_key and active;
  if v_version is null then raise exception 'Unknown world kernel.' using errcode='22023'; end if;
  select coalesce(array_agg(distinct x),'{}'::text[]) into v_context from atlas.household_root_calibrations c, lateral jsonb_array_elements_text(c.selections) t(x) where c.household_id=v_household_id and c.confirmed;

  select coalesce(jsonb_agg(jsonb_build_object('modelKey',q.model_key,'title',q.title,'summary',q.summary,'configuration',q.configuration,'score',q.score) order by q.score desc,q.position),'[]'::jsonb) into v_models
  from (
    select m.*, coalesce((select count(*) from jsonb_array_elements_text(m.context_tags) t(tag) where tag = any(v_context)),0) as score
    from atlas.world_kernel_models m
    where m.kernel_key=p_kernel_key and m.kernel_version=v_version and m.active
    order by score desc,m.position
    limit 3
  ) q;
  return jsonb_build_object('ok',true,'contractVersion','personal_kernel_models_self_api_v1','kernelKey',p_kernel_key,'kernelVersion',v_version,'contextTags',to_jsonb(v_context),'models',v_models);
end; $$;

create or replace function public.personal_root_calibration_self_api_v1() returns jsonb language sql stable security definer set search_path=pg_catalog as $$ select atlas.personal_root_calibration_self_api_v1(); $$;
create or replace function public.upsert_personal_root_calibration_self_api_v1(p_input jsonb) returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.upsert_personal_root_calibration_self_api_v1(p_input); $$;
create or replace function public.personal_kernel_models_self_api_v1(p_kernel_key text) returns jsonb language sql stable security definer set search_path=pg_catalog as $$ select atlas.personal_kernel_models_self_api_v1(p_kernel_key); $$;

revoke all on function public.personal_root_calibration_self_api_v1() from public,anon;
revoke all on function public.upsert_personal_root_calibration_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_kernel_models_self_api_v1(text) from public,anon;
grant execute on function public.personal_root_calibration_self_api_v1() to authenticated,service_role;
grant execute on function public.upsert_personal_root_calibration_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_kernel_models_self_api_v1(text) to authenticated,service_role;
