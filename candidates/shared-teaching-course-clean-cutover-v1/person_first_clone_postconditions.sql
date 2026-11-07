-- SHARED COURSE V1 — M1 structural proof, clone only after candidate.
-- READ ONLY; DOES NOT prove signed auth / data adoption / migration safety.
WITH root_cols AS (
 SELECT attname,attnotnull
 FROM pg_attribute
 WHERE attrelid='atlas.teaching_courses'::regclass AND attnum>0 AND NOT attisdropped
),
routines AS (
 SELECT p.oid,p.proname,n.nspname
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='public' AND p.proname='shared_teaching_course_create_self_api_v1')
 OR (n.nspname='atlas' AND p.proname='current_person_for_private_course_v1')
),
checks(name,ok) AS (
 VALUES
 ('Course remains one atlas canonical root',to_regclass('atlas.teaching_courses') IS NOT NULL),
 ('Person-origin writer available',
   to_regprocedure('public.shared_teaching_course_create_self_api_v1(uuid,text)') IS NOT NULL),
 ('auth resolver available',
   to_regprocedure('atlas.current_person_for_private_course_v1()') IS NOT NULL),
 ('canonical founder Person required',
   exists(select 1 from root_cols where attname='created_by_person_entity_id' and attnotnull)),
 ('request idempotency required',
   exists(select 1 from root_cols where attname='create_request_id' and attnotnull)),
 ('Course root Ledger no longer mandatory',
   exists(select 1 from root_cols where attname='ledger_id' and not attnotnull)),
 ('Course root activation no longer mandatory',
   exists(select 1 from root_cols where attname='capability_activation_id' and not attnotnull)),
 ('Course root old Principal no longer mandatory',
   exists(select 1 from root_cols where attname='created_by_principal_id' and not attnotnull)),
 ('canonical manuscript revision storage',
   to_regclass('atlas.teaching_course_manuscript_revisions') IS NOT NULL),
 ('canonical authored Unit storage',
   to_regclass('atlas.teaching_course_units') IS NOT NULL),
 ('canonical authored Unit revision storage',
   to_regclass('atlas.teaching_course_unit_revisions') IS NOT NULL),
 ('new private manuscript table RLS enabled',
   exists(select 1 from pg_class where oid=to_regclass('atlas.teaching_course_manuscript_revisions') and relrowsecurity)),
 ('new Unit table RLS enabled',
   exists(select 1 from pg_class where oid=to_regclass('atlas.teaching_course_units') and relrowsecurity)),
 ('new Unit revision table RLS enabled',
   exists(select 1 from pg_class where oid=to_regclass('atlas.teaching_course_unit_revisions') and relrowsecurity)),
 ('SK 101 private original NOT deleted by M1',
   (select count(*) from titus.customer_course_drafts_v1)=1),
 ('no synthetic duplicate Course seeded in M1',
   (select count(*) from atlas.teaching_courses)=0)
)
SELECT name,ok FROM checks ORDER BY name;
-- The signed GoTrue/PostgREST owner, second-Person, anonymous, revoked-author,
-- exact-request replay and changed-title-denial checks are separate required
-- tests. Do NOT claim complete M1 acceptance from static postconditions.
