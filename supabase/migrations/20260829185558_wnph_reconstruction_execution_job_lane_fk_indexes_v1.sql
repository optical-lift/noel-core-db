create index publication_source_reconstruction_jobs_source_package_idx
  on wnph.publication_source_reconstruction_jobs(source_package_id);

create index publication_source_reconstruction_jobs_target_parent_idx
  on wnph.publication_source_reconstruction_jobs(target_parent_block_id);

do $verify$
declare
  v_job_count integer;
  v_ch2_proposals integer;
  v_ch2_blocks integer;
  v_ch1_paragraphs integer;
begin
  if not exists(
    select 1 from pg_indexes
    where schemaname='wnph' and tablename='publication_source_reconstruction_jobs'
      and indexname='publication_source_reconstruction_jobs_source_package_idx'
  ) or not exists(
    select 1 from pg_indexes
    where schemaname='wnph' and tablename='publication_source_reconstruction_jobs'
      and indexname='publication_source_reconstruction_jobs_target_parent_idx'
  ) then
    raise exception 'WNPH reconstruction job foreign-key index repair did not install both indexes';
  end if;

  select count(*) into v_job_count from wnph.publication_source_reconstruction_jobs;
  if v_job_count<>0 then
    raise exception 'WNPH foreign-key index repair unexpectedly found % reconstruction jobs before execution authorization',v_job_count;
  end if;

  select count(*) into v_ch2_proposals
  from wnph.publication_source_reconstruction_proposals p
  join wnph.publication_source_blocks parent on parent.id=p.target_parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id);

  select count(*) into v_ch2_blocks
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);

  select count(*) into v_ch1_paragraphs
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:1:paragraph-stream'
    and b.block_type='paragraph'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);

  if v_ch2_proposals<>0 or v_ch2_blocks<>0 or v_ch1_paragraphs<>24 then
    raise exception 'WNPH foreign-key index repair crossed reading boundary: ch2 proposals %, ch2 blocks %, ch1 paragraphs %',v_ch2_proposals,v_ch2_blocks,v_ch1_paragraphs;
  end if;
end;
$verify$;