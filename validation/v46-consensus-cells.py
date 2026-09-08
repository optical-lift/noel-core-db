#!/usr/bin/env python3
"""V46 selected-K consensus regimes and pre-outcome cell eligibility.

Uses only the frozen 110-block development corpus and the selected K=12
parameter artifacts. It does not inspect continuation outcomes, replication,
or the original outer holdout.
"""
from __future__ import annotations
import argparse, csv, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
from numba import njit
from scipy.optimize import linear_sum_assignment

K=12
N_OBS=65
MAX_DURATION=64
CONF=0.70
SUPPORT_MIN=100
DECISIVE_MOTIF_MIN=300
CELL_MIN=50
REGIME_MIN=1000
REGIME_MOTIF_BREADTH=20
MIN_CELL_BLOCKS=3
MOTIF_LENGTHS=(6,4,3,2)

class Block:
    __slots__=("book","block_index","x")
    def __init__(self,book,block_index,x): self.book=book; self.block_index=block_index; self.x=x

def stable_bucket(book:str, block_index:int, seed:int, mod:int=10)->int:
    raw=f"{seed}:{book}:{block_index}".encode()
    h=hashlib.sha256(raw).digest()
    return int.from_bytes(h[:8],"big")%mod

def load_blocks(path:Path):
    out=[]
    with path.open(newline="",encoding="utf-8") as f:
        for row in csv.DictReader(f):
            x=np.fromiter((int(v)-1 for v in row["state_sequence"].split(',')),dtype=np.int16)
            assert len(x)==int(row["n_tokens"])
            out.append(Block(row["book"],int(row["block_index"]),x))
    return out

def load_params(path:Path):
    z=np.load(path,allow_pickle=False)
    return tuple(np.asarray(z[k],dtype=np.float64) for k in ("pi","A","B","D"))

@njit(cache=True)
def lse_pair(cur,val):
    if cur==-np.inf: return val
    if val==-np.inf: return cur
    if cur>=val: return cur+math.log1p(math.exp(val-cur))
    return val+math.log1p(math.exp(cur-val))

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
def posterior_occ(x,pi,A,B,D):
    K0=pi.shape[0]; T=x.shape[0]; Dmax=MAX_DURATION if T>=MAX_DURATION else T
    logpi=np.log(np.maximum(pi,1e-300)); logA=np.log(np.maximum(A,1e-300))
    logB=np.log(np.maximum(B,1e-300)); logD=np.log(np.maximum(D,1e-300))
    pref=np.zeros((K0,T+1),np.float64)
    for k in range(K0):
        z=0.0
        for t in range(T): z += logB[k,x[t]]; pref[k,t+1]=z

    ae=np.full((T+1,K0),-np.inf,np.float64)
    incoming=np.full((T+1,K0),-np.inf,np.float64)
    for t in range(1,T+1):
        md=Dmax if t>=Dmax else t
        for k in range(K0):
            acc=-np.inf
            for d in range(1,md+1):
                s=t-d; seg=logD[k,d-1]+pref[k,t]-pref[k,s]
                val=(logpi[k] if s==0 else incoming[s,k])+seg
                acc=lse_pair(acc,val)
            ae[t,k]=acc
        for dest in range(K0):
            acc=-np.inf
            for j in range(K0): acc=lse_pair(acc,ae[t,j]+logA[j,dest])
            incoming[t,dest]=acc
    ll=lse_vec(ae[T])

    ba=np.full((T+1,K0),-np.inf,np.float64); ba[T,:]=0.0
    future=np.full((T,K0),-np.inf,np.float64)
    for s in range(T-1,-1,-1):
        md=Dmax if T-s>=Dmax else T-s
        for k in range(K0):
            acc=-np.inf
            for d in range(1,md+1):
                e=s+d; tail=0.0 if e==T else ba[e,k]
                val=logD[k,d-1]+pref[k,e]-pref[k,s]+tail
                acc=lse_pair(acc,val)
            future[s,k]=acc
        for j in range(K0):
            acc=-np.inf
            for k in range(K0):
                if k==j: continue
                acc=lse_pair(acc,logA[j,k]+future[s,k])
            ba[s,j]=acc

    diff=np.zeros((K0,T+1),np.float64)
    md=Dmax if T>=Dmax else T
    for k in range(K0):
        for d in range(1,md+1):
            e=d; tail=0.0 if e==T else ba[e,k]
            lp=logpi[k]+logD[k,d-1]+pref[k,e]-pref[k,0]+tail-ll
            w=math.exp(lp) if lp>-745 else 0.0
            diff[k,0]+=w; diff[k,e]-=w
    for s in range(1,T):
        md=Dmax if T-s>=Dmax else T-s
        for k in range(K0):
            prev=-np.inf
            for j in range(K0):
                if j==k: continue
                prev=lse_pair(prev,ae[s,j]+logA[j,k])
            if not np.isfinite(prev): continue
            for d in range(1,md+1):
                e=s+d; tail=0.0 if e==T else ba[e,k]
                lp=prev+logD[k,d-1]+pref[k,e]-pref[k,s]+tail-ll
                w=math.exp(lp) if lp>-745 else 0.0
                diff[k,s]+=w; diff[k,e]-=w
    gamma=np.zeros((T,K0),np.float64)
    for k in range(K0):
        occ=0.0
        for t in range(T):
            occ += diff[k,t]; gamma[t,k]=occ
    for t in range(T):
        s=0.0
        for k in range(K0): s+=gamma[t,k]
        if s>0:
            for k in range(K0): gamma[t,k]/=s
    return gamma

def js(p,q):
    p=np.asarray(p,float); q=np.asarray(q,float); m=0.5*(p+q)
    def kl(a,b):
        mask=a>0
        return float(np.sum(a[mask]*np.log(a[mask]/b[mask])))
    return 0.5*kl(p,m)+0.5*kl(q,m)

def align(refB, otherB):
    cost=np.array([[js(refB[i],otherB[j]) for j in range(K)] for i in range(K)])
    rows,cols=linear_sum_assignment(cost)
    assert np.array_equal(rows,np.arange(K))
    # aligned[:, ref_label] = original[:, cols[ref_label]]
    return cols.astype(int), float(cost[rows,cols].sum()), cost

def motif_key(x,t,L):
    if t-L+1<0: return None
    return tuple(int(v)+1 for v in x[t-L+1:t+1])

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--csv',type=Path,required=True)
    ap.add_argument('--seed46',type=Path,required=True)
    ap.add_argument('--seed460',type=Path,required=True)
    ap.add_argument('--seed4600',type=Path,required=True)
    ap.add_argument('--selection',type=Path,required=True)
    ap.add_argument('--out',type=Path,default=Path('v46_consensus_cells'))
    args=ap.parse_args(); args.out.mkdir(parents=True,exist_ok=True)

    sel=json.loads(args.selection.read_text())
    assert int(sel['selected_k'])==K
    blocks=load_blocks(args.csv); assert len(blocks)==110 and sum(len(b.x) for b in blocks)==158503
    params={46:load_params(args.seed46),460:load_params(args.seed460),4600:load_params(args.seed4600)}
    refB=params[46][2]
    p460,c460,_=align(refB,params[460][2]); p4600,c4600,_=align(refB,params[4600][2])
    perms={46:list(range(K)),460:p460.tolist(),4600:p4600.tolist()}

    consensus={}
    high_conf_by_regime=Counter()
    for b in blocks:
        gs=[]
        for seed in (46,460,4600):
            g=posterior_occ(b.x,*params[seed])
            perm=np.asarray(perms[seed],int)
            g=g[:,perm]
            gs.append(g)
        g=sum(gs)/3.0
        g/=np.maximum(g.sum(axis=1,keepdims=True),1e-300)
        confidence=g.max(axis=1); label=g.argmax(axis=1)
        consensus[(b.book,b.block_index)]=(g,confidence,label)
        if stable_bucket(b.book,b.block_index,460046,10)>=2:
            for c,z in zip(confidence,label):
                if c>=CONF: high_conf_by_regime[int(z)+1]+=1

    train=[b for b in blocks if stable_bucket(b.book,b.block_index,460046,10)>=2]
    # exact suffix support on development-training only
    exact={L:Counter() for L in MOTIF_LENGTHS}
    for b in train:
        for t in range(len(b.x)):
            for L in MOTIF_LENGTHS:
                m=motif_key(b.x,t,L)
                if m is not None: exact[L][m]+=1

    assigned=[]
    assigned_support=Counter(); assigned_len=Counter()
    for b in train:
        g,conf,label=consensus[(b.book,b.block_index)]
        for t in range(len(b.x)):
            chosen=None
            for L in MOTIF_LENGTHS:
                m=motif_key(b.x,t,L)
                if m is not None and exact[L][m]>=SUPPORT_MIN:
                    chosen=(L,m); break
            if chosen is None: continue
            assigned_support[chosen]+=1; assigned_len[chosen[0]]+=1
            assigned.append((b.book,b.block_index,t,chosen,float(conf[t]),int(label[t])+1))

    decisive_motifs={m for m,n in assigned_support.items() if n>=DECISIVE_MOTIF_MIN}
    cell_count=Counter(); cell_blocks=defaultdict(set)
    for book,bi,t,m,c,z in assigned:
        if c<CONF or m not in decisive_motifs: continue
        cell_count[(z,m)]+=1; cell_blocks[(z,m)].add((book,bi))

    motif_regimes=defaultdict(set)
    for (z,m),n in cell_count.items():
        if n>=CELL_MIN: motif_regimes[m].add(z)
    cross_motifs={m for m,zs in motif_regimes.items() if len(zs)>=3}
    regime_motifs=defaultdict(set)
    for (z,m),n in cell_count.items():
        if m in cross_motifs and n>=CELL_MIN: regime_motifs[z].add(m)
    qualifying_regimes={z for z,ms in regime_motifs.items() if high_conf_by_regime[z]>=REGIME_MIN and len(ms)>=REGIME_MOTIF_BREADTH}

    cells=[]
    for (z,m),n in cell_count.items():
        if z not in qualifying_regimes or m not in cross_motifs or n<CELL_MIN or len(cell_blocks[(z,m)])<MIN_CELL_BLOCKS: continue
        L,seq=m
        h=hashlib.sha256(f"460046:{z}:{L}:{','.join(map(str,seq))}".encode()).hexdigest()
        cells.append({'regime':z,'motif_length':L,'motif':list(seq),'n':n,'blocks':len(cell_blocks[(z,m)]),'hash':h})
    cells.sort(key=lambda r:r['hash'])
    before=len(cells); cells=cells[:200]

    summary={
      'selected_k':K,
      'candidate_mean_validation_nll_per_token':sel['mean_validation_nll_per_token'],
      'alignment':{'seed46_reference':list(range(1,K+1)),'seed460_original_columns_for_reference_labels_0based':p460.tolist(),'seed4600_original_columns_for_reference_labels_0based':p4600.tolist(),'seed460_total_js_cost':c460,'seed4600_total_js_cost':c4600},
      'development_blocks':len(blocks),'development_tokens':sum(len(b.x) for b in blocks),
      'development_training_blocks':len(train),'development_training_tokens':sum(len(b.x) for b in train),
      'high_confidence_counts_by_regime':dict(sorted(high_conf_by_regime.items())),
      'assigned_occurrences_by_motif_length':dict(sorted(assigned_len.items())),
      'assigned_distinct_motifs_by_length':{L:sum(1 for (l,_),n in assigned_support.items() if l==L) for L in MOTIF_LENGTHS},
      'assigned_motifs_ge300_by_length':{L:sum(1 for (l,_),n in assigned_support.items() if l==L and n>=DECISIVE_MOTIF_MIN) for L in MOTIF_LENGTHS},
      'cross_regime_motifs':len(cross_motifs),'qualifying_regimes':sorted(qualifying_regimes),
      'eligible_cells_before_cap':before,'eligible_cells_after_cap':len(cells),
      'decisive_status':'EVALUABLE' if len(cells)>=20 else 'NOT EVALUABLE'
    }
    (args.out/'summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
    (args.out/'eligible_cells.json').write_text(json.dumps(cells,indent=2,sort_keys=True)+'\n')
    print(json.dumps(summary,sort_keys=True))

if __name__=='__main__': main()
