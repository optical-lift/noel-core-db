drop table if exists instrument.v40_witness_scores;
create table instrument.v40_witness_scores as
with totals as (select sum(n)::double precision n from instrument.v40_m0_counts),
marks as (
 select m.codepoint,m.n::double precision n,(m.n::double precision/t.n) pg,ln(m.n::double precision/t.n) m0_logp
 from instrument.v40_m0_counts m cross join totals t
), raw as (
 select w.center_id,w.codepoint true_codepoint,w.holdout,w.skeleton,w.intrinsic,
        m.codepoint,
        m.m0_logp,
        p.log_prior
          + (p.emissions->>('1:'||w.f1))::double precision
          + (p.emissions->>('2:'||w.f2))::double precision
          + (p.emissions->>('3:'||w.f3))::double precision
          + (p.emissions->>('4:'||w.f4))::double precision
          + (p.emissions->>('5:'||w.f5))::double precision
          + (p.emissions->>('6:'||w.f6))::double precision
          + (p.emissions->>('7:'||w.f7))::double precision
          + (p.emissions->>('8:'||w.f8))::double precision
          + (p.emissions->>('9:'||w.f9))::double precision
          + (p.emissions->>('10:'||w.f10))::double precision
          + (p.emissions->>('11:'||w.f11))::double precision
          + (p.emissions->>('12:'||w.f12))::double precision
          + (p.emissions->>('13:'||w.f13))::double precision
          + (p.emissions->>('14:'||w.f14))::double precision as m1_score,
        ln((coalesce(m2.n,0)::double precision + 5.0*m.pg)/(coalesce(t2.n,0)::double precision+5.0)) as m2_logp,
        ln((coalesce(m4.n,0)::double precision + 5.0*m.pg)/(coalesce(t4.n,0)::double precision+5.0)) as m4_logp
 from instrument.v40_witness_centers w
 cross join marks m
 join instrument.v40_m1_params p on p.codepoint=m.codepoint
 left join instrument.v40_m2_counts m2 on m2.intrinsic=w.intrinsic and m2.codepoint=m.codepoint
 left join instrument.v40_m2_totals t2 on t2.intrinsic=w.intrinsic
 left join instrument.v40_m4_counts m4 on m4.skeleton=w.skeleton and m4.codepoint=m.codepoint
 left join instrument.v40_m4_totals t4 on t4.skeleton=w.skeleton
 where w.holdout
), mx as (
 select center_id,max(m1_score) mx from raw group by center_id
), z as (
 select r.center_id,m.mx,sum(exp(r.m1_score-m.mx)) z from raw r join mx m using(center_id) group by r.center_id,m.mx
), norm as (
 select r.*, r.m1_score-(z.mx+ln(z.z)) m1_logp
 from raw r join z using(center_id)
), m3raw as (
 select n.*,0.5*n.m1_logp+0.5*n.m2_logp as m3_score from norm n
), m3mx as (select center_id,max(m3_score) mx from m3raw group by center_id),
m3z as (select r.center_id,m.mx,sum(exp(r.m3_score-m.mx)) z from m3raw r join m3mx m using(center_id) group by r.center_id,m.mx)
select r.center_id,r.true_codepoint,r.skeleton,r.intrinsic,r.codepoint,r.m0_logp,r.m1_logp,r.m2_logp,
       r.m3_score-(z.mx+ln(z.z)) m3_logp,r.m4_logp
from m3raw r join m3z z using(center_id);
create index v40_witness_scores_center_idx on instrument.v40_witness_scores(center_id);
create index v40_witness_scores_true_idx on instrument.v40_witness_scores(true_codepoint,center_id);