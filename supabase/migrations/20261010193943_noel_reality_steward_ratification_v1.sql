
CREATE OR REPLACE FUNCTION draft.ratify_noel_reality_definition_v1(
 p_node_id text,p_definition text,p_decision_basis text
)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=''
AS $f$
DECLARE prior text;
BEGIN
 IF nullif(btrim(p_definition),'') IS NULL OR length(btrim(coalesce(p_decision_basis,'')))<5 THEN
  RAISE EXCEPTION 'A real definition and explicit steward decision basis are required';
 END IF;
 SELECT operative_definition INTO prior FROM draft.noel_reality_nodes WHERE node_id=p_node_id AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive pool node: %',p_node_id; END IF;
 UPDATE draft.noel_reality_nodes
 SET operative_definition=p_definition,
     authority_state='steward_governed',
     authority_basis=p_decision_basis,
     updated_at=now()
 WHERE node_id=p_node_id;
 INSERT INTO draft.noel_reality_decisions(subject_kind,subject_id,action,prior_state,resulting_state,decision_basis,extra)
 VALUES('node',p_node_id,'steward_ratification',prior,'steward_governed',p_decision_basis,
 jsonb_build_object('operative_definition',p_definition));
 RETURN p_node_id;
END;
$f$;
REVOKE ALL ON FUNCTION draft.ratify_noel_reality_definition_v1(text,text,text)
 FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION draft.ratify_noel_reality_edge_v1(
 p_from_node_id text,p_relation_type text,p_to_node_id text,
 p_decision_basis text,p_inherits_realm boolean DEFAULT false,p_scope_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=''
AS $f$
DECLARE edge_key text; prior text;
BEGIN
 IF nullif(btrim(p_relation_type),'') IS NULL OR length(btrim(coalesce(p_decision_basis,'')))<5 THEN
  RAISE EXCEPTION 'A typed relationship and explicit steward decision basis are required';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM draft.noel_reality_nodes WHERE node_id=p_from_node_id AND is_active)
 OR NOT EXISTS (SELECT 1 FROM draft.noel_reality_nodes WHERE node_id=p_to_node_id AND is_active)
 THEN RAISE EXCEPTION 'Both linked pool nodes must already exist and be active'; END IF;
 IF p_from_node_id=p_to_node_id THEN RAISE EXCEPTION 'Self-edge is not allowed'; END IF;
 edge_key:='steward-edge:'||md5(p_from_node_id||'|'||p_relation_type||'|'||p_to_node_id);
 SELECT authority_state INTO prior FROM draft.noel_reality_edges WHERE edge_id=edge_key;
 INSERT INTO draft.noel_reality_edges
 (edge_id,from_node_id,to_node_id,relation_type,authority_state,authority_basis,propagates_realm,scope_note)
 VALUES(edge_key,p_from_node_id,p_to_node_id,p_relation_type,'steward_governed',
        p_decision_basis,coalesce(p_inherits_realm,false),p_scope_note)
 ON CONFLICT(edge_id) DO UPDATE SET
 authority_state='steward_governed',
 authority_basis=EXCLUDED.authority_basis,
 propagates_realm=EXCLUDED.propagates_realm,
 scope_note=EXCLUDED.scope_note,
 is_active=true;
 INSERT INTO draft.noel_reality_decisions
 (subject_kind,subject_id,action,prior_state,resulting_state,decision_basis,extra)
 VALUES('edge',edge_key,'steward_ratification',prior,'steward_governed',p_decision_basis,
 jsonb_build_object('from',p_from_node_id,'relation',p_relation_type,
 'to',p_to_node_id,'inherits_realm',coalesce(p_inherits_realm,false)));
 RETURN edge_key;
END;
$f$;
REVOKE ALL ON FUNCTION draft.ratify_noel_reality_edge_v1(text,text,text,text,boolean,text)
 FROM PUBLIC, anon, authenticated;
