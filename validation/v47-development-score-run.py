#!/usr/bin/env python3
"""Execution wrapper for V47 development scoring.

Correction frozen before any V47 continuation result: every motif that can be
selected by the exact-support >=100 longest-suffix rule belongs in the model
vocabulary, even if its *assigned* occurrence count falls below 100 after
longer supported suffixes take precedence.
"""
from __future__ import annotations
import importlib.util
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('v47score',ROOT/'v47-development-score.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def prepare(blocks,posts,support,km,holdmap,asup):
    motifs=sorted(asup.keys(),key=lambda x:(x[0],x[1]))
    mid={motif:i for i,motif in enumerate(motifs)}
    rows=[]
    for bnum,(b,bi,x) in enumerate(blocks):
        q=posts[(b,bi)]
        regions=km.predict(np.sqrt(q))
        v=np.zeros_like(q);v[1:]=q[1:]-q[:-1]
        split='train' if m.stable_bucket(b,bi)>=2 else 'val'
        for t in range(0,len(x)-4):
            motif=m.choose_motif(x,t,support)
            mi=mid.get(motif,-1)
            if motif is not None and mi<0:
                raise AssertionError(f'chosen motif missing from vocabulary: {motif}')
            reg=int(regions[t]);hid=holdmap.get((motif,reg),-1) if motif else -1
            rows.append((b,bi,bnum,t,split,mi,reg,hid,q[t],v[t],x[t+1:t+5].astype(np.int64)))
    return rows,motifs

m.prepare=prepare
m.main()
