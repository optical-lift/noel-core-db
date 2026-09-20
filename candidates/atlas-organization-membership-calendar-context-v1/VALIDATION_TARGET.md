# Validation target

Issue: #874  
Architecture:
- atlas-present-organization-membership-effectiveness-current-canon-v1
- atlas-organization-membership-calendar-context-current-canon-v1
- atlas-present-membership-effective-time-cutover-current-canon-v1

Promotion rule: generate the migration path with the repository-pinned Supabase CLI, then copy the reviewed candidate SQL byte-for-byte into that generated migration and install the matching clone fixture/postconditions under the generated version.
