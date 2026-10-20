# Atlas Person Inquiry Public Route Preflight — candidate only

This directory contains the SQL-only, read-only, no-send preflight proposed in PR #1824 under Atlas Option C / issue #1818. Neither of the SQL source files is an executable migration. Generating, validating and protecting a future production release are separately required.

The companion custody recovery (PR #1826) restored only three **already-executed** historical Medical Lab SQL bodies and sealed their exact source provenance; it must not be used to bypass new migration custody or grant a generic `medical_lab_` release prefix. Future Atlas migrations must still be named and released under the existing `atlas_` lane.

The preflight must not infer durable Person identity from an email address, reveal another Ledger's private contact match, equate delivery with consent, send correspondence, or establish a relationship. It requires independent contact/sender authority and recipient verification packets before those effects could be considered.
