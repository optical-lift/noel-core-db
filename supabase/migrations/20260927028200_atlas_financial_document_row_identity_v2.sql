-- Atlas financial document-row identity helper v2
--
-- Historical statements often lack a provider transaction id for every row. When no native
-- durable key exists, an ingestion adapter may identify the observed source row by a stable
-- document locator (for example page/section/source-row anchor). The locator describes where
-- the row exists in the source document; it must not be derived only from mutable merchant text.
--
-- Prefer a native provider transaction/reference id whenever one exists. This helper is the
-- deterministic fallback for document reconstruction.

create or replace function atlas.financial_document_row_key_v2(
  p_statement_key text,
  p_source_row_locator text
)
returns text
language plpgsql
immutable
set search_path=pg_catalog,extensions
as $$
declare
  v_statement_key text:=btrim(coalesce(p_statement_key,''));
  v_locator text:=btrim(coalesce(p_source_row_locator,''));
begin
  if v_statement_key='' or v_locator='' then
    raise exception 'Statement key and stable source row locator are required.' using errcode='22023';
  end if;
  if char_length(v_statement_key)>500 or char_length(v_locator)>1000 then
    raise exception 'Statement key or source row locator is unreasonably long.' using errcode='22023';
  end if;

  return 'document-row:'||encode(
    extensions.digest(convert_to(v_statement_key||E'\n'||v_locator,'utf8'),'sha256'),
    'hex'
  );
end;
$$;

revoke all on function atlas.financial_document_row_key_v2(text,text) from public,anon;
grant execute on function atlas.financial_document_row_key_v2(text,text) to authenticated,service_role;

comment on function atlas.financial_document_row_key_v2(text,text) is
  'Deterministic fallback transaction key for immutable document reconstruction when no native provider transaction id exists. The adapter must supply a stable physical/logical source-row locator rather than relying only on mutable description text.';
