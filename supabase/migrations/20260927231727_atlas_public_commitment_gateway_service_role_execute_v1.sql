revoke all on function atlas.public_commitment_surface_v1(text) from public, anon, authenticated;
revoke all on function atlas.begin_public_commitment_session_v1(text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function atlas.public_commitment_session_v1(text) from public, anon, authenticated;
revoke all on function atlas.set_public_commitment_selection_v1(text,jsonb,text) from public, anon, authenticated;
revoke all on function atlas.submit_public_commitment_session_v1(text,text) from public, anon, authenticated;
revoke all on function atlas.public_commitment_quote_for_selection_v1(uuid,jsonb) from public, anon, authenticated;
revoke all on function atlas.resolve_public_commitment_person_v1(text,text,text,text) from public, anon, authenticated;

grant execute on function atlas.public_commitment_surface_v1(text) to service_role;
grant execute on function atlas.begin_public_commitment_session_v1(text,text,text,text,text,text,text) to service_role;
grant execute on function atlas.public_commitment_session_v1(text) to service_role;
grant execute on function atlas.set_public_commitment_selection_v1(text,jsonb,text) to service_role;
grant execute on function atlas.submit_public_commitment_session_v1(text,text) to service_role;

-- Internal helpers remain callable only by the owner and service role where the public gateway requires them indirectly.
grant execute on function atlas.public_commitment_quote_for_selection_v1(uuid,jsonb) to service_role;
grant execute on function atlas.resolve_public_commitment_person_v1(text,text,text,text) to service_role;