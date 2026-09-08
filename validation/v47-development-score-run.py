#!/usr/bin/env python3
"""Execution wrapper for V47 development scoring.

Two execution corrections frozen before any accepted V47 continuation result:
1. every motif selected by the exact-support >=100 longest-suffix rule belongs
   in the model vocabulary, even if its assigned count falls below 100 after
   longer supported suffixes take precedence;
2. consensus posteriors remain float64 through target-blind geometry
   reconstruction, exactly matching the frozen V47 geometry stage. Conversion
   to float32 occurs only when predictive tensors are created.
"""
from __future__ import annotations
import importlib.util
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('v47score',ROOT/'v47-development-score.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def consensus_posts(blocks,params):
    refB=params[46][2]
    perms={
        46:np.arange(m.K),
        460:m.align(refB,params[460][2]),
        4600:m.align(refB,params[4600][2]),
    }
    out={}
    for b,bi,x in blocks:
        gs=[]
        for seed in (46,460,4600):
            gs.append(m.v46.posterior_occ(x,*params[seed])[:,perms[seed]])
        q=sum(gs)/3.0
        q=np.clip(q,1e-8,1.0)
        q/=q.sum(1,keepdims=True)
        out[(b,bi)]=q  # keep float64 through K-means / region reconstruction
    return out

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

m.consensus_posts=consensus_posts
m.prepare=prepare
m.main()
