# Gate B production-schema-clone validation result

Migration version: `20260913232856`
Candidate SHA: `29b0a11abae7fb1d061ddf3ce86212a811d7a5b7`
Validation run: `221` (`34790384808`)
Result: **passed**

- Candidate-introduced Atlas lint errors: 0
- Baseline production-clone errors: 12
- Candidate-clone errors: 12
- Unchanged pre-existing errors: 12
- Errors resolved by candidate: 0
- Migration postconditions: passed
- Local database advisors: passed

The first validation run (`220`) failed only because the production-schema clone restores schema without production data, so the Gate A `teaching` capability-definition row was absent. The repair seeded that production dependency in the validation fixture only. Gate B migration bytes and behavioral postconditions were not changed.

Production release is not authorized by this validation record.
