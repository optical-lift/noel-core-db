-- Canonical source writes must pass through the admission membranes.
-- service_role may read the source tables for governed adapters, but direct INSERT
-- is not part of the admitted contract.

revoke insert on table reality.resource_observations from service_role;
revoke insert on table atlas.organization_responsibility_resource_applicability from service_role;

grant select on table reality.resource_observations to service_role;
grant select on table atlas.organization_responsibility_resource_applicability to service_role;
