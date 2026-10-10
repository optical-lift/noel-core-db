-- Run only against a clone AFTER the migration is applied.
DO $test$
DECLARE p jsonb;
BEGIN
 SELECT intelligence.begin_noel_research_v1('What happens when grain becomes bread?',4,3,3) INTO p;
 IF p->>'preflight_complete' <> 'true'
    OR (p->>'recognized_pool_count')::int < 3 THEN
   RAISE EXCEPTION 'Grain + bread pools not loaded before discovery';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(p->'governing_pool_contexts') x
   WHERE x->'governed_context'->'mandatory_reality_categories' @>
     '[{"category_id":"reality:healing_holiness_restoration"}]'::jsonb
 ) THEN RAISE EXCEPTION 'Grain must inherit Healing/Holiness/Restoration'; END IF;
 SELECT intelligence.begin_noel_research_v1('Bless those who eat',3,2,3) INTO p;
 IF (p->>'recognized_pool_count')::int < 2 THEN
   RAISE EXCEPTION 'Eat and Bless are not independently routed'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(p->'governing_pool_contexts') x
   WHERE x->'governed_context'->'governing_seed' @>
     '[{"operative_definition":"Atonement happening.","authority_state":"steward_governed"}]'::jsonb
 ) THEN RAISE EXCEPTION 'The ratified Eat definition has been demoted'; END IF;
 SELECT intelligence.begin_noel_research_v1('H0398',3,1,2) INTO p;
 IF (p->>'recognized_pool_count')::int <> 1 THEN
   RAISE EXCEPTION 'Strong ID alias lookup failed'; END IF;
END $test$;
