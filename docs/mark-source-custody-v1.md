# Mark source-byte custody v1

`Mark Source Custody Acquisition` is an owner-triggered GitHub Actions lane for converting an already-admitted `registered_remote` Mark capture into reproducible byte-custody evidence without silently treating a web rendition as verified bytes.

The issue request supplies exactly three existing anonymous capture keys and HTTPS source URLs. The workflow permits only the currently approved institutional hosts, downloads with redirect and retry controls, records response headers and effective URLs, calculates SHA-256, byte length, raster dimensions, image format and MIME type, prints a machine-readable manifest to the job log, and uploads the exact downloaded files plus manifest as a 30-day Actions artifact.

The workflow does not write to production. Production capture status is advanced only after the resulting manifest is independently read and reconciled against the already-admitted capture keys.
