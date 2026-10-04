
    create table if not exists instrument.unknown_structure_candidate_packets (
      packet_id bigint generated always as identity primary key,
      packet_key text not null unique,
      structure_candidate_id bigint not null references instrument.structure_candidates(structure_candidate_id) on delete cascade,
      source_run_id bigint not null references instrument.runs(instrument_run_id) on delete cascade,
      packet_stage text not null check(packet_stage in ('blind_member_snapshot','validation_input','semantic_rejoin_input')),
      packet_status text not null default 'materialized' check(packet_status in ('materialized','validated','opened','retired')),
      member_count integer not null,
      packet_hash text not null,
      packet_payload jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create table if not exists instrument.unknown_structure_packet_members (
      packet_id bigint not null references instrument.unknown_structure_candidate_packets(packet_id) on delete cascade,
      member_ordinal integer not null,
      unknown_object_id bigint not null references instrument.unknown_structure_objects(unknown_object_id) on delete cascade,
      source_family text not null,
      object_kind text not null,
      scale_key text not null,
      topology_family text not null,
      topology_signature text not null,
      anonymous_signature text not null,
      source_ref jsonb not null default '{}'::jsonb,
      anonymous_payload jsonb not null default '{}'::jsonb,
      primary key(packet_id,member_ordinal),
      unique(packet_id,unknown_object_id)
    );

    create table if not exists instrument.unknown_structure_validation_checkpoints (
      checkpoint_id bigint generated always as identity primary key,
      checkpoint_key text not null unique,
      structure_candidate_id bigint not null references instrument.structure_candidates(structure_candidate_id) on delete cascade,
      packet_id bigint references instrument.unknown_structure_candidate_packets(packet_id) on delete set null,
      checkpoint_stage text not null,
      checkpoint_status text not null check(checkpoint_status in ('pending','complete','failed','superseded')),
      method_key text not null,
      metrics jsonb not null default '{}'::jsonb,
      result_hash text,
      notes text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create index if not exists unknown_structure_packet_candidate_idx
      on instrument.unknown_structure_candidate_packets(structure_candidate_id,packet_stage);
    create index if not exists unknown_structure_checkpoint_candidate_idx
      on instrument.unknown_structure_validation_checkpoints(structure_candidate_id,checkpoint_stage);

    create or replace function instrument.materialize_unknown_candidate_packet_v1(
      p_candidate_key text,
      p_packet_stage text default 'validation_input',
      p_max_members integer default 500
    )
    returns jsonb
    language plpgsql
    as $function$
    declare
      v_candidate_id bigint;
      v_run_id bigint;
      v_packet_id bigint;
      v_packet_key text;
      v_member_count integer;
      v_packet_hash text;
    begin
      if p_packet_stage not in ('blind_member_snapshot','validation_input','semantic_rejoin_input') then
        raise exception 'Invalid packet stage %',p_packet_stage;
      end if;
      if p_max_members < 1 or p_max_members > 5000 then
        raise exception 'p_max_members must be 1..5000';
      end if;

      select structure_candidate_id,discovery_run_id
      into v_candidate_id,v_run_id
      from instrument.structure_candidates
      where candidate_key=p_candidate_key;

      if v_candidate_id is null then
        raise exception 'Unknown candidate %',p_candidate_key;
      end if;

      v_packet_key := 'USP_'||upper(substr(md5(p_candidate_key||':'||p_packet_stage||':'||p_max_members::text),1,18));

      if exists(select 1 from instrument.unknown_structure_candidate_packets where packet_key=v_packet_key) then
        select packet_id,member_count,packet_hash
        into v_packet_id,v_member_count,v_packet_hash
        from instrument.unknown_structure_candidate_packets
        where packet_key=v_packet_key;

        return jsonb_build_object(
          'packet_id',v_packet_id,'packet_key',v_packet_key,'candidate_key',p_candidate_key,
          'member_count',v_member_count,'packet_hash',v_packet_hash,'status','existing'
        );
      end if;

      create temporary table _usp_members on commit drop as
      select
        row_number() over(order by m.member_ordinal,o.unknown_object_id)::int member_ordinal,
        o.unknown_object_id,o.source_family,o.object_kind,o.scale_key,
        o.topology_family,o.topology_signature,o.anonymous_signature,
        o.source_ref,o.anonymous_payload
      from instrument.unknown_structure_candidate_members m
      join instrument.unknown_structure_objects o on o.unknown_object_id=m.unknown_object_id
      where m.structure_candidate_id=v_candidate_id
      order by m.member_ordinal,o.unknown_object_id
      limit p_max_members;

      select count(*)::int,
             md5(coalesce(string_agg(
               unknown_object_id::text||':'||anonymous_signature||':'||topology_signature,
               '|' order by member_ordinal
             ),'EMPTY'))
      into v_member_count,v_packet_hash
      from _usp_members;

      insert into instrument.unknown_structure_candidate_packets(
        packet_key,structure_candidate_id,source_run_id,packet_stage,packet_status,
        member_count,packet_hash,packet_payload
      )
      values(
        v_packet_key,v_candidate_id,v_run_id,p_packet_stage,'materialized',
        v_member_count,v_packet_hash,
        jsonb_build_object(
          'candidate_key',p_candidate_key,
          'max_members',p_max_members,
          'materialization_rule','frozen candidate membership order; bounded prefix only',
          'semantic_decode',case when p_packet_stage='semantic_rejoin_input' then 'permitted_after_open' else 'closed' end
        )
      )
      returning packet_id into v_packet_id;

      insert into instrument.unknown_structure_packet_members(
        packet_id,member_ordinal,unknown_object_id,source_family,object_kind,scale_key,
        topology_family,topology_signature,anonymous_signature,source_ref,anonymous_payload
      )
      select v_packet_id,member_ordinal,unknown_object_id,source_family,object_kind,scale_key,
             topology_family,topology_signature,anonymous_signature,source_ref,anonymous_payload
      from _usp_members
      order by member_ordinal;

      return jsonb_build_object(
        'packet_id',v_packet_id,'packet_key',v_packet_key,'candidate_key',p_candidate_key,
        'member_count',v_member_count,'packet_hash',v_packet_hash,'status','materialized'
      );
    end
    $function$;
  