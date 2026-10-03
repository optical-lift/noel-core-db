create table instrument.v46_transfer_cipher_20260907 (
  id integer primary key check (id=1),
  blob bytea not null,
  payload_md5 text not null,
  blocks integer not null,
  tokens bigint not null
);
revoke all on instrument.v46_transfer_cipher_20260907 from public, anon, authenticated;

with s as (
  select t.book,t.block_index,t.rn,coalesce(i.rank,65)::int state_id,
         mod(abs(hashtextextended(t.book||':'||t.block_index::text,46)),10) bucket
  from instrument.v42_token_index t
  left join instrument.v41_target_inventory i on i.target=t.y
  where t.holdout=false
), b as (
  select book,block_index,count(*)::int n_tokens,
         string_agg(substr('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~',state_id,1),'' order by rn) enc
  from s where bucket<7 group by book,block_index
), p as (
  select string_agg(book||'|'||block_index::text||'|'||n_tokens::text||'|'||enc,E'\n' order by book,block_index) payload,
         count(*)::int blocks,sum(n_tokens)::bigint tokens
  from b
)
insert into instrument.v46_transfer_cipher_20260907(id,blob,payload_md5,blocks,tokens)
select 1,
       pgp_sym_encrypt(payload,'O8hFsN9Ef6rv_2DpuECy40PH6gxrWKYb','cipher-algo=aes256,compress-algo=2,compress-level=9'),
       md5(payload),blocks,tokens
from p;