#!/usr/bin/env python3
"""HELD PostgREST PGRST121 follow-on; source-only exact-v2 delta, no DB."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parent.parent
OLD=ROOT/"candidates/atlas_uniops_historical_stale_transport_v2/candidate.sql"
NEW=ROOT/"candidates/atlas_uniops_historical_stale_transport_v3/candidate.sql"
V2_BLOB="da3ddafc8f479327df02fbe16e418eb0b094072d"
V3_BLOB="0318ac92492d34adcd1475255304cc21dca449e6"
OLD_MESSAGE='MESSAGE=\'{"code":"40001","message":"Retirement preflight stale; refresh impact"}\''
NEW_MESSAGE='MESSAGE=\'{"code":"40001","message":"Retirement preflight stale; refresh impact","details":null,"hint":null}\''
OLD_DETAIL='DETAIL=\'{"status":409}\''
NEW_DETAIL='DETAIL=\'{"status":409,"headers":{}}\''

class HeldSourceRefusal(AssertionError):
    pass

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode("ascii")+b"\0"+data).hexdigest()

def exact_delta(old,new):
    if not isinstance(old,bytes) or not isinstance(new,bytes):
        raise HeldSourceRefusal("Only pinned ordinary source bytes accepted")
    if git_blob(old)!=V2_BLOB or git_blob(new)!=V3_BLOB:
        raise HeldSourceRefusal("HELD v2 or v3 source identity mismatch")
    oldtext=old.decode("utf-8")
    text=new.decode("utf-8")
    if oldtext.count(OLD_MESSAGE)!=1 or oldtext.count(OLD_DETAIL)!=1:
        raise HeldSourceRefusal("Frozen v2 custom error anchor changed")
    if oldtext.replace(OLD_MESSAGE,NEW_MESSAGE,1).replace(OLD_DETAIL,NEW_DETAIL,1)!=text:
        raise HeldSourceRefusal("Governor modified outside exactly two PGRST JSON literals")
    if text.count("RAISE SQLSTATE 'PGRST'")!=1:
        raise HeldSourceRefusal("Expected exactly one custom stale-token rejection")
    if "USING ERRCODE='40001'" in text:
        raise HeldSourceRefusal("Original serialization SQLSTATE reappeared")
    message=json.loads(NEW_MESSAGE.split("'",2)[1])
    detail=json.loads(NEW_DETAIL.split("'",2)[1])
    if message!={"code":"40001","message":"Retirement preflight stale; refresh impact",
                 "details":None,"hint":None}:
        raise HeldSourceRefusal("Response JSON body diverged from explicit error contract")
    if detail!={"status":409,"headers":{}}:
        raise HeldSourceRefusal("Custom HTTP 409 JSON metadata must include headers object")
    return True

class ExactPGRSTEnvelope(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old=OLD.read_bytes()
        cls.new=NEW.read_bytes()

    def test_exact_two_literal_delta(self):
        self.assertTrue(exact_delta(self.old,self.new))

    def test_any_other_semantic_change_rejected(self):
        for candidate in (
            self.new.replace(b'"status":409',b'"status":200',1),
            self.new.replace(b'"headers":{}',b'"headers":[]',1),
            self.new.replace(b'"code":"40001"',b'"code":"PT409"',1),
            self.new.replace(b'"hint":null',b'"hint":"ignore"',1),
            self.new.replace(b"company_work_native_ledger_owner_self_v1",b"unreviewed",1),
            self.new.replace(b"apply_work_lifecycle_transition_internal_v1",
                             b"unreviewed_transition_writer_v1",1),
            self.new+b"\nGRANT EXECUTE TO anon;",
            self.new[:-1]
        ):
            with self.subTest(size=len(candidate)), self.assertRaises(HeldSourceRefusal):
                exact_delta(self.old,candidate)

if __name__=="__main__":
    unittest.main(verbosity=2)
