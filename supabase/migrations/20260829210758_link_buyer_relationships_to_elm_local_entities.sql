alter table atlas.buyer_relationship_reconstruction
  add column if not exists entity_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'atlas.buyer_relationship_reconstruction'::regclass
      and conname = 'buyer_relationship_reconstruction_entity_id_fkey'
  ) then
    alter table atlas.buyer_relationship_reconstruction
      add constraint buyer_relationship_reconstruction_entity_id_fkey
      foreign key (entity_id) references local_intel.entities(id) on delete restrict;
  end if;
end $$;

create index if not exists buyer_relationship_reconstruction_entity_id_idx
  on atlas.buyer_relationship_reconstruction(entity_id)
  where entity_id is not null;

with targets(buyer_key, entity_key, business_name, city, email, bounced) as (values
('community_southern_baptist_fair_grove','community_southern_baptist_fair_grove','Community Southern Baptist Church','Fair Grove','csbcfg@gmail.com',false),
('fair_grove_first_baptist','fair_grove_first_baptist','Fair Grove First Baptist Church','Fair Grove','info@fgfbc.org',true),
('fair_grove_united_methodist','fair_grove_united_methodist','Fair Grove United Methodist Church','Fair Grove','office@fairgroveumc.org',false),
('holy_trinity_catholic_marshfield','holy-trinity-catholic-marshfield-candidate','Holy Trinity Catholic Church','Marshfield','holytrinitymarshfield@gmail.com',false),
('hope_church_nazarene_marshfield','hope_church_nazarene_marshfield','Hope Church of the Nazarene','Marshfield','hopechurch.stephen@gmail.com',false),
('kingdom_church_marshfield','kingdom_church_marshfield','Kingdom Church','Marshfield','hello@kingdomchurch.info',false),
('marshfield_first_baptist','marshfield_first_baptist','Marshfield First Baptist Church','Marshfield','office@marshfieldfirst.org',false),
('marshfield_united_methodist','marshfield_umc','Marshfield United Methodist Church','Marshfield','marshfieldumchurch@gmail.com',false),
('temple_baptist_marshfield','temple-baptist-marshfield-candidate','Temple Baptist Church','Marshfield','tbcmarshfield@gmail.com',false),
('aldersgate_church_nixa','aldersgate_church_nixa','Aldersgate Church','Nixa','info@aldersgatechurch.com',false),
('cassidy_church_nixa','cassidy_church_nixa','Cassidy Church','Nixa','admin@cassidychurch.org',false),
('nixa_seventh_day_adventist','nixa_seventh_day_adventist','Nixa Seventh-day Adventist Church','Nixa','nixasdachurch@gmail.com',false),
('redeemer_lutheran_nixa','redeemer_lutheran_nixa','Redeemer Lutheran Church - Nixa','Nixa','rlc@rlcmail.org',false),
('st_francis_assisi_nixa','st_francis_assisi_nixa','St. Francis of Assisi Catholic Church','Nixa','office@stfrancisnixa.org',false),
('thrive_church_nixa','thrive_church_nixa','Thrive Church','Nixa','info@thrivechurch.city',false),
('union_hill_church_christ_nixa','union_hill_church_christ_nixa','Union Hill Church of Christ','Nixa','office@unionhillcofc.com',false),
('calvary_baptist_republic','calvary_baptist_republic','Calvary Baptist Church','Republic','office@calvarmo.com',true),
('calvary_chapel_republic','calvary_chapel_republic','Calvary Chapel Republic','Republic','republic@ccrepublic.com',false),
('hope_lutheran_republic','hope_lutheran_republic','Hope Lutheran Church','Republic','secretary@hopelc.com',false),
('live_church_republic','live_church_republic','Live Church','Republic','info@wearelive.church',false),
('republic_first_baptist','republic_first_baptist','Republic First Baptist Church','Republic','fbcsec1@sbcglobal.net',false),
('christ_episcopal_springfield','christ_episcopal_springfield','Christ Episcopal Church','Springfield','frontoffice@christepiscopalchurch.com',false),
('holy_trinity_catholic_springfield','holy_trinity_catholic_springfield','Holy Trinity Catholic Church','Springfield','trinityoffice@htscatholic.com',false),
('immaculate_conception_springfield','immaculate_conception_springfield','Immaculate Conception Catholic Church','Springfield','staff@ic-parish.org',false),
('springfield_seventh_day_adventist','springfield_seventh_day_adventist','Springfield Seventh-day Adventist Church','Springfield','headdeaconess@springfieldsda.org',false),
('st_elizabeth_ann_seton_springfield','st_elizabeth_ann_seton_springfield','St. Elizabeth Ann Seton Catholic Church','Springfield','parishinfo@seaschurch.org',false),
('st_james_episcopal_springfield','st_james_episcopal_springfield','St. James Episcopal Church','Springfield','office@sj.church',false),
('st_johns_episcopal_springfield','st_johns_episcopal_springfield','St. Johns Episcopal Church','Springfield','stjohns-spgfld@sbcglobal.net',false),
('bass_chapel_baptist','bass_chapel_baptist','Bass Chapel Baptist Church','Strafford','pastorzach@basschapel.church',false),
('berean_baptist_strafford','berean_baptist_strafford','Berean Baptist Church','Strafford','bereanbaptiststrafford@gmail.com',false),
('first_baptist_strafford','first_baptist_strafford','First Baptist Church of Strafford','Strafford','church@fbcstrafford.org',false),
('landmark_church_strafford','landmark_church_strafford','Landmark Church','Strafford','landmarkstrafford@gmail.com',false)
)
insert into local_intel.entities(stable_key,entity_type,name,email,city,state,status,verification_state,metadata)
select entity_key,'organization',business_name,
       case when bounced then null else email end,
       city,'MO','active','public_indexed',
       jsonb_build_object(
         'category','church',
         'publication_state','identity_publishable',
         'elm_local_outreach_reconciled',true,
         'elm_local_outreach_reconciled_on','2026-08-29',
         'owner_contacted_email',email
       )
from targets
on conflict (stable_key) do update
set city = coalesce(local_intel.entities.city, excluded.city),
    state = coalesce(local_intel.entities.state, excluded.state),
    email = case
      when excluded.email is null then local_intel.entities.email
      else coalesce(local_intel.entities.email, excluded.email)
    end,
    metadata = coalesce(local_intel.entities.metadata,'{}'::jsonb) || excluded.metadata,
    updated_at = now();

with targets(entity_key, email, bounced) as (values
('community_southern_baptist_fair_grove','csbcfg@gmail.com',false),
('fair_grove_first_baptist','info@fgfbc.org',true),
('fair_grove_united_methodist','office@fairgroveumc.org',false),
('holy-trinity-catholic-marshfield-candidate','holytrinitymarshfield@gmail.com',false),
('hope_church_nazarene_marshfield','hopechurch.stephen@gmail.com',false),
('kingdom_church_marshfield','hello@kingdomchurch.info',false),
('marshfield_first_baptist','office@marshfieldfirst.org',false),
('marshfield_umc','marshfieldumchurch@gmail.com',false),
('temple-baptist-marshfield-candidate','tbcmarshfield@gmail.com',false),
('aldersgate_church_nixa','info@aldersgatechurch.com',false),
('cassidy_church_nixa','admin@cassidychurch.org',false),
('nixa_seventh_day_adventist','nixasdachurch@gmail.com',false),
('redeemer_lutheran_nixa','rlc@rlcmail.org',false),
('st_francis_assisi_nixa','office@stfrancisnixa.org',false),
('thrive_church_nixa','info@thrivechurch.city',false),
('union_hill_church_christ_nixa','office@unionhillcofc.com',false),
('calvary_baptist_republic','office@calvarmo.com',true),
('calvary_chapel_republic','republic@ccrepublic.com',false),
('hope_lutheran_republic','secretary@hopelc.com',false),
('live_church_republic','info@wearelive.church',false),
('republic_first_baptist','fbcsec1@sbcglobal.net',false),
('christ_episcopal_springfield','frontoffice@christepiscopalchurch.com',false),
('holy_trinity_catholic_springfield','trinityoffice@htscatholic.com',false),
('immaculate_conception_springfield','staff@ic-parish.org',false),
('springfield_seventh_day_adventist','headdeaconess@springfieldsda.org',false),
('st_elizabeth_ann_seton_springfield','parishinfo@seaschurch.org',false),
('st_james_episcopal_springfield','office@sj.church',false),
('st_johns_episcopal_springfield','stjohns-spgfld@sbcglobal.net',false),
('bass_chapel_baptist','pastorzach@basschapel.church',false),
('berean_baptist_strafford','bereanbaptiststrafford@gmail.com',false),
('first_baptist_strafford','church@fbcstrafford.org',false),
('landmark_church_strafford','landmarkstrafford@gmail.com',false)
), resolved as (
  select e.id as entity_id,t.email,t.bounced
  from targets t join local_intel.entities e on e.stable_key=t.entity_key
)
insert into local_intel.contact_points(
  entity_id,contact_type,contact_value,normalized_value,context,contact_scope,is_primary,visibility,
  verification_state,deliverability_state,marketing_status,last_checked_at,suppression_reason,metadata
)
select entity_id,'email',email,lower(email),'professional','organization_general',true,'public',
       'public_source_current',
       case when bounced then 'hard_bounce' else 'unknown' end,
       case when bounced then 'suppressed' else 'eligible_unknown' end,
       now(),
       case when bounced then 'owner_reported_undeliverable_2026_08_29' else null end,
       jsonb_build_object('owner_outreach_sent_on','2026-08-29','elm_local_reconciled',true)
from resolved
on conflict (entity_id,contact_type,normalized_value) do update
set last_checked_at=excluded.last_checked_at,
    deliverability_state=case when excluded.deliverability_state='hard_bounce' then 'hard_bounce' else local_intel.contact_points.deliverability_state end,
    marketing_status=case when excluded.deliverability_state='hard_bounce' then 'suppressed' else local_intel.contact_points.marketing_status end,
    suppression_reason=case when excluded.deliverability_state='hard_bounce' then excluded.suppression_reason else local_intel.contact_points.suppression_reason end,
    metadata=coalesce(local_intel.contact_points.metadata,'{}'::jsonb) || excluded.metadata,
    updated_at=now();

with bounced(email) as (values ('info@fgfbc.org'),('office@calvarmo.com')),
cp as (
  select cp.id,cp.contact_value
  from local_intel.contact_points cp join bounced b on lower(cp.normalized_value)=lower(b.email)
  where cp.contact_type='email'
)
insert into local_intel.contact_point_events(contact_point_id,event_type,occurred_at,evidence_text,metadata)
select cp.id,'bounced_hard',now(),
       'Owner reported this Elm Local email address was undeliverable after outreach on 2026-08-29.',
       jsonb_build_object('reported_by','Lex','outreach_date','2026-08-29','source','owner_report')
from cp
where not exists (
  select 1 from local_intel.contact_point_events e
  where e.contact_point_id=cp.id and e.event_type='bounced_hard'
    and e.metadata->>'outreach_date'='2026-08-29'
);

with mapping(buyer_key,entity_key) as (values
('community_southern_baptist_fair_grove','community_southern_baptist_fair_grove'),
('fair_grove_first_baptist','fair_grove_first_baptist'),
('fair_grove_united_methodist','fair_grove_united_methodist'),
('holy_trinity_catholic_marshfield','holy-trinity-catholic-marshfield-candidate'),
('hope_church_nazarene_marshfield','hope_church_nazarene_marshfield'),
('kingdom_church_marshfield','kingdom_church_marshfield'),
('marshfield_first_baptist','marshfield_first_baptist'),
('marshfield_united_methodist','marshfield_umc'),
('temple_baptist_marshfield','temple-baptist-marshfield-candidate'),
('aldersgate_church_nixa','aldersgate_church_nixa'),
('cassidy_church_nixa','cassidy_church_nixa'),
('nixa_seventh_day_adventist','nixa_seventh_day_adventist'),
('redeemer_lutheran_nixa','redeemer_lutheran_nixa'),
('st_francis_assisi_nixa','st_francis_assisi_nixa'),
('thrive_church_nixa','thrive_church_nixa'),
('union_hill_church_christ_nixa','union_hill_church_christ_nixa'),
('calvary_baptist_republic','calvary_baptist_republic'),
('calvary_chapel_republic','calvary_chapel_republic'),
('hope_lutheran_republic','hope_lutheran_republic'),
('live_church_republic','live_church_republic'),
('republic_first_baptist','republic_first_baptist'),
('christ_episcopal_springfield','christ_episcopal_springfield'),
('holy_trinity_catholic_springfield','holy_trinity_catholic_springfield'),
('immaculate_conception_springfield','immaculate_conception_springfield'),
('springfield_seventh_day_adventist','springfield_seventh_day_adventist'),
('st_elizabeth_ann_seton_springfield','st_elizabeth_ann_seton_springfield'),
('st_james_episcopal_springfield','st_james_episcopal_springfield'),
('st_johns_episcopal_springfield','st_johns_episcopal_springfield'),
('bass_chapel_baptist','bass_chapel_baptist'),
('berean_baptist_strafford','berean_baptist_strafford'),
('first_baptist_strafford','first_baptist_strafford'),
('landmark_church_strafford','landmark_church_strafford')
), resolved as (
  select m.buyer_key,e.id entity_id
  from mapping m join local_intel.entities e on e.stable_key=m.entity_key
)
update atlas.buyer_relationship_reconstruction r
set entity_id=resolved.entity_id,
    metadata=coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object('elm_local_entity_linked',true),
    updated_at=now()
from resolved
where r.farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'
  and r.stable_key=resolved.buyer_key;

create or replace view intelligence.v_noel_buyer_relationships as
select r.id,
    r.farm_id,
    f.stable_key as farm_key,
    f.name as farm_name,
    r.stable_key,
    r.business_name,
    r.buyer_type,
    r.city,
    r.primary_contact_name,
    r.relationship_status,
    r.priority_rank,
    r.volume_tier,
    r.purchase_history_summary,
    r.product_interests,
    r.buying_preferences,
    r.payment_behavior,
    r.access_notes,
    r.pursuit_recommendation,
    r.next_action,
    r.source_person,
    r.source_date,
    r.metadata,
    r.created_at,
    r.updated_at,
    latest.occurred_at as last_contact_at,
    latest.outcome as last_contact_outcome,
    latest.contact_name as last_contact_name,
    latest.follow_up as last_contact_follow_up,
    coalesce(counts.contact_event_count,0) as contact_event_count,
    r.entity_id,
    le.stable_key as elm_local_stable_key,
    le.name as elm_local_entity_name,
    le.city as elm_local_city
from atlas.buyer_relationship_reconstruction r
join atlas.farms f on f.id=r.farm_id
left join local_intel.entities le on le.id=r.entity_id
left join lateral (
  select e.occurred_at,e.outcome,e.contact_name,e.follow_up
  from atlas.buyer_contact_events e
  where e.buyer_relationship_id=r.id
  order by e.occurred_at desc,e.created_at desc
  limit 1
) latest on true
left join lateral (
  select count(*)::integer as contact_event_count
  from atlas.buyer_contact_events e
  where e.buyer_relationship_id=r.id
) counts on true;