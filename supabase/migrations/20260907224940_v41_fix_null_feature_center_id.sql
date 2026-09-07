create or replace function instrument.v41_build_null_features(null_k integer)
returns bigint
language plpgsql
as $function$
declare n bigint;
begin
  delete from instrument.v41_null_features where k=null_k;
  insert into instrument.v41_null_features(
    k,center_id,true_y,center_skeleton,
    m4_l,m4_r,m4_f,m3_l,m3_r,m3_f,m2_l,m2_r,m2_f,m1_l,m1_r,m1_f,
    p1_l,p1_r,p1_f,p2_l,p2_r,p2_f,p3_l,p3_r,p3_f,p4_l,p4_r,p4_f,
    dl_l1,dr_l1,dl_l2,dr_l2,dl_l3,dr_l3,dl_r1,dr_r1,dl_r2,dr_r2,dl_r3,dr_r3,
    xshared,xboundary)
  select null_k,w.center_id,w.y,w.center_skeleton,
    t1.len_bin,least(t1.repeat_excess,2),t1.terminal_final::int,
    t2.len_bin,least(t2.repeat_excess,2),t2.terminal_final::int,
    t3.len_bin,least(t3.repeat_excess,2),t3.terminal_final::int,
    t4.len_bin,least(t4.repeat_excess,2),t4.terminal_final::int,
    t5.len_bin,least(t5.repeat_excess,2),t5.terminal_final::int,
    t6.len_bin,least(t6.repeat_excess,2),t6.terminal_final::int,
    t7.len_bin,least(t7.repeat_excess,2),t7.terminal_final::int,
    t8.len_bin,least(t8.repeat_excess,2),t8.terminal_final::int,
    least(3,greatest(-3,t2.len-t1.len)),least(2,greatest(-2,t2.repeat_excess-t1.repeat_excess)),
    least(3,greatest(-3,t3.len-t2.len)),least(2,greatest(-2,t3.repeat_excess-t2.repeat_excess)),
    least(3,greatest(-3,t4.len-t3.len)),least(2,greatest(-2,t4.repeat_excess-t3.repeat_excess)),
    least(3,greatest(-3,t6.len-t5.len)),least(2,greatest(-2,t6.repeat_excess-t5.repeat_excess)),
    least(3,greatest(-3,t7.len-t6.len)),least(2,greatest(-2,t7.repeat_excess-t6.repeat_excess)),
    least(3,greatest(-3,t8.len-t7.len)),least(2,greatest(-2,t8.repeat_excess-t7.repeat_excess)),
    (select least(3,count(distinct x)) from unnest(t4.chars) x where x=any(t5.chars))::int,
    (t4.chars[array_length(t4.chars,1)]=t5.chars[1])::int
  from instrument.v41_train w
  join instrument.v41_null_permutations p on p.k=null_k
  join instrument.v41_hebrew_tokens t1 on t1.id=w.center_id+p.s1
  join instrument.v41_hebrew_tokens t2 on t2.id=w.center_id+p.s2
  join instrument.v41_hebrew_tokens t3 on t3.id=w.center_id+p.s3
  join instrument.v41_hebrew_tokens t4 on t4.id=w.center_id+p.s4
  join instrument.v41_hebrew_tokens t5 on t5.id=w.center_id+p.s5
  join instrument.v41_hebrew_tokens t6 on t6.id=w.center_id+p.s6
  join instrument.v41_hebrew_tokens t7 on t7.id=w.center_id+p.s7
  join instrument.v41_hebrew_tokens t8 on t8.id=w.center_id+p.s8
  where w.holdout;
  get diagnostics n=row_count;
  return n;
end
$function$;