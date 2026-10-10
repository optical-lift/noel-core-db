-- Disposable schema-only clone data. These rows never reach production.
INSERT INTO draft.noel_reality_nodes
(node_id,node_kind,display_name,original_definition,operative_definition,authority_state,authority_basis)
VALUES
('founding-pool-0018','lexical_pool','Eat','To internalize and participate','Atonement happening.','steward_governed','clone test: ratified Eat'),
('founding-pool-0043','lexical_pool','Bless','To confer a promise','Declaring that holiness is applicable or going to happen.','steward_governed','clone test: ratified Bless'),
('founding-pool-0093','lexical_pool','Bread','Bread as received provision','Body-directed atonement','founder_seed','clone test: original Bread'),
('lexeme:H1250','lexical_pool','Grain H1250',NULL,NULL,'indexed_attested','clone test: MT lexical distinction'),
('lexeme:H1715','lexical_pool','Grain H1715',NULL,NULL,'indexed_attested','clone test: MT lexical distinction'),
('reality:healing_holiness_restoration','reality_category','Healing / Holiness / Restoration',NULL,'Governed reality category','steward_governed','clone test: accepted realm');

INSERT INTO draft.noel_reality_aliases(alias_kind,alias_value,node_id)
VALUES
('strongs','H0398','founding-pool-0018'),
('strongs','H1288','founding-pool-0043'),
('strongs','H3899','founding-pool-0093'),
('strongs','H1250','lexeme:H1250'),
('strongs','H1715','lexeme:H1715');

INSERT INTO draft.noel_reality_english_routes(term,node_id,route_basis)
VALUES
('grain','lexeme:H1250','clone test exact lexical route'),
('grain','lexeme:H1715','clone test exact lexical route'),
('bread','founding-pool-0093','clone test founder route'),
('eat','founding-pool-0018','clone test steward route'),
('bless','founding-pool-0043','clone test steward route');

INSERT INTO draft.noel_reality_edges
(edge_id,from_node_id,to_node_id,relation_type,authority_state,authority_basis,propagates_realm)
VALUES
('clone-grain-1250-bread','lexeme:H1250','founding-pool-0093','provision_relation_to','steward_governed','clone test: grain bread',true),
('clone-grain-1715-bread','lexeme:H1715','founding-pool-0093','provision_relation_to','steward_governed','clone test: grain bread',true),
('clone-bread-realm','founding-pool-0093','reality:healing_holiness_restoration','participates_in_reality_category','steward_governed','clone test: founder bread realm',true),
('clone-eat-realm','founding-pool-0018','reality:healing_holiness_restoration','participates_in_reality_category','steward_governed','clone test: eat realm',true),
('clone-bless-realm','founding-pool-0043','reality:healing_holiness_restoration','participates_in_reality_category','steward_governed','clone test: bless realm',true);
