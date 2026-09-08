#!/usr/bin/env python3
"""V46 equation-equivalent accelerated explicit-duration categorical HSMM fitter.

Execution implementation for the frozen V46 Regime-Conditioned Grammar
Recombination Test. It preserves the exact model family, priors, candidate K,
seeds, EM criterion, train/validation split, and K-selection rule of
validation/v46-fit-regimes.py.

Acceleration only algebraically factors the segment dynamic program and uses
Numba JIT. Before Noel data may be scored, --self-test must pass against a
literal reference implementation on deterministic synthetic blocks.
"""
from __future__ import annotations
import argparse, csv, hashlib, json, math
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple
import numpy as np
try:
    from numba import njit
except Exception as exc:
    raise SystemExit("numba is required for the V46 accelerated execution") from exc

K_CANDIDATES=(4,6,8,12,16)
SEEDS=(46,460,4600)
N_OBS=65
MAX_DURATION=64
MAX_ITERS=200
PATIENCE=10
REL_TOL=1e-6
ALPHA_EMIT=0.5
ALPHA_TRANS=0.5
ALPHA_DUR=0.5
ALPHA_INIT=0.5
NEG_INF=-np.inf

@dataclass
class Block:
    book:str; block_index:int; x:np.ndarray
@dataclass
class Params:
    pi:np.ndarray; A:np.ndarray; B:np.ndarray; D:np.ndarray

def stable_bucket(book:str, block_index:int, seed:int, mod:int=10)->int:
    raw=f"{seed}:{book}:{block_index}".encode()
    h=hashlib.sha256(raw).digest()
    return int.from_bytes(h[:8],"big")%mod

def load_blocks(path:Path)->List[Block]:
    out=[]
    with path.open(newline="",encoding="utf-8") as f:
        for row in csv.DictReader(f):
            xs=np.fromiter((int(v)-1 for v in row["state_sequence"].split(",")),dtype=np.int16)
            if len(xs)!=int(row["n_tokens"]): raise ValueError(f"length mismatch {row['book']}:{row['block_index']}")
            if np.any(xs<0) or np.any(xs>=N_OBS): raise ValueError("state outside 1..65")
            out.append(Block(row["book"],int(row["block_index"]),xs))
    return out

def normalize(v,axis=-1):
    s=v.sum(axis=axis,keepdims=True)
    return v/np.maximum(s,1e-300)

def init_params(k:int,seed:int)->Params:
    rng=np.random.default_rng(seed)
    pi=normalize(rng.gamma(1.0,1.0,size=k))
    A=rng.gamma(1.0,1.0,size=(k,k)); np.fill_diagonal(A,0.0); A=normalize(A,axis=1)
    B=normalize(rng.gamma(1.0,1.0,size=(k,N_OBS)),axis=1)
    base=np.exp(-np.arange(MAX_DURATION)/8.0)
    D=np.vstack([base*rng.lognormal(0,0.15,MAX_DURATION) for _ in range(k)])
    D=normalize(D,axis=1)
    return Params(pi,A,B,D)

@njit(cache=True)
def lse_vec(a):
    m=-np.inf
    for i in range(a.shape[0]):
        if a[i]>m: m=a[i]
    if not np.isfinite(m): return -np.inf
    s=0.0
    for i in range(a.shape[0]): s += math.exp(a[i]-m)
    return m+math.log(s)

@njit(cache=True)
def lse_pair_acc(cur,val):
    if cur==-np.inf: return val
    if val==-np.inf: return cur
    if cur>=val: return cur+math.log1p(math.exp(val-cur))
    return val+math.log1p(math.exp(cur-val))

@njit(cache=True)
def fb_fast(x,pi,A,B,D):
    K=pi.shape[0]; T=x.shape[0]; Dmax=MAX_DURATION if T>=MAX_DURATION else T
    logpi=np.log(np.maximum(pi,1e-300)); logA=np.log(np.maximum(A,1e-300))
    logB=np.log(np.maximum(B,1e-300)); logD=np.log(np.maximum(D,1e-300))
    pref=np.zeros((K,T+1),np.float64)
    for k in range(K):
        z=0.0
        for t in range(T):
            z += logB[k,x[t]]; pref[k,t+1]=z

    ae=np.full((T+1,K),-np.inf,np.float64)
    incoming=np.full((T+1,K),-np.inf,np.float64)
    for t in range(1,T+1):
        md=Dmax if t>=Dmax else t
        for k in range(K):
            acc=-np.inf
            for d in range(1,md+1):
                s=t-d
                seg=logD[k,d-1] + (pref[k,t]-pref[k,s])
                if s==0: val=logpi[k]+seg
                else: val=incoming[s,k]+seg
                acc=lse_pair_acc(acc,val)
            ae[t,k]=acc
        for dest in range(K):
            acc=-np.inf
            for j in range(K): acc=lse_pair_acc(acc,ae[t,j]+logA[j,dest])
            incoming[t,dest]=acc
    ll=lse_vec(ae[T])

    ba=np.full((T+1,K),-np.inf,np.float64); ba[T,:]=0.0
    future=np.full((T,K),-np.inf,np.float64)
    for s in range(T-1,-1,-1):
        md=Dmax if T-s>=Dmax else T-s
        for k in range(K):
            acc=-np.inf
            for d in range(1,md+1):
                e=s+d
                tail=0.0 if e==T else ba[e,k]
                val=logD[k,d-1]+(pref[k,e]-pref[k,s])+tail
                acc=lse_pair_acc(acc,val)
            future[s,k]=acc
        for j in range(K):
            acc=-np.inf
            for k in range(K):
                if k==j: continue
                acc=lse_pair_acc(acc,logA[j,k]+future[s,k])
            ba[s,j]=acc

    init=np.zeros(K); trans=np.zeros((K,K)); dur=np.zeros((K,MAX_DURATION)); diff=np.zeros((K,T+1))
    md=Dmax if T>=Dmax else T
    for k in range(K):
        for d in range(1,md+1):
            e=d; tail=0.0 if e==T else ba[e,k]
            lp=logpi[k]+logD[k,d-1]+(pref[k,e]-pref[k,0])+tail-ll
            w=math.exp(lp) if lp>-745.0 else 0.0
            if w!=0.0:
                init[k]+=w; dur[k,d-1]+=w; diff[k,0]+=w; diff[k,e]-=w

    for s in range(1,T):
        md=Dmax if T-s>=Dmax else T-s
        segsum=np.full(K,-np.inf)
        for k in range(K):
            for d in range(1,md+1):
                e=s+d; tail=0.0 if e==T else ba[e,k]
                segpart=logD[k,d-1]+(pref[k,e]-pref[k,s])+tail
                segsum[k]=lse_pair_acc(segsum[k],segpart)
        for j in range(K):
            if not np.isfinite(ae[s,j]): continue
            for k in range(K):
                if j==k: continue
                lp=ae[s,j]+logA[j,k]+segsum[k]-ll
                w=math.exp(lp) if lp>-745.0 else 0.0
                if w!=0.0: trans[j,k]+=w
        for k in range(K):
            prev=-np.inf
            for j in range(K):
                if j==k: continue
                prev=lse_pair_acc(prev,ae[s,j]+logA[j,k])
            if not np.isfinite(prev): continue
            for d in range(1,md+1):
                e=s+d; tail=0.0 if e==T else ba[e,k]
                lp=prev+logD[k,d-1]+(pref[k,e]-pref[k,s])+tail-ll
                w=math.exp(lp) if lp>-745.0 else 0.0
                if w!=0.0:
                    dur[k,d-1]+=w; diff[k,s]+=w; diff[k,e]-=w

    emit=np.zeros((K,N_OBS))
    for k in range(K):
        occ=0.0
        for t in range(T):
            occ += diff[k,t]
            if occ!=0.0: emit[k,x[t]] += occ
    return ll,init,trans,dur,emit

def e_step(blocks:List[Block],p:Params):
    K=len(p.pi); si=np.zeros(K); st=np.zeros((K,K)); sd=np.zeros((K,MAX_DURATION)); se=np.zeros((K,N_OBS)); ll=0.0
    for b in blocks:
        r=fb_fast(b.x,p.pi,p.A,p.B,p.D); ll+=r[0]; si+=r[1]; st+=r[2]; sd+=r[3]; se+=r[4]
    return ll,si,st,sd,se

def m_step(stats,k):
    _,si,st,sd,se=stats
    pi=normalize(si+ALPHA_INIT)
    A=st+ALPHA_TRANS; np.fill_diagonal(A,0.0); A=normalize(A,axis=1)
    B=normalize(se+ALPHA_EMIT,axis=1); D=normalize(sd+ALPHA_DUR,axis=1)
    return Params(pi,A,B,D)

def score(blocks,p):
    ll=0.0;n=0
    for b in blocks:
        ll += fb_fast(b.x,p.pi,p.A,p.B,p.D)[0]; n += len(b.x)
    return ll,n

def fit(train,k,seed):
    p=init_params(k,seed); best=-np.inf; stale=0; history=[]
    for _ in range(MAX_ITERS):
        stats=e_step(train,p); ll=stats[0]; history.append(ll)
        if np.isfinite(best):
            rel=(ll-best)/max(1.0,abs(best))
            stale=0 if rel>=REL_TOL else stale+1
        best=max(best,ll); p=m_step(stats,k)
        if stale>=PATIENCE: break
    return p,history

def save_params(path,p,meta):
    np.savez_compressed(path,pi=p.pi,A=p.A,B=p.B,D=p.D,meta=json.dumps(meta,sort_keys=True))

def ref_lse(a):
    m=np.max(a)
    if not np.isfinite(m): return -np.inf
    return float(m+np.log(np.exp(a-m).sum()))
def ref_fb(x,p):
    K=len(p.pi);T=len(x);Dmax=min(MAX_DURATION,T)
    logpi=np.log(np.maximum(p.pi,1e-300)); logA=np.log(np.maximum(p.A,1e-300)); logB=np.log(np.maximum(p.B,1e-300)); logD=np.log(np.maximum(p.D,1e-300))
    pref=np.zeros((K,T+1))
    for k in range(K): pref[k,1:]=np.cumsum(logB[k,x])
    ae=np.full((T+1,K),-np.inf)
    for t in range(1,T+1):
        md=min(Dmax,t)
        for k in range(K):
            terms=[]
            for d in range(1,md+1):
                s=t-d; emit=pref[k,t]-pref[k,s]+logD[k,d-1]
                terms.append((logpi[k] if s==0 else ref_lse(ae[s]+logA[:,k]))+emit)
            ae[t,k]=ref_lse(np.asarray(terms))
    ll=ref_lse(ae[T])
    ba=np.full((T+1,K),-np.inf);ba[T,:]=0.0
    for s in range(T-1,-1,-1):
        md=min(Dmax,T-s)
        for j in range(K):
            terms=[]
            for k in range(K):
                if k==j: continue
                for d in range(1,md+1):
                    e=s+d
                    terms.append(logA[j,k]+logD[k,d-1]+pref[k,e]-pref[k,s]+ba[e,k])
            ba[s,j]=ref_lse(np.asarray(terms)) if terms else -np.inf
    init=np.zeros(K);trans=np.zeros((K,K));dur=np.zeros((K,MAX_DURATION));emit=np.zeros((K,N_OBS))
    md=min(Dmax,T)
    for k in range(K):
        for d in range(1,md+1):
            e=d;tail=0.0 if e==T else ba[e,k]
            lp=logpi[k]+logD[k,d-1]+pref[k,e]-pref[k,0]+tail-ll; w=math.exp(lp) if lp>-745 else 0.0
            init[k]+=w;dur[k,d-1]+=w
            if w: np.add.at(emit[k],x[0:e],w)
    for s in range(1,T):
        md=min(Dmax,T-s)
        for j in range(K):
            if not np.isfinite(ae[s,j]): continue
            for k in range(K):
                if j==k: continue
                for d in range(1,md+1):
                    e=s+d;tail=0.0 if e==T else ba[e,k]
                    lp=ae[s,j]+logA[j,k]+logD[k,d-1]+pref[k,e]-pref[k,s]+tail-ll;w=math.exp(lp) if lp>-745 else 0.0
                    if not w: continue
                    trans[j,k]+=w;dur[k,d-1]+=w;np.add.at(emit[k],x[s:e],w)
    return ll,init,trans,dur,emit

def self_test():
    cases=[(4,46,7),(4,460,17),(6,46,23),(8,4400,31)]
    worst=0.0
    for k,seed,T in cases:
        p=init_params(k,seed); rng=np.random.default_rng(seed+999); x=rng.integers(0,N_OBS,size=T,dtype=np.int16)
        r0=ref_fb(x,p); r1=fb_fast(x,p.pi,p.A,p.B,p.D)
        names=("ll","init","trans","dur","emit")
        for name,a,b in zip(names,r0,r1):
            err=abs(a-b) if np.isscalar(a) else float(np.max(np.abs(a-b)))
            worst=max(worst,err)
            tol=2e-9 if name!="emit" else 2e-8
            if err>tol: raise AssertionError(f"equivalence failure k={k} T={T} {name} maxabs={err}")
    print(json.dumps({"self_test":"PASS","max_abs_error":worst,"cases":len(cases)},sort_keys=True))

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv",type=Path,nargs="?");ap.add_argument("--out",type=Path,default=Path("v46_regime_fit"));ap.add_argument("--self-test",action="store_true")
    args=ap.parse_args()
    if args.self_test:
        self_test(); return
    if args.csv is None: raise SystemExit("csv required unless --self-test")
    self_test()
    blocks=load_blocks(args.csv)
    train=[b for b in blocks if stable_bucket(b.book,b.block_index,460046,10)>=2]
    valid=[b for b in blocks if stable_bucket(b.book,b.block_index,460046,10)<2]
    if not train or not valid: raise RuntimeError("deterministic development train/validation split is empty")
    args.out.mkdir(parents=True,exist_ok=True);rows=[]
    for k in K_CANDIDATES:
        for seed in SEEDS:
            p,h=fit(train,k,seed);tr_ll,tr_n=score(train,p);va_ll,va_n=score(valid,p)
            meta={"k":k,"seed":seed,"train_ll":tr_ll,"train_n":tr_n,"valid_ll":va_ll,"valid_n":va_n,"valid_nll_per_token":-va_ll/va_n,"iters":len(h)}
            save_params(args.out/f"k{k}_seed{seed}.npz",p,meta);rows.append(meta);print(json.dumps(meta,sort_keys=True),flush=True)
    byk={k:float(np.mean([r["valid_nll_per_token"] for r in rows if r["k"]==k])) for k in K_CANDIDATES}
    selected=min(byk,key=byk.get)
    summary={"selected_k":selected,"mean_validation_nll_per_token":byk,"rows":rows,"train_blocks":len(train),"valid_blocks":len(valid),"train_tokens":sum(len(b.x) for b in train),"valid_tokens":sum(len(b.x) for b in valid)}
    (args.out/"selection.json").write_text(json.dumps(summary,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"selected_k":selected,"by_k":byk},sort_keys=True))
if __name__=="__main__": main()
