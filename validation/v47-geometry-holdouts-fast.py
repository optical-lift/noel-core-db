#!/usr/bin/env python3
"""Execution wrapper for V47 target-blind geometry.

This does not change V47 mathematics. It replaces only the literal Python
posterior enumerator in v47-geometry-holdouts.py with the Numba-accelerated
`posterior_occ` implementation already used and validated in V46 consensus
scoring. Both implement the same explicit-duration HSMM token occupancy
posterior.
"""
from __future__ import annotations
import importlib.util
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parent

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod

v47=load('v47_geometry_literal', ROOT/'v47-geometry-holdouts.py')
v46=load('v46_consensus_kernel', ROOT/'v46-consensus-cells.py')

def fast_token_posterior(x,p):
    return v46.posterior_occ(
        np.asarray(x,dtype=np.int16),
        np.asarray(p['pi'],dtype=np.float64),
        np.asarray(p['A'],dtype=np.float64),
        np.asarray(p['B'],dtype=np.float64),
        np.asarray(p['D'],dtype=np.float64),
    )

# Mandatory equivalence gate on deterministic short synthetic sequences.
def self_test():
    rng=np.random.default_rng(47)
    for seed,T in [(47,7),(470,11),(4700,17)]:
        rr=np.random.default_rng(seed)
        pi=rr.gamma(1,1,12); pi/=pi.sum()
        A=rr.gamma(1,1,(12,12)); np.fill_diagonal(A,0); A/=A.sum(1,keepdims=True)
        B=rr.gamma(1,1,(12,65)); B/=B.sum(1,keepdims=True)
        D=rr.gamma(1,1,(12,64)); D/=D.sum(1,keepdims=True)
        p={'pi':pi,'A':A,'B':B,'D':D}
        x=rng.integers(0,65,size=T,dtype=np.int16)
        slow=v47.token_posterior(x,p)
        fast=fast_token_posterior(x,p)
        err=float(np.max(np.abs(slow-fast)))
        if err>2e-9:
            raise AssertionError(f'posterior equivalence failure T={T}: {err}')
        print({'T':T,'max_abs_error':err})

self_test()
v47.token_posterior=fast_token_posterior
v47.main()
