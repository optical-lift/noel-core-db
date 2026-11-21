"""Synthetic source-custody tests. No protected photograph or founder evidence."""
import hashlib
import json
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from PIL import Image
from prepare_private_mark_photo_catalogue import generate


class CatalogueAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.photo = self.root / 'synthetic.jpg'
        Image.new('RGB', (100, 100), color=(230, 219, 188)).save(self.photo)
        source_hash = hashlib.sha256(self.photo.read_bytes()).hexdigest()
        self.catalogue = {
            'schema': 'song_ai_photo_component_catalogue_browser_v1',
            'sourceSha256': source_hash, 'width': 100, 'height': 100,
            'componentColumns': ['id', 'x', 'y', 'width', 'height', 'kind',
                                 'visualGroup', 'foregroundPixelArea', 'possibleMerge'],
            'groups': [['T-001', 'TALL', 2]],
            'components': [
                [1, 11, 12, 7, 19, 'SINGLE_COMPONENT_SHAPE_CANDIDATE', 'T-001', 40, 0],
                [2, 40, 25, 11, 29, 'SINGLE_COMPONENT_SHAPE_CANDIDATE', 'T-001', 81, 0],
                [3, 60, 41, 13, 17, 'FRAGMENT_OR_SHORT_STROKE', None, 28, 0],
            ],
        }
    def run_staging(self, c):
        return generate(c, self.photo, 24, self.root/'stage')
    def test_exact_private_packet_has_no_image_bytes_or_decisions(self):
        summary = self.run_staging(self.catalogue)
        self.assertEqual(summary['expected_count'], 3)
        self.assertEqual(summary['grouped_component_count'], 2)
        self.assertEqual(summary['ungrouped_component_count'], 1)
        self.assertEqual({p.name for p in (self.root/'stage').iterdir()},
                         {'staging_manifest.json', 'component_rows.ndjson'})
        self.assertFalse(summary['admission_authorized'])
        data = (self.root/'stage'/'component_rows.ndjson').read_text().splitlines()
        self.assertEqual(len(data), 3)
        self.assertEqual(json.loads(data[0])['original_x'], 11)
    def test_wrong_photo_sha_rejected(self):
        a=deepcopy(self.catalogue);a['sourceSha256']='0'*64
        with self.assertRaisesRegex(ValueError, 'fingerprint'):
            self.run_staging(a)
    def test_duplicate_source_id_rejected(self):
        a=deepcopy(self.catalogue);a['components'][1][0]=1
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.run_staging(a)
    def test_out_of_bounds_source_rect_rejected(self):
        a=deepcopy(self.catalogue);a['components'][0][1]=99
        with self.assertRaisesRegex(ValueError, 'outside verified source'):
            self.run_staging(a)
    def test_inconsistent_group_inventory_rejected(self):
        a=deepcopy(self.catalogue);a['groups'][0][2]=3
        with self.assertRaisesRegex(ValueError, 'group inventory'):
            self.run_staging(a)


if __name__ == '__main__':
    unittest.main()
