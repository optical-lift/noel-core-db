-- Generic acceptance membrane for source-controlled Personal Reality Kernel models.
-- Accepting a model creates household-specific kernel calibration; the model itself remains generic world knowledge.

create or replace function atlas.accept_personal_kernel_model_self_api_v1(p_kernel_key text, p_model_key text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_household_id uuid;
  v_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_instance atlas.household_kernel_instances%rowtype;
  v_title text;
  v_pattern text;
  v_expected integer;
  v_rhythm jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_kernel_key not in ('household.cleaning','household.groceries') then raise exception 'Kernel is not available through generic model acceptance.' using errcode='22023'; end if;
  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  select max(version) into v_version from atlas.world_kernel_definitions where kernel_key=p_kernel_key and active;
  select * into v_model from atlas.world_kernel_models where kernel_key=p_kernel_key and kernel_version=v_version and model_key=p_model_key and active;
  if v_model.model_key is null then raise exception 'Unknown kernel model.' using errcode='22023'; end if;

  insert into atlas.household_kernel_instances(household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata)
  values(v_household_id,p_kernel_key,v_version,'active',v_model.configuration,now(),jsonb_build_object('source','principal_model_acceptance','selectedModelKey',v_model.model_key,'selectedAt',now(),'calibratedBy',auth.uid()))
  on conflict(household_id,kernel_key) do update set kernel_version=excluded.kernel_version,state='active',configuration=excluded.configuration,calibrated_at=now(),metadata=atlas.household_kernel_instances.metadata||excluded.metadata,updated_at=now()
  returning * into v_instance;

  v_title := case p_kernel_key when 'household.cleaning' then 'Cleaning' when 'household.groceries' then 'Groceries' end;
  v_pattern := nullif(v_model.configuration->>'usualPattern','');
  v_expected := coalesce(nullif(v_model.configuration->>'expectedMinutes','')::integer,45);
  if v_pattern is not null then
    v_rhythm := atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
      'stableKey','kernel:'||p_kernel_key||':general',
      'area',replace(p_kernel_key,'household.',''),
      'title',v_title,
      'cadenceRule',v_pattern,
      'expectedMinutes',v_expected,
      'protectionLevel','protected',
      'floorClass',3,
      'interruptibility','interruptible',
      'principalRequired',true,
      'blocksCapacity',true,
      'reasonForFloor','Ordinary household reality calibrated from a source-controlled Personal Reality Kernel model.',
      'metadata',jsonb_build_object('worldKernelKey',p_kernel_key,'worldKernelVersion',v_version,'selectedModelKey',v_model.model_key,'semanticCadence',true,'clockWindowEstablished',false)
    ));
  end if;

  return jsonb_build_object('ok',true,'kernelKey',p_kernel_key,'selectedModelKey',v_model.model_key,'instance',jsonb_build_object('id',v_instance.id,'configuration',v_instance.configuration,'calibratedAt',v_instance.calibrated_at),'rhythm',v_rhythm);
end;
$$;

create or replace function public.accept_personal_kernel_model_self_api_v1(p_kernel_key text,p_model_key text)
returns jsonb language sql security definer set search_path=pg_catalog as $$
  select atlas.accept_personal_kernel_model_self_api_v1(p_kernel_key,p_model_key);
$$;

revoke all on function public.accept_personal_kernel_model_self_api_v1(text,text) from public,anon;
grant execute on function public.accept_personal_kernel_model_self_api_v1(text,text) to authenticated,service_role;
