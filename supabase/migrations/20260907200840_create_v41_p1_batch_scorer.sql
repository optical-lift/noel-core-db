create or replace function instrument.v41_insert_p1_batch(lo int, hi int)
returns bigint
language sql
security invoker
as $$
with ins as (
 insert into instrument.v41_p1_scores(center_id,true_y,center_skeleton,y,score)
 select w.center_id,w.y,w.center_skeleton,tr.y,
 ln(tr.n::double precision/(select sum(n)::double precision from instrument.v41_target_counts))
 +c1.score+c2.score+c3.score+c4.score+c5.score+c6.score+c7.score+c8.score
 +t1.score+t2.score+t3.score+t4.score+t5.score+t6.score+x.score
 from instrument.v41_train w cross join instrument.v41_target_rank tr
 join instrument.v41_pos_components c1 on c1.comp=1 and c1.y=tr.y and c1.l=w.m4_l and c1.rr=w.m4_r and c1.ff=w.m4_f
 join instrument.v41_pos_components c2 on c2.comp=2 and c2.y=tr.y and c2.l=w.m3_l and c2.rr=w.m3_r and c2.ff=w.m3_f
 join instrument.v41_pos_components c3 on c3.comp=3 and c3.y=tr.y and c3.l=w.m2_l and c3.rr=w.m2_r and c3.ff=w.m2_f
 join instrument.v41_pos_components c4 on c4.comp=4 and c4.y=tr.y and c4.l=w.m1_l and c4.rr=w.m1_r and c4.ff=w.m1_f
 join instrument.v41_pos_components c5 on c5.comp=5 and c5.y=tr.y and c5.l=w.p1_l and c5.rr=w.p1_r and c5.ff=w.p1_f
 join instrument.v41_pos_components c6 on c6.comp=6 and c6.y=tr.y and c6.l=w.p2_l and c6.rr=w.p2_r and c6.ff=w.p2_f
 join instrument.v41_pos_components c7 on c7.comp=7 and c7.y=tr.y and c7.l=w.p3_l and c7.rr=w.p3_r and c7.ff=w.p3_f
 join instrument.v41_pos_components c8 on c8.comp=8 and c8.y=tr.y and c8.l=w.p4_l and c8.rr=w.p4_r and c8.ff=w.p4_f
 join instrument.v41_traj_components t1 on t1.comp=1 and t1.y=tr.y and t1.dl=w.dl_l1 and t1.dr=w.dr_l1
 join instrument.v41_traj_components t2 on t2.comp=2 and t2.y=tr.y and t2.dl=w.dl_l2 and t2.dr=w.dr_l2
 join instrument.v41_traj_components t3 on t3.comp=3 and t3.y=tr.y and t3.dl=w.dl_l3 and t3.dr=w.dr_l3
 join instrument.v41_traj_components t4 on t4.comp=4 and t4.y=tr.y and t4.dl=w.dl_r1 and t4.dr=w.dr_r1
 join instrument.v41_traj_components t5 on t5.comp=5 and t5.y=tr.y and t5.dl=w.dl_r2 and t5.dr=w.dr_r2
 join instrument.v41_traj_components t6 on t6.comp=6 and t6.y=tr.y and t6.dl=w.dl_r3 and t6.dr=w.dr_r3
 join instrument.v41_cross_components x on x.y=tr.y and x.xshared=w.xshared and x.xboundary=w.xboundary
 where w.holdout and tr.r between lo and hi
 returning 1
)
select count(*)::bigint from ins;
$$;