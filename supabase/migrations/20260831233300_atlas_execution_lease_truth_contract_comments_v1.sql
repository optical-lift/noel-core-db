BEGIN;

comment on function atlas.grant_execution_lease_v1(text,text,text,uuid,uuid,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,jsonb,text,text,uuid,uuid,boolean,jsonb) is
  'Neutral execution-authority boundary. A caller must supply an authorized domain warrant; identical grants are idempotent; an existing lease cannot be rewritten by later planner output.';

comment on function atlas.transition_execution_lease_v1(uuid,text,text,text,text,uuid,uuid,jsonb,jsonb,timestamptz) is
  'Only supported state-transition path for an execution lease. Every interruption, resume, completion, withdrawal, or expiry is append-only evidence.';

comment on function atlas.execution_lease_reconciliation_proposal_v1(text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb) is
  'Advisory comparison only. Returns add/retain/withdraw proposals between planner candidates and current nonterminal leases; never mutates lease authority.';

COMMIT;
