#!/usr/bin/env python3
"""V46 explicit-duration categorical HSMM fitter.

Frozen research implementation for the V46 Regime-Conditioned Grammar
Recombination Test. This script fits only the development partition and is not
permitted to inspect internal replication or the original outer holdout during
K selection.

Input CSV columns:
  book, block_index, n_tokens, state_sequence
where state_sequence is comma-separated integer ids 1..65.

Model:
  - categorical emissions over 65 observed structural states
  - explicit categorical duration distribution over d=1..64
  - regime transition matrix with self-transition disallowed at segment
    boundaries (duration carries persistence)
  - K in {4,6,8,12,16}
  - seeds {46,460,4600}
  - EM maximum 200 iterations
  - early stop after 10 iterations without >=1e-6 relative likelihood gain

Development validation is deterministic by preserved block id. Within the
preregistered development blocks, hash(book:block_index, seed=460046) assigns
20% of blocks to validation and 80% to regime training. This implementation
choice is frozen here before any V46 regime-model scoring.

No semantic fields are read.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import numpy as np

K_CANDIDATES = (4, 6, 8, 12, 16)
SEEDS = (46, 460, 4600)
N_OBS = 65
MAX_DURATION = 64
MAX_ITERS = 200
PATIENCE = 10
REL_TOL = 1e-6
ALPHA_EMIT = 0.5
ALPHA_TRANS = 0.5
ALPHA_DUR = 0.5
ALPHA_INIT = 0.5


def stable_bucket(book: str, block_index: int, seed: int, mod: int = 10) -> int:
    raw = f"{seed}:{book}:{block_index}".encode("utf-8")
    h = hashlib.sha256(raw).digest()
    return int.from_bytes(h[:8], "big") % mod


@dataclass
class Block:
    book: str
    block_index: int
    x: np.ndarray


def load_blocks(path: Path) -> List[Block]:
    out: List[Block] = []
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            xs = np.fromiter((int(v)-1 for v in row["state_sequence"].split(",")), dtype=np.int16)
            if len(xs) != int(row["n_tokens"]):
                raise ValueError(f"length mismatch for {row['book']}:{row['block_index']}")
            if np.any(xs < 0) or np.any(xs >= N_OBS):
                raise ValueError("state id outside 1..65")
            out.append(Block(row["book"], int(row["block_index"]), xs))
    return out


def logsumexp(a: np.ndarray) -> float:
    m = np.max(a)
    if not np.isfinite(m):
        return -np.inf
    return float(m + np.log(np.exp(a-m).sum()))


@dataclass
class Params:
    pi: np.ndarray          # K
    A: np.ndarray           # K,K boundary transitions; diagonal zero
    B: np.ndarray           # K,65 emissions
    D: np.ndarray           # K,64 durations 1..64


def normalize(v: np.ndarray, axis: int = -1) -> np.ndarray:
    s = v.sum(axis=axis, keepdims=True)
    return v / np.maximum(s, 1e-300)


def init_params(k: int, seed: int) -> Params:
    rng = np.random.default_rng(seed)
    pi = normalize(rng.gamma(1.0, 1.0, size=k))
    A = rng.gamma(1.0, 1.0, size=(k,k))
    np.fill_diagonal(A, 0.0)
    A = normalize(A, axis=1)
    B = normalize(rng.gamma(1.0, 1.0, size=(k,N_OBS)), axis=1)
    # Initialize durations broadly, favoring short-to-moderate segments without
    # fixing a geometric form.
    base = np.exp(-np.arange(MAX_DURATION) / 8.0)
    D = np.vstack([base * rng.lognormal(0,0.15,MAX_DURATION) for _ in range(k)])
    D = normalize(D, axis=1)
    return Params(pi,A,B,D)


def emission_prefix(x: np.ndarray, logB: np.ndarray) -> np.ndarray:
    # pref[k,t] = log emission sum for x[:t]
    K = logB.shape[0]
    T = len(x)
    pref = np.zeros((K,T+1), dtype=np.float64)
    for k in range(K):
        pref[k,1:] = np.cumsum(logB[k,x])
    return pref


def seg_emit(pref: np.ndarray, k: int, start: int, end: int) -> float:
    return float(pref[k,end] - pref[k,start])


def forward_backward_block(x: np.ndarray, p: Params):
    """Exact segment-level HSMM forward/backward for one block.

    Returns loglik and sufficient-statistic expectations.
    Complexity O(T*K*K*Dmax); intended for research runner, not SQL.
    """
    K = len(p.pi); T = len(x); Dmax = min(MAX_DURATION,T)
    logpi=np.log(np.maximum(p.pi,1e-300)); logA=np.log(np.maximum(p.A,1e-300))
    logB=np.log(np.maximum(p.B,1e-300)); logD=np.log(np.maximum(p.D,1e-300))
    pref=emission_prefix(x,logB)

    # alpha_end[t,k]: log prob observations 0..t-1 with segment k ending at t.
    ae=np.full((T+1,K),-np.inf)
    for t in range(1,T+1):
        md=min(Dmax,t)
        for k in range(K):
            terms=[]
            for d in range(1,md+1):
                s=t-d
                emit=seg_emit(pref,k,s,t)+logD[k,d-1]
                if s==0:
                    terms.append(logpi[k]+emit)
                else:
                    prev=ae[s]+logA[:,k]
                    terms.append(logsumexp(prev)+emit)
            ae[t,k]=logsumexp(np.asarray(terms))
    ll=logsumexp(ae[T])

    # beta_after[s,j]: log prob x[s:] given previous segment state j ended at s.
    ba=np.full((T+1,K),-np.inf)
    ba[T,:]=0.0
    for s in range(T-1,-1,-1):
        md=min(Dmax,T-s)
        for j in range(K):
            terms=[]
            for k in range(K):
                if k==j: continue
                for d in range(1,md+1):
                    e=s+d
                    terms.append(logA[j,k]+logD[k,d-1]+seg_emit(pref,k,s,e)+ba[e,k])
            ba[s,j]=logsumexp(np.asarray(terms)) if terms else -np.inf

    init=np.zeros(K); trans=np.zeros((K,K)); dur=np.zeros((K,MAX_DURATION)); emit=np.zeros((K,N_OBS))

    # Initial segments.
    md=min(Dmax,T)
    for k in range(K):
        for d in range(1,md+1):
            e=d
            tail=0.0 if e==T else ba[e,k]
            lp=logpi[k]+logD[k,d-1]+seg_emit(pref,k,0,e)+tail-ll
            w=math.exp(lp) if lp>-745 else 0.0
            init[k]+=w; dur[k,d-1]+=w
            if w:
                np.add.at(emit[k],x[0:e],w)

    # Noninitial segments, enumerated by previous boundary state.
    for s in range(1,T):
        md=min(Dmax,T-s)
        for j in range(K):
            if not np.isfinite(ae[s,j]): continue
            for k in range(K):
                if j==k: continue
                for d in range(1,md+1):
                    e=s+d
                    tail=0.0 if e==T else ba[e,k]
                    lp=ae[s,j]+logA[j,k]+logD[k,d-1]+seg_emit(pref,k,s,e)+tail-ll
                    w=math.exp(lp) if lp>-745 else 0.0
                    if not w: continue
                    trans[j,k]+=w; dur[k,d-1]+=w
                    np.add.at(emit[k],x[s:e],w)

    return ll, init, trans, dur, emit


def e_step(blocks: List[Block], p: Params):
    K=len(p.pi)
    si=np.zeros(K); st=np.zeros((K,K)); sd=np.zeros((K,MAX_DURATION)); se=np.zeros((K,N_OBS)); ll=0.0
    for b in blocks:
        r=forward_backward_block(b.x,p)
        ll += r[0]; si += r[1]; st += r[2]; sd += r[3]; se += r[4]
    return ll,si,st,sd,se


def m_step(stats, k:int) -> Params:
    _,si,st,sd,se=stats
    pi=normalize(si+ALPHA_INIT)
    A=st+ALPHA_TRANS
    np.fill_diagonal(A,0.0)
    A=normalize(A,axis=1)
    B=normalize(se+ALPHA_EMIT,axis=1)
    D=normalize(sd+ALPHA_DUR,axis=1)
    return Params(pi,A,B,D)


def score(blocks: List[Block], p: Params) -> Tuple[float,int]:
    ll=0.0; n=0
    for b in blocks:
        ll += forward_backward_block(b.x,p)[0]
        n += len(b.x)
    return ll,n


def fit(train: List[Block], k:int, seed:int):
    p=init_params(k,seed)
    best=-np.inf; stale=0; history=[]
    for it in range(MAX_ITERS):
        stats=e_step(train,p)
        ll=stats[0]; history.append(ll)
        if np.isfinite(best):
            rel=(ll-best)/max(1.0,abs(best))
            if rel >= REL_TOL:
                stale=0
            else:
                stale += 1
        best=max(best,ll)
        p=m_step(stats,k)
        if stale>=PATIENCE:
            break
    return p,history


def save_params(path: Path,p:Params,meta:dict):
    np.savez_compressed(path,pi=p.pi,A=p.A,B=p.B,D=p.D,meta=json.dumps(meta,sort_keys=True))


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("csv",type=Path)
    ap.add_argument("--out",type=Path,default=Path("v46_regime_fit"))
    args=ap.parse_args()
    blocks=load_blocks(args.csv)
    train=[b for b in blocks if stable_bucket(b.book,b.block_index,460046,10)>=2]
    valid=[b for b in blocks if stable_bucket(b.book,b.block_index,460046,10)<2]
    if not train or not valid:
        raise RuntimeError("deterministic development train/validation split is empty")
    args.out.mkdir(parents=True,exist_ok=True)

    rows=[]
    for k in K_CANDIDATES:
        for seed in SEEDS:
            p,h=fit(train,k,seed)
            tr_ll,tr_n=score(train,p)
            va_ll,va_n=score(valid,p)
            meta={"k":k,"seed":seed,"train_ll":tr_ll,"train_n":tr_n,"valid_ll":va_ll,"valid_n":va_n,"valid_nll_per_token":-va_ll/va_n,"iters":len(h)}
            save_params(args.out/f"k{k}_seed{seed}.npz",p,meta)
            rows.append(meta)
            print(json.dumps(meta,sort_keys=True),flush=True)

    # K selection uses mean validation NLL/token across the three frozen seeds.
    byk={}
    for k in K_CANDIDATES:
        rr=[r for r in rows if r["k"]==k]
        byk[k]=float(np.mean([r["valid_nll_per_token"] for r in rr]))
    selected=min(byk,key=byk.get)
    summary={"selected_k":selected,"mean_validation_nll_per_token":byk,"rows":rows,
             "train_blocks":len(train),"valid_blocks":len(valid),
             "train_tokens":sum(len(b.x) for b in train),"valid_tokens":sum(len(b.x) for b in valid)}
    (args.out/"selection.json").write_text(json.dumps(summary,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps({"selected_k":selected,"by_k":byk},sort_keys=True))

if __name__=="__main__":
    main()
