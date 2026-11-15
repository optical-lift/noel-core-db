"""Read-only source packet verifier for Noel mark catalogue admission.

Verifies machine source coordinates/census, immutable-catalogue digest, and absence
of sensitive payload content. This does NOT establish owner authorization or
admit a catalogue into a database.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

SOURCE_SHA = '8f64008c1f5310836f0fca8f42f395158641b3052921f92fcb2f213315eea4b0'
SOURCE_DIMS = (29696, 5013)
SCHEMA = 'noel_mark_private_component_staging_v1'
KINDS = {'SINGLE_COMPONENT_SHAPE_CANDIDATE','FRAGMENT_OR_SHORT_STROKE',
         'EDGE_INCOMPLETE','POSSIBLY_JOINED_OR_DAMAGE'}
FIELDS = {'component_id','original_x','original_y','original_width','original_height',
          'kind','machine_group','feature_version'}
HEX = re.compile(r'^[0-9a-f]{64}$')
GROUP = re.compile(r'^[TBW]-[0-9]{3}$')


def validate_packet(folder:Path,expected_digest:str,expected_capture_id:int=13)->dict:
    """Strictly validate independent local files, without DB or network access."""
    folder=Path(folder)
    if not HEX.fullmatch(expected_digest):
        raise ValueError('Expected digest must be a supplied 64-char SHA-256')
    expected={'staging_manifest.json','component_rows.ndjson'}
    allowed=expected|{'README.txt'}
    actual={p.name for p in folder.iterdir()}
    if not expected.issubset(actual) or actual-allowed:
        raise ValueError('Missing or unexpected files in private staging packet')
    manifest=json.loads((folder/'staging_manifest.json').read_text('utf-8'))
    if manifest.get('schema')!=SCHEMA or manifest.get('capture_id')!=expected_capture_id or \
       manifest.get('capture_sha256')!=SOURCE_SHA or \
       (manifest.get('source_width'),manifest.get('source_height'))!=SOURCE_DIMS:
        raise ValueError('Unknown original capture identity or source dimensions')
    if manifest.get('payload_file')!='component_rows.ndjson':
        raise ValueError('Payload path was changed')
    if manifest.get('catalogue_digest')!=expected_digest:
        raise ValueError('Manifest checksum differs from independently approved checksum')
    if manifest.get('verified_source_photo_bytes_in_packet') is not False or \
       manifest.get('owner_review_events_in_packet') is not False or \
       manifest.get('training_authorized') is not False or \
       manifest.get('admission_authorized') is not False:
        raise ValueError('Unapproved evidence or authorization in staging')
    payload=folder/'component_rows.ndjson'
    sha=hashlib.sha256();count=0;last=0;seen=set(); kinds=Counter(); groups=Counter()
    with payload.open('rb') as stream:
        for line in stream:
            sha.update(line)
            if not line.endswith(b'\n') or not line.strip():
                raise ValueError('NDJSON requires exactly one line per component')
            r=json.loads(line)
            if not isinstance(r,dict) or set(r)!=FIELDS:
                raise ValueError('Unexpected source field, including authority or image bytes')
            cid,x,y,w,h=[r[k] for k in ('component_id','original_x','original_y','original_width','original_height')]
            if any(type(v) is not int for v in [cid,x,y,w,h]) or cid<=last or cid in seen:
                raise ValueError('Source component IDs not ordered, unique, positive integers')
            if x<0 or y<0 or w<4 or h<4 or x+w>SOURCE_DIMS[0] or y+h>SOURCE_DIMS[1]:
                raise ValueError('Physical source rectangle exceeds native photograph')
            if r['kind'] not in KINDS or not isinstance(r['feature_version'],str) or \
               not 2<=len(r['feature_version'])<=120:
                raise ValueError('Unrecognized machine-only proposal type or feature version')
            family=r['machine_group']
            if family is not None:
                if not isinstance(family,str) or not GROUP.fullmatch(family):
                    raise ValueError('Machine visual group ID is invalid')
                groups[family]+=1
            count+=1;last=cid;seen.add(cid);kinds[r['kind']]+=1
    digest=sha.hexdigest()
    if digest!=expected_digest:
        raise ValueError('Private source component payload has been modified')
    if manifest.get('expected_count')!=count or not 1<=count<=10_000_000:
        raise ValueError('Machine component source census mismatch')
    if manifest.get('grouped_component_count')!=sum(groups.values()) or \
       manifest.get('ungrouped_component_count')!=count-sum(groups.values()) or \
       manifest.get('machine_group_count')!=len(groups):
        raise ValueError('Machine-group census mismatch')
    if manifest.get('candidate_kind_counts')!=dict(sorted(kinds.items())):
        raise ValueError('Provisional component type census mismatch')
    return {'source_sha256':SOURCE_SHA,'source_dimensions':SOURCE_DIMS,
            'capture_id':expected_capture_id,'source_components_verified':count,
            'machine_visual_groups':len(groups),'grouped_proposals':sum(groups.values()),
            'packet_sha256':digest, 'review_events':0,'source_pixels':0,
            'database_writes':0,'owner_authorization_verified':False}

if __name__=='__main__':
    cli=argparse.ArgumentParser()
    cli.add_argument('--packet-dir',required=True,type=Path)
    cli.add_argument('--expected-digest',required=True)
    cli.add_argument('--capture-id',type=int,default=13)
    a=cli.parse_args()
    print(json.dumps(validate_packet(a.packet_dir,a.expected_digest,a.capture_id),indent=2))
