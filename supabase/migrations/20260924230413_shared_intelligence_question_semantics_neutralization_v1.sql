-- Remove Elm-specific ownership language and outreach-target object scope from universal Shared Intelligence questions.

update local_intel.question_families
set insufficient_data_policy =
  'Say exactly what is currently established and what must be confirmed. Prefer “They offer riding lessons; current openings still need confirmation” over a false yes/no.',
    updated_at=now()
where question_key='check_availability_now';

update local_intel.question_families
set insufficient_data_policy =
  'If an annual pattern or organizer is known but no current occurrence is established, say the event/program is known but the requested date has not been verified.',
    updated_at=now()
where question_key='find_event';

update local_intel.question_families
set insufficient_data_policy =
  'If provider identity exists but exact capability is not established, say Atlas knows the provider exists but has not verified that exact service/product; offer the best governed contact path rather than guessing.',
    updated_at=now()
where question_key='find_provider';

update local_intel.question_families
set insufficient_data_policy =
  'If only the business category is known, do not convert category into a specific service claim. Return a provider-direct verification path.',
    updated_at=now()
where question_key='find_service';

update local_intel.question_families
set insufficient_data_policy =
  'If the offering is known but a current transaction path is not established, say that explicitly and route to provider-direct verification.',
    updated_at=now()
where question_key='how_to_get_it';

update local_intel.question_families
set primary_object_scopes=array['offering','occurrence','entity']::text[],
    insufficient_data_policy =
      'If the organization is known but no current open opportunity is established, say the organization exists and offer to confirm its current needs or contact path.',
    example_questions=jsonb_build_array(
      'Who needs volunteers?',
      'Where can I sell as a vendor?',
      'Who is accepting donations?',
      'Who is currently open to teaching or collaborating off-site?'
    ),
    updated_at=now()
where question_key='participate_or_contribute';

update local_intel.question_families
set primary_object_scopes=array['entity']::text[],
    updated_at=now()
where question_key='external_space_use';
