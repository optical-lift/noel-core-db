#!/usr/bin/env python3
"""V47 target-blind posterior geometry and motif-region holdout construction.

Consumes:
- V46 development CSV (110 blocks)
- selected K=12 seed parameter artifacts

Produces only target-blind geometry and holdout identities/counts. No continuation
outcomes or predictive model scoring are accessed in this stage.
"""
from __future__ import annotations
import argparse,csv,hashlib,json,math
from pathlib import Path
from collections import Counter,defaultdict
import numpy as np
from scipy.optimize import linear_sum_assignment
from sklearn.cluster import KMeans

N_OBS=65; K=12; MAX_DURATION=64
MOTIF_LENGTHS=(6,4,3,2)
MIN_MOTIF_SUPPORT=100
PRIMARY_MOTIF_SUPPORT=300
REGIONS=12
REGION_MIN=30
OUTSIDE_MIN=300
OUTSIDE_REGIONS_MIN=3
BLOCKS_MIN=3
CAP=200


def stable_bucket(book,block_index,seed=460046,mod=10):
    raw=f"{seed}:{book}:{block_index}".encode(); h=hashlib.sha256(raw).digest()
    return int.from_bytes(h[:8],"big")%mod

def load_blocks(path):
    out=[]
    with open(path,newline='',encoding='utf-8') as f:
        for r in csv.DictReader(f):
            x=np.array([int(v)-1 for v in r['state_sequence'].split(',')],dtype=np.int16)
            out.append((r['book'],int(r['block_index']),x))
    return out

def load_npz(path):
    z=np.load(path); return {k:z[k] for k in ('pi','A','B','D')}

def js(p,q):
    p=np.asarray(p,float);q=np.asarray(q,float);m=.5*(p+q)
    def kl(a,b):
        mask=a>0
        return float(np.sum(a[mask]*np.log(a[mask]/np.maximum(b[mask],1e-300))))
    return .5*kl(p,m)+.5*kl(q,m)

def align_to_ref(ref,other):
    C=np.zeros((K,K))
    for i in range(K):
        for j in range(K): C[i,j]=js(ref['B'][i],other['B'][j])
    ri,cj=linear_sum_assignment(C)
    perm=np.empty(K,dtype=int)
    for i,j in zip(ri,cj): perm[i]=j
    aligned={}
    aligned['pi']=other['pi'][perm]
    aligned['B']=other['B'][perm]
    aligned['D']=other['D'][perm]
    aligned['A']=other['A'][perm][:,perm]
    return aligned,perm,float(C[ri,cj].sum())

def lse(vals):
    a=np.asarray(vals,float);m=np.max(a)
    if not np.isfinite(m): return -np.inf
    return float(m+np.log(np.exp(a-m).sum()))

def token_posterior(x,p):
    """Exact explicit-duration HSMM token occupancy posterior via segment enumeration."""
    T=len(x);Dmax=min(MAX_DURATION,T)
    logpi=np.log(np.maximum(p['pi'],1e-300));logA=np.log(np.maximum(p['A'],1e-300))
    logB=np.log(np.maximum(p['B'],1e-300));logD=np.log(np.maximum(p['D'],1e-300))
    pref=np.zeros((K,T+1))
    for k in range(K): pref[k,1:]=np.cumsum(logB[k,x])
    ae=np.full((T+1,K),-np.inf)
    incoming=np.full((T+1,K),-np.inf)
    for t in range(1,T+1):
        for k in range(K):
            terms=[]
            for d in range(1,min(Dmax,t)+1):
                s=t-d; seg=logD[k,d-1]+pref[k,t]-pref[k,s]
                terms.append((logpi[k] if s==0 else incoming[s,k])+seg)
            ae[t,k]=lse(terms)
        for dest in range(K): incoming[t,dest]=lse(ae[t]+logA[:,dest])
    ll=lse(ae[T])
    ba=np.full((T+1,K),-np.inf);ba[T,:]=0.0
    for s in range(T-1,-1,-1):
        future=np.full(K,-np.inf)
        for k in range(K):
            terms=[]
            for d in range(1,min(Dmax,T-s)+1):
                e=s+d; tail=0.0 if e==T else ba[e,k]
                terms.append(logD[k,d-1]+pref[k,e]-pref[k,s]+tail)
            future[k]=lse(terms)
        for j in range(K):
            ba[s,j]=lse([logA[j,k]+future[k] for k in range(K) if k!=j])
    diff=np.zeros((K,T+1))
    for k in range(K):
        for d in range(1,min(Dmax,T)+1):
            e=d;tail=0.0 if e==T else ba[e,k]
            lp=logpi[k]+logD[k,d-1]+pref[k,e]-pref[k,0]+tail-ll
            w=math.exp(lp) if lp>-745 else 0.0
            diff[k,0]+=w;diff[k,e]-=w
    for s in range(1,T):
        for k in range(K):
            prev=lse([ae[s,j]+logA[j,k] for j in range(K) if j!=k])
            if not np.isfinite(prev): continue
            for d in range(1,min(Dmax,T-s)+1):
                e=s+d;tail=0.0 if e==T else ba[e,k]
                lp=prev+logD[k,d-1]+pref[k,e]-pref[k,s]+tail-ll
                w=math.exp(lp) if lp>-745 else 0.0
                diff[k,s]+=w;diff[k,e]-=w
    post=np.zeros((T,K))
    for k in range(K): post[:,k]=np.cumsum(diff[k,:T])
    post=np.maximum(post,0);post/=np.maximum(post.sum(1,keepdims=True),1e-300)
    return post

def motif_assignments(blocks):
    # support exact suffixes on development-training only
    counts={L:Counter() for L in MOTIF_LENGTHS}
    train=[]
    for book,bi,x in blocks:
        if stable_bucket(book,bi)>=2:
            train.append((book,bi,x))
            for L in MOTIF_LENGTHS:
                for t in range(L-1,len(x)):
                    counts[L][tuple((x[t-L+1:t+1]+1).tolist())]+=1
    assigned=[]
    for book,bi,x in train:
        for t in range(1,len(x)):
            m=None
            for L in MOTIF_LENGTHS:
                if t-L+1<0: continue
                key=tuple((x[t-L+1:t+1]+1).tolist())
                if counts[L][key]>=MIN_MOTIF_SUPPORT:
                    m=(L,key);break
            if m is not None: assigned.append((book,bi,t,m[0],m[1]))
    assigned_support=Counter((L,key) for _,_,_,L,key in assigned)
    return assigned,assigned_support

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('csv');ap.add_argument('--p46',required=True);ap.add_argument('--p460',required=True);ap.add_argument('--p4600',required=True);ap.add_argument('--out',required=True)
    a=ap.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    blocks=load_blocks(a.csv)
    p46=load_npz(a.p46);p460=load_npz(a.p460);p4600=load_npz(a.p4600)
    p460,perm460,cost460=align_to_ref(p46,p460);p4600,perm4600,cost4600=align_to_ref(p46,p4600)
    posts={}; allq=[]; rows=[]
    for book,bi,x in blocks:
        q=(token_posterior(x,p46)+token_posterior(x,p460)+token_posterior(x,p4600))/3.0
        q=np.clip(q,1e-8,1);q/=q.sum(1,keepdims=True);posts[(book,bi)]=q
    assigned,support=motif_assignments(blocks)
    eligible_ids={m for m,n in support.items() if n>=PRIMARY_MOTIF_SUPPORT}
    geom=[];meta=[]
    for book,bi,t,L,key in assigned:
        if (L,key) not in eligible_ids: continue
        q=posts[(book,bi)][t]
        geom.append(np.sqrt(q));meta.append((book,bi,t,L,key,q))
    X=np.vstack(geom)
    km=KMeans(n_clusters=REGIONS,random_state=47,n_init=20,algorithm='lloyd').fit(X)
    region_counts=Counter(km.labels_.tolist())
    by_m=defaultdict(list)
    for lab,m in zip(km.labels_,meta): by_m[(m[3],m[4])].append((int(lab),m[0],m[1],m[2]))
    selected=[]
    occupancy={}
    for motif,occ in by_m.items():
        c=Counter(r for r,_,_,_ in occ); occupancy[f"{motif[0]}:{','.join(map(str,motif[1]))}"]=dict(sorted(c.items()))
        candidates=[]
        for r,n in c.items():
            outside=sum(c.values())-n; outside_regs=sum(1 for rr,nn in c.items() if rr!=r and nn>0)
            blocks_n=len({(b,bi) for rr,b,bi,t in occ if rr==r})
            if n>=REGION_MIN and outside>=OUTSIDE_MIN and outside_regs>=OUTSIDE_REGIONS_MIN and blocks_n>=BLOCKS_MIN:
                raw=f"47:{motif[0]}:{','.join(map(str,motif[1]))}:{r}"; h=hashlib.sha256(raw.encode()).hexdigest();candidates.append((h,r,n,outside,outside_regs,blocks_n))
        if candidates:
            h,r,n,outside,oreg,bn=min(candidates)
            selected.append({'digest':h,'motif_length':motif[0],'motif_states':list(motif[1]),'region':r,'inside_n':n,'outside_n':outside,'outside_regions':oreg,'inside_blocks':bn})
    selected=sorted(selected,key=lambda d:d['digest'])[:CAP]
    # diagnostics
    Q=np.vstack([posts[(b,bi)] for b,bi,x in blocks if stable_bucket(b,bi)>=2])
    maxp=Q.max(1); ent=-np.sum(Q*np.log(np.maximum(Q,1e-300)),1)
    qc=Q-Q.mean(0); s=np.linalg.svd(qc,compute_uv=False); eig=(s*s)/(len(Q)-1); var=eig/eig.sum(); cum=np.cumsum(var); pr=(eig.sum()**2)/(np.sum(eig*eig))
    hell=[]; vel=[]
    for b,bi,x in blocks:
        if stable_bucket(b,bi)<2: continue
        q=posts[(b,bi)]
        if len(q)>1:
            hell.extend(np.linalg.norm(np.sqrt(q[1:])-np.sqrt(q[:-1]),axis=1).tolist())
            vel.extend(np.linalg.norm(q[1:]-q[:-1],axis=1).tolist())
    def qs(v):
        a=np.asarray(v);return {'mean':float(a.mean()),'p10':float(np.quantile(a,.1)),'p25':float(np.quantile(a,.25)),'p50':float(np.quantile(a,.5)),'p75':float(np.quantile(a,.75)),'p90':float(np.quantile(a,.9))}
    res={'alignment':{'seed460_perm':perm460.tolist(),'seed460_js_cost':cost460,'seed4600_perm':perm4600.tolist(),'seed4600_js_cost':cost4600},
         'development_train_tokens':int(len(Q)),'primary_supported_motifs':len(eligible_ids),'geometry_occurrences':len(meta),'region_sizes':dict(sorted(region_counts.items())),
         'eligible_holdouts':len(selected),'holdouts':selected,
         'max_posterior':qs(maxp),'posterior_entropy':qs(ent),'pca_variance':var[:11].tolist(),'pca_cumulative':cum[:11].tolist(),'participation_ratio':float(pr),'hellinger_step':qs(hell),'velocity_norm':qs(vel),'motif_region_occupancy':occupancy}
    (out/'v47_geometry_holdouts.json').write_text(json.dumps(res,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:res[k] for k in ['development_train_tokens','primary_supported_motifs','geometry_occurrences','region_sizes','eligible_holdouts','participation_ratio']},sort_keys=True))
if __name__=='__main__': main()
