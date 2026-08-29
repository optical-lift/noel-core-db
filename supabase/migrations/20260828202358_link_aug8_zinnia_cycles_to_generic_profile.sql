update atlas.crop_cycles cc
set crop_profile_id = cp.id,
    metadata = coalesce(cc.metadata,'{}'::jsonb) || jsonb_build_object(
      'crop_profile_reconciled_at', now(),
      'crop_profile_reconciliation', 'exact_alias_match',
      'crop_profile_reconciliation_source', 'crop_lifecycle_reconciliation_20260828'
    ),
    updated_at = now()
from atlas.crop_profiles cp
where cp.stable_key = 'zinnia_cut_flower_generic'
  and cc.farm_id = '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and cc.lifecycle_status = 'active'
  and cc.crop_profile_id is null
  and cc.crop_label = 'Zinnia transplants · Aug 8'
  and lower(coalesce(cc.variety,'')) = 'zinnia';