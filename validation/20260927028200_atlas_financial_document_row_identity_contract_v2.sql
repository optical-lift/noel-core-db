-- Contract validation: deterministic document-row financial identity fallback v2

begin;

do $$
declare
  v_a text;
  v_b text;
  v_c text;
  v_comment text;
begin
  if to_regprocedure('atlas.financial_document_row_key_v2(text,text)') is null then
    raise exception 'Missing financial_document_row_key_v2';
  end if;

  v_a:=atlas.financial_document_row_key_v2('statement-2025-01','page:3/withdrawals/card-1201/row:1');
  v_b:=atlas.financial_document_row_key_v2('statement-2025-01','page:3/withdrawals/card-1201/row:1');
  v_c:=atlas.financial_document_row_key_v2('statement-2025-01','page:3/withdrawals/card-1201/row:2');

  if v_a<>v_b or v_a=v_c or v_a !~ '^document-row:[0-9a-f]{64}$' then
    raise exception 'Document row identity helper must be deterministic, locator-sensitive, and opaque';
  end if;

  select obj_description('atlas.financial_document_row_key_v2(text,text)'::regprocedure,'pg_proc')
  into v_comment;
  if position('native provider transaction id' in lower(coalesce(v_comment,'')))=0
     or position('source-row locator' in lower(coalesce(v_comment,'')))=0 then
    raise exception 'Document row helper must preserve native-id preference and locator semantics in its contract';
  end if;
end;
$$;

rollback;
