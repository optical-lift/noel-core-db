drop table if exists instrument.v41_p1_scores;
create table instrument.v41_p1_scores(center_id bigint not null,true_y text not null,center_skeleton text not null,y text not null,score double precision not null);
create index v41_p1_scores_center_idx on instrument.v41_p1_scores(center_id);