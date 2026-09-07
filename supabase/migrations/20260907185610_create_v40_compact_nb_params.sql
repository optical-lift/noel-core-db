create table if not exists instrument.v40_nb_params as
select target,max(log_prior) log_prior,jsonb_object_agg(feature_no::text||':'||feature_value,log_emission) emissions
from instrument.v40_nb_logprob group by target;
create unique index if not exists v40_nb_params_target_idx on instrument.v40_nb_params(target);