"""Portable synthetic negative tests, plus optional full Isaiah packet check."""
import hashlib, json, os, tempfile, unittest
from pathlib import Path
from verify_private_mark_packet import validate_packet, SOURCE_SHA, SOURCE_DIMS

class TestPrivatePacket(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory()
  self.addCleanup(self.tmp.cleanup)
  self.dir=Path(self.tmp.name)
  self.rows=[
   dict(component_id=1,original_x=518,original_y=436,original_width=17,original_height=26,kind='SINGLE_COMPONENT_SHAPE_CANDIDATE',machine_group='B-018',feature_version='silhouette_hog_pca_v1'),
   dict(component_id=2,original_x=475,original_y=448,original_width=18,original_height=20,kind='FRAGMENT_OR_SHORT_STROKE',machine_group=None,feature_version='silhouette_hog_pca_v1')]
  self.data=''.join(json.dumps(r,sort_keys=True,separators=(',',':'))+'\n' for r in self.rows).encode()
  self.digest=hashlib.sha256(self.data).hexdigest()
  self.manifest=dict(schema='noel_mark_private_component_staging_v1',capture_id=13,
    capture_sha256=SOURCE_SHA,source_width=SOURCE_DIMS[0],source_height=SOURCE_DIMS[1],
    algorithm_key='song_ai_bulk_component_shape_v1',expected_count=2,catalogue_digest=self.digest,
    machine_group_count=1,grouped_component_count=1,ungrouped_component_count=1,
    candidate_kind_counts={'FRAGMENT_OR_SHORT_STROKE':1,'SINGLE_COMPONENT_SHAPE_CANDIDATE':1},
    payload_file='component_rows.ndjson',verified_source_photo_bytes_in_packet=False,
    owner_review_events_in_packet=False,training_authorized=False,admission_authorized=False,
    notice='Synthetic packet, no owner authorization')
  self.write()
 def write(self):
  (self.dir/'component_rows.ndjson').write_bytes(self.data)
  (self.dir/'staging_manifest.json').write_text(json.dumps(self.manifest))
 def test_valid_source_bound_packet(self):
  r=validate_packet(self.dir,self.digest)
  self.assertEqual((r['source_components_verified'],r['machine_visual_groups']),(2,1))
  self.assertFalse(r['owner_authorization_verified'])
 def test_wrong_expected_digest(self):
  with self.assertRaises(ValueError):validate_packet(self.dir,'0'*64)
 def test_wrong_existing_capture_id(self):
  with self.assertRaises(ValueError):validate_packet(self.dir,self.digest,14)
 def test_changed_physical_box_refused(self):
  self.data=self.data.replace(b'"original_x":518',b'"original_x":519')
  self.write()
  with self.assertRaisesRegex(ValueError,'modified'):validate_packet(self.dir,self.digest)
 def test_source_out_of_bounds(self):
  self.rows[0]['original_x']=SOURCE_DIMS[0]-10
  self.data=''.join(json.dumps(r,sort_keys=True,separators=(',',':'))+'\n' for r in self.rows).encode()
  self.digest=hashlib.sha256(self.data).hexdigest()
  self.manifest['catalogue_digest']=self.digest
  self.write()
  with self.assertRaisesRegex(ValueError,'exceeds native'):validate_packet(self.dir,self.digest)
 def test_unexpected_private_pixels_refused(self):
  (self.dir/'private.jpg').write_bytes(b'fake')
  with self.assertRaisesRegex(ValueError,'unexpected files'):validate_packet(self.dir,self.digest)
 def test_claimed_training_authority_refused(self):
  self.manifest['training_authorized']=True
  self.write()
  with self.assertRaisesRegex(ValueError,'Unapproved'):validate_packet(self.dir,self.digest)
 def test_group_census_forgery_refused(self):
  self.manifest['grouped_component_count']=2
  self.write()
  with self.assertRaisesRegex(ValueError,'census'):validate_packet(self.dir,self.digest)
 def test_private_full_isaiah_packet_if_supplied(self):
  d=os.environ.get('SONG_PRIVATE_MARK_PACKET_DIR')
  h=os.environ.get('SONG_PRIVATE_MARK_PACKET_DIGEST')
  if not (d and h):self.skipTest('Optional owner-private full packet not supplied')
  r=validate_packet(Path(d),h)
  self.assertEqual((r['source_components_verified'],r['machine_visual_groups']),(13860,96))

if __name__=='__main__':unittest.main()
