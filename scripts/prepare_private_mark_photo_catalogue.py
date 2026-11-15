"""Create a deterministic PRIVATE staging packet for a photographed-mark catalogue.

No DB writes, model training, source image upload, or owner-decision import.
The resulting data packet is private input for a future authorized Noel writer;
not a signed admission receipt or canonical glyph inventory.

Usage:
  python prepare_private_mark_photo_catalogue.py --catalog catalog-data.js \
    --source original.jpg --capture-id 13 --output private-stage/
"""
import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from PIL import Image

KIND = {'SINGLE_COMPONENT_SHAPE_CANDIDATE', 'FRAGMENT_OR_SHORT_STROKE',
        'EDGE_INCOMPLETE', 'POSSIBLY_JOINED_OR_DAMAGE'}
COLUMNS = ['id', 'x', 'y', 'width', 'height', 'kind', 'visualGroup',
           'foregroundPixelArea', 'possibleMerge']


def sha256_file(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_catalogue(path):
    text = Path(path).read_text('utf-8').strip()
    prefix = 'window.SONG_CATALOG='
    if text.startswith(prefix):
        text = text[len(prefix):].rstrip(';').strip()
    if not text.startswith('{'):
        raise ValueError('Only JSON or a single window.SONG_CATALOG JSON assignment accepted')
    return json.loads(text)


def generate(catalog, photo, capture_id, out_dir):
    if not isinstance(capture_id, int) or capture_id <= 0:
        raise ValueError('An existing verified capture_id is required')
    if catalog.get('schema') != 'song_ai_photo_component_catalogue_browser_v1':
        raise ValueError('Unrecognized physical catalogue contract')
    sha = catalog.get('sourceSha256')
    if not isinstance(sha, str) or not re.fullmatch('[a-f0-9]{64}', sha):
        raise ValueError('Original-source SHA is missing')
    if sha256_file(photo) != sha:
        raise ValueError('The original source photograph fingerprint does not match')
    with Image.open(photo) as img:
        w, h = img.size
    if (w, h) != (catalog.get('width'), catalog.get('height')):
        raise ValueError('Original source dimensions mismatch')
    raw = catalog.get('components')
    if not isinstance(raw, list) or not 1 <= len(raw) <= 10_000_000:
        raise ValueError('Invalid source-component population')
    if catalog.get('componentColumns') != COLUMNS:
        raise ValueError('Component field order is not the frozen contract')
    group_defs = catalog.get('groups')
    if not isinstance(group_defs, list):
        raise ValueError('Visual group list missing')
    groups = {g[0]: g for g in group_defs if isinstance(g, list) and len(g) == 3}
    if len(groups) != len(group_defs) or any(not re.fullmatch('[TBW]-[0-9]{3}', key) for key in groups):
        raise ValueError('Invalid or duplicate machine visual groups')
    seen = set()
    records = []
    kinds = Counter()
    group_counts = Counter()
    for row in raw:
        if not isinstance(row, list) or len(row) != 9:
            raise ValueError('Malformed component row')
        cid, x, y, width, height, kind, group, area, merge = row
        if any(type(v) is not int for v in (cid, x, y, width, height, area, merge)):
            raise ValueError('Source fields must be exact integers')
        if cid <= 0 or cid in seen or x < 0 or y < 0 or width < 4 or height < 4:
            raise ValueError('Duplicate component or invalid source box')
        if x + width > w or y + height > h or kind not in KIND or group not in (None, *groups):
            raise ValueError('Component outside verified source or invalid grouping')
        if area < 0 or merge not in (0, 1):
            raise ValueError('Invalid original component physical measurements')
        seen.add(cid)
        kinds[kind] += 1
        if group is not None:
            group_counts[group] += 1
        records.append({'component_id': cid, 'original_x': x, 'original_y': y,
                        'original_width': width, 'original_height': height,
                        'kind': kind, 'machine_group': group,
                        'feature_version': 'silhouette_hog_pca_v1'})
    for key, group in groups.items():
        if group_counts[key] != group[2]:
            raise ValueError('Machine group inventory differs from source declarations')
    records.sort(key=lambda r: r['component_id'])
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=False)
    payload = out / 'component_rows.ndjson'
    with payload.open('w', encoding='utf-8', newline='\n') as f:
        for record in records:
            f.write(json.dumps(record, sort_keys=True, separators=(',', ':')) + '\n')
    digest = sha256_file(payload)
    manifest = {
        'schema': 'noel_mark_private_component_staging_v1',
        'capture_id': capture_id, 'capture_sha256': sha,
        'source_width': w, 'source_height': h,
        'algorithm_key': 'song_ai_bulk_component_shape_v1',
        'expected_count': len(records), 'catalogue_digest': digest,
        'machine_group_count': len(groups), 'grouped_component_count': sum(group_counts.values()),
        'ungrouped_component_count': len(records) - sum(group_counts.values()),
        'candidate_kind_counts': dict(sorted(kinds.items())),
        'payload_file': payload.name, 'verified_source_photo_bytes_in_packet': False,
        'owner_review_events_in_packet': False, 'training_authorized': False,
        'admission_authorized': False,
        'notice': 'Private staging only; server-side owner rights, source capture, digest and original locators must be verified before admission.'
    }
    (out / 'staging_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--catalog', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--capture-id', type=int, required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(generate(read_catalogue(args.catalog), args.source,
                              args.capture_id, args.output), indent=2))
