create table if not exists instrument.v39_w0_counts as select mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout group by mark;
create unique index if not exists v39_w0_counts_idx on instrument.v39_w0_counts(mark);

create table if not exists instrument.v39_w1_counts as select intrinsic ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout group by intrinsic,mark;
create index if not exists v39_w1_counts_idx on instrument.v39_w1_counts(ctx,mark);

create table if not exists instrument.v39_w2l_counts as select intrinsic||'||'||left_rcoarse ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout and left_rcoarse is not null group by intrinsic||'||'||left_rcoarse,mark;
create index if not exists v39_w2l_counts_idx on instrument.v39_w2l_counts(ctx,mark);

create table if not exists instrument.v39_w2r_counts as select intrinsic||'||'||right_rcoarse ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout and right_rcoarse is not null group by intrinsic||'||'||right_rcoarse,mark;
create index if not exists v39_w2r_counts_idx on instrument.v39_w2r_counts(ctx,mark);

create table if not exists instrument.v39_w3_counts as select intrinsic||'||'||left_rcoarse||'||'||right_rcoarse ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout and left_rcoarse is not null and right_rcoarse is not null group by intrinsic||'||'||left_rcoarse||'||'||right_rcoarse,mark;
create index if not exists v39_w3_counts_idx on instrument.v39_w3_counts(ctx,mark);

create table if not exists instrument.v39_w4l_counts as select intrinsic||'||'||left_rpair ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout and left_rpair is not null group by intrinsic||'||'||left_rpair,mark;
create index if not exists v39_w4l_counts_idx on instrument.v39_w4l_counts(ctx,mark);

create table if not exists instrument.v39_w4r_counts as select intrinsic||'||'||right_rpair ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout and right_rpair is not null group by intrinsic||'||'||right_rpair,mark;
create index if not exists v39_w4r_counts_idx on instrument.v39_w4r_counts(ctx,mark);

create table if not exists instrument.v39_w6_counts as select skeleton ctx,mark,count(*)::bigint n from instrument.v39_witness_tokens where not holdout group by skeleton,mark;
create index if not exists v39_w6_counts_idx on instrument.v39_w6_counts(ctx,mark);

create table if not exists instrument.v39_w1_totals as select ctx,sum(n)::bigint n from instrument.v39_w1_counts group by ctx; create unique index if not exists v39_w1_totals_idx on instrument.v39_w1_totals(ctx);
create table if not exists instrument.v39_w2l_totals as select ctx,sum(n)::bigint n from instrument.v39_w2l_counts group by ctx; create unique index if not exists v39_w2l_totals_idx on instrument.v39_w2l_totals(ctx);
create table if not exists instrument.v39_w2r_totals as select ctx,sum(n)::bigint n from instrument.v39_w2r_counts group by ctx; create unique index if not exists v39_w2r_totals_idx on instrument.v39_w2r_totals(ctx);
create table if not exists instrument.v39_w3_totals as select ctx,sum(n)::bigint n from instrument.v39_w3_counts group by ctx; create unique index if not exists v39_w3_totals_idx on instrument.v39_w3_totals(ctx);
create table if not exists instrument.v39_w4l_totals as select ctx,sum(n)::bigint n from instrument.v39_w4l_counts group by ctx; create unique index if not exists v39_w4l_totals_idx on instrument.v39_w4l_totals(ctx);
create table if not exists instrument.v39_w4r_totals as select ctx,sum(n)::bigint n from instrument.v39_w4r_counts group by ctx; create unique index if not exists v39_w4r_totals_idx on instrument.v39_w4r_totals(ctx);
create table if not exists instrument.v39_w6_totals as select ctx,sum(n)::bigint n from instrument.v39_w6_counts group by ctx; create unique index if not exists v39_w6_totals_idx on instrument.v39_w6_totals(ctx);