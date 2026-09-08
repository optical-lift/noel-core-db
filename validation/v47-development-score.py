#!/usr/bin/env python3
"""V47 development-only continuous regime grammar transport scorer.

Implements the frozen primary M0-M5 development scoring, block bootstrap,
q-shift null, and velocity gate. Internal replication and outer holdout are not
read by this program.
"""
from __future__ import annotations
import argparse,csv,hashlib,importlib.util,json,math,random
from collections import Counter,defaultdict
from pathlib import Path
import numpy as np
from scipy.optimize import linear_sum_assignment
from sklearn.cluster import KMeans
import torch
from torch import nn
from torch.utils.data import DataLoader,TensorDataset

ROOT=Path(__file__).resolve().parent
K=12; N=65; MAXD=64
LENS=(6,4,3,2); MIN_SUP=100; PRIMARY_SUP=300
SEEDS=(47,470,4700); BATCH=2048; MAX_EPOCHS=200; PATIENCE=10


def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
v46=load_module('v46kern',ROOT/'v46-consensus-cells.py')

def stable_bucket(book,bi,seed=460046,mod=10):
    h=hashlib.sha256(f"{seed}:{book}:{bi}".encode()).digest();return int.from_bytes(h[:8],'big')%mod

def load_blocks(path):
    out=[]
    with open(path,newline='',encoding='utf-8') as f:
        for r in csv.DictReader(f): out.append((r['book'],int(r['block_index']),np.array([int(v)-1 for v in r['state_sequence'].split(',')],dtype=np.int16)))
    return out

def loadp(path):
    z=np.load(path);return tuple(np.asarray(z[k],dtype=np.float64) for k in ('pi','A','B','D'))
def js(p,q):
    m=.5*(p+q)
    def kl(a,b):
        z=a>0;return float(np.sum(a[z]*np.log(a[z]/np.maximum(b[z],1e-300))))
    return .5*kl(p,m)+.5*kl(q,m)
def align(refB,otherB):
    C=np.array([[js(refB[i],otherB[j]) for j in range(K)] for i in range(K)]);r,c=linear_sum_assignment(C);assert np.array_equal(r,np.arange(K));return c

def consensus_posts(blocks,params):
    refB=params[46][2];perms={46:np.arange(K),460:align(refB,params[460][2]),4600:align(refB,params[4600][2])}
    out={}
    for b,bi,x in blocks:
        gs=[]
        for s in (46,460,4600): gs.append(v46.posterior_occ(x,*params[s])[:,perms[s]])
        q=sum(gs)/3.;q=np.clip(q,1e-8,1);q/=q.sum(1,keepdims=True);out[(b,bi)]=q.astype(np.float32)
    return out

def exact_support(blocks):
    c={L:Counter() for L in LENS}
    for b,bi,x in blocks:
        if stable_bucket(b,bi)<2: continue
        for L in LENS:
            for t in range(L-1,len(x)): c[L][tuple((x[t-L+1:t+1]+1).tolist())]+=1
    return c

def choose_motif(x,t,support):
    for L in LENS:
        if t-L+1<0: continue
        k=tuple((x[t-L+1:t+1]+1).tolist())
        if support[L][k]>=MIN_SUP:return (L,k)
    return None

def build_geometry(blocks,posts,support,frozen):
    assigned_train=[];asup=Counter()
    for b,bi,x in blocks:
        if stable_bucket(b,bi)<2:continue
        for t in range(len(x)):
            m=choose_motif(x,t,support)
            if m: asup[m]+=1;assigned_train.append((b,bi,t,m))
    primary={m for m,n in asup.items() if n>=PRIMARY_SUP};assert len(primary)==126
    X=[];meta=[]
    for b,bi,t,m in assigned_train:
        if m in primary:X.append(np.sqrt(posts[(b,bi)][t]));meta.append((b,bi,t,m))
    km=KMeans(n_clusters=12,random_state=47,n_init=20,algorithm='lloyd').fit(np.vstack(X))
    bym=defaultdict(list)
    for r,(b,bi,t,m) in zip(km.labels_,meta):bym[m].append((int(r),b,bi,t))
    selected=[]
    for m,occ in bym.items():
        c=Counter(r for r,_,_,_ in occ);cand=[]
        for r,n in c.items():
            outside=sum(c.values())-n;oreg=sum(1 for rr,nn in c.items() if rr!=r and nn>0);bn=len({(b,bi) for rr,b,bi,t in occ if rr==r})
            if n>=30 and outside>=300 and oreg>=3 and bn>=3:
                raw=f"47:{m[0]}:{','.join(map(str,m[1]))}:{r}";cand.append((hashlib.sha256(raw.encode()).hexdigest(),r,n,outside,oreg,bn))
        if cand:
            h,r,n,o,or_,bn=min(cand);selected.append((h,m,r,n,o,or_,bn))
    selected=sorted(selected)[:200]
    frozen_sel=[(h,(int(d['motif_length']),tuple(d['motif_states'])),int(d['region'])) for d in frozen['holdouts'] for h in [d['digest']]]
    ours=[(h,m,r) for h,m,r,*_ in selected]
    assert ours==frozen_sel,(len(ours),len(frozen_sel));assert len(ours)==113
    return km,{(m,r):i for i,(h,m,r,*_) in enumerate(selected)},asup

def prepare(blocks,posts,support,km,holdmap,asup):
    motifs=sorted([m for m,n in asup.items() if n>=MIN_SUP],key=lambda m:(m[0],m[1]));mid={m:i for i,m in enumerate(motifs)}
    rows=[]
    for bnum,(b,bi,x) in enumerate(blocks):
        q=posts[(b,bi)];regions=km.predict(np.sqrt(q));v=np.zeros_like(q);v[1:]=q[1:]-q[:-1]
        split='train' if stable_bucket(b,bi)>=2 else 'val'
        for t in range(0,len(x)-4):
            m=choose_motif(x,t,support);mi=mid.get(m,-1);reg=int(regions[t]);hid=holdmap.get((m,reg),-1) if m else -1
            rows.append((b,bi,bnum,t,split,mi,reg,hid,q[t],v[t],x[t+1:t+5].astype(np.int64)))
    return rows,motifs

class M1(nn.Module):
    def __init__(self,nm):super().__init__();self.e=nn.Embedding(nm,16);self.o=nn.Linear(16,N);self.bias=nn.Parameter(torch.zeros(N))
    def forward(self,m,q,v):return self.o(self.e(m))+self.bias
class M2(nn.Module):
    def __init__(self,nm):super().__init__();self.q=nn.Linear(12,8);self.o=nn.Linear(8,N);self.bias=nn.Parameter(torch.zeros(N))
    def forward(self,m,q,v):return self.o(torch.tanh(self.q(q)))+self.bias
class M3(nn.Module):
    def __init__(self,nm):super().__init__();self.e=nn.Embedding(nm,16);self.q=nn.Linear(12,8);self.mo=nn.Linear(16,N);self.qo=nn.Linear(8,N);self.bias=nn.Parameter(torch.zeros(N))
    def parts(self,m,q):return self.e(m),torch.tanh(self.q(q))
    def forward(self,m,q,v):e,z=self.parts(m,q);return self.mo(e)+self.qo(z)+self.bias
class M4(M3):
    def __init__(self,nm):super().__init__(nm);self.A=nn.Parameter(torch.randn(N,8,16)*.02);self.B=nn.Parameter(torch.randn(N,8,8)*.02)
    def forward(self,m,q,v):
        e,z=self.parts(m,q);ae=torch.einsum('bi,sri->bsr',e,self.A);bz=torch.einsum('bj,srj->bsr',z,self.B);return self.mo(e)+self.qo(z)+self.bias+(ae*bz).sum(-1)
class M5(M4):
    def __init__(self,nm):super().__init__(nm);self.vp=nn.Linear(12,8);self.vo=nn.Linear(8,N);self.Av=nn.Parameter(torch.randn(N,8,16)*.02);self.Bv=nn.Parameter(torch.randn(N,8,8)*.02)
    def forward(self,m,q,v):
        e,z=self.parts(m,q);zv=torch.tanh(self.vp(v));ae=torch.einsum('bi,sri->bsr',e,self.A);bz=torch.einsum('bj,srj->bsr',z,self.B);av=torch.einsum('bi,sri->bsr',e,self.Av);bv=torch.einsum('bj,srj->bsr',zv,self.Bv)
        return self.mo(e)+self.qo(z)+self.vo(zv)+self.bias+(ae*bz).sum(-1)+(av*bv).sum(-1)
MODELS={'M1':M1,'M2':M2,'M3':M3,'M4':M4,'M5':M5}

def tensors(rows,model,kind):
    rr=[]
    for r in rows:
        split=r[4];mi=r[5];hid=r[7]
        if kind=='train' and split!='train':continue
        if kind=='val' and split!='val':continue
        if kind=='eval' and not(split=='train' and hid>=0):continue
        if kind in ('train','val') and hid>=0:continue
        if model!='M2' and mi<0:continue
        rr.append(r)
    if not rr:return None
    m=torch.tensor([max(r[5],0) for r in rr],dtype=torch.long);q=torch.tensor(np.stack([r[8] for r in rr]),dtype=torch.float32);v=torch.tensor(np.stack([r[9] for r in rr]),dtype=torch.float32);y=torch.tensor(np.stack([r[10] for r in rr]),dtype=torch.long)
    return rr,TensorDataset(m,q,v,y)
def batch_loss(model,b):
    m,q,v,y=b;logp=torch.log_softmax(model(m,q,v),1);return -logp.gather(1,y).mean()
def eval_ce(model,ds):
    model.eval();tot=0.;n=0
    with torch.no_grad():
        for b in DataLoader(ds,batch_size=BATCH,shuffle=False):
            m,q,v,y=b;loss=batch_loss(model,b);tot+=float(loss)*len(m);n+=len(m)
    return tot/n

def fit(model_name,seed,nm,train_ds,val_ds):
    torch.manual_seed(seed);np.random.seed(seed);random.seed(seed);model=MODELS[model_name](nm)
    opt=torch.optim.AdamW(model.parameters(),lr=.001,weight_decay=.0001);best=1e99;state=None;stale=0
    gen=torch.Generator().manual_seed(seed)
    for ep in range(MAX_EPOCHS):
        model.train()
        for b in DataLoader(train_ds,batch_size=BATCH,shuffle=True,generator=gen):
            opt.zero_grad();loss=batch_loss(model,b);loss.backward();opt.step()
        va=eval_ce(model,val_ds)
        if va<best-1e-7:best=va;state={k:v.detach().clone() for k,v in model.state_dict().items()};stale=0
        else:stale+=1
        if stale>=PATIENCE:break
    model.load_state_dict(state);return model,best,ep+1

def probs(model,ds,q_override=None,v_override=None):
    model.eval();outs=[];off=0
    with torch.no_grad():
        for b in DataLoader(ds,batch_size=BATCH,shuffle=False):
            m,q,v,y=b;n=len(m)
            if q_override is not None:q=torch.tensor(q_override[off:off+n],dtype=torch.float32)
            if v_override is not None:v=torch.tensor(v_override[off:off+n],dtype=torch.float32)
            outs.append(torch.softmax(model(m,q,v),1).cpu().numpy());off+=n
    return np.vstack(outs)
def losses(P,Y):return -np.log(np.maximum(P[np.arange(len(Y))[:,None],Y],1e-300)).mean(1)
def ce(P,Y):return float(losses(P,Y).mean())

def bootstrap(diff,blocks,seed=470047,nboot=10000):
    ub=sorted(set(blocks));idx={b:np.where(np.array(blocks)==b)[0] for b in ub};rng=np.random.default_rng(seed);vals=[]
    for _ in range(nboot):
        samp=rng.choice(ub,len(ub),replace=True);num=0.;den=0
        for b in samp:
            ii=idx[b];num+=float(diff[ii].sum());den+=len(ii)
        vals.append(num/den)
    return [float(np.quantile(vals,.005)),float(np.quantile(vals,.995))]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--csv',required=True);ap.add_argument('--p46',required=True);ap.add_argument('--p460',required=True);ap.add_argument('--p4600',required=True);ap.add_argument('--geometry',required=True);ap.add_argument('--out',required=True);a=ap.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    frozen=json.load(open(a.geometry));blocks=load_blocks(a.csv);params={46:loadp(a.p46),460:loadp(a.p460),4600:loadp(a.p4600)};posts=consensus_posts(blocks,params);support=exact_support(blocks);km,holdmap,asup=build_geometry(blocks,posts,support,frozen);rows,motifs=prepare(blocks,posts,support,km,holdmap,asup);nm=len(motifs)
    fitted={};ens={};trainmeta={}
    for mn in ('M1','M2','M3','M4','M5'):
        tr=tensors(rows,mn,'train');va=tensors(rows,mn,'val');ev=tensors(rows,mn,'eval');assert tr and va and ev
        evrows,evds=ev;seed_probs=[];models=[]
        for s in SEEDS:
            model,bv,it=fit(mn,s,nm,tr[1],va[1]);seed_probs.append(probs(model,evds));models.append(model);trainmeta[f'{mn}_{s}']={'best_val_ce':bv,'epochs':it}
        ens[mn]=sum(seed_probs)/3.;fitted[mn]=models
    evrows,evds=tensors(rows,'M4','eval');Y=np.stack([r[10] for r in evrows]);blocks_eval=[f"{r[0]}:{r[1]}" for r in evrows];hid=np.array([r[7] for r in evrows])
    # M0 on common motif-supported nonheldout train examples
    common=[r for r in rows if r[4]=='train' and r[5]>=0 and r[7]<0];cnt=np.ones(N)*.5
    for r in common:
        for y in r[10]:cnt[y]+=.25
    p0=cnt/cnt.sum();P0=np.tile(p0,(len(Y),1));ces={'M0':ce(P0,Y)}
    for mn in ('M1','M2','M3','M4','M5'):ces[mn]=ce(ens[mn],Y)
    bname=min(('M1','M2','M3'),key=lambda x:ces[x]);LB=losses(ens[bname],Y);L4=losses(ens['M4'],Y);L5=losses(ens['M5'],Y);delta=ces[bname]-ces['M4'];rel=delta/ces[bname]
    ci=bootstrap(LB-L4,blocks_eval);hwin=[]
    for h in sorted(set(hid)):
        ii=np.where(hid==h)[0];hwin.append(float(L4[ii].mean())<float(LB[ii].mean()))
    # q-shift null
    rng=np.random.default_rng(47004700);qnull=[]
    eval_m=np.array([max(r[5],0) for r in evrows],dtype=np.int64);eval_v=np.stack([r[9] for r in evrows]).astype(np.float32)
    block_to_positions=defaultdict(list)
    for i,r in enumerate(evrows):block_to_positions[(r[0],r[1])].append((i,r[3]))
    # lightweight dataset template for M4
    dummyY=np.zeros((len(evrows),4),dtype=np.int64)
    mtorch=torch.tensor(eval_m,dtype=torch.long);vtorch=torch.tensor(eval_v,dtype=torch.float32);yt=torch.tensor(dummyY,dtype=torch.long)
    for z in range(1000):
        qshift=np.zeros((len(evrows),12),dtype=np.float32)
        for key,pairs in block_to_positions.items():
            q=posts[key];off=int(rng.integers(1,len(q)))
            for i,t in pairs:qshift[i]=q[(t-off)%len(q)]
        ds=TensorDataset(mtorch,torch.tensor(qshift),vtorch,yt);pp=sum(probs(m,ds) for m in fitted['M4'])/3.;qnull.append(ces[bname]-ce(pp,Y))
    null99=float(np.quantile(qnull,.99));real_beats=delta>null99
    dvel=ces['M4']-ces['M5'];relvel=dvel/ces['M4'];civel=bootstrap(L4-L5,blocks_eval,seed=470047);vw=[]
    for h in sorted(set(hid)):
        ii=np.where(hid==h)[0];vw.append(float(L5[ii].mean())<float(L4[ii].mean()))
    primary_pass=(len(set(hid))>=20 and delta>0 and rel>=.005 and ci[0]>0 and np.mean(hwin)>=.65 and real_beats)
    vel_pass=(dvel>0 and relvel>=.0025 and civel[0]>0 and np.mean(vw)>=.60)
    res={'eval_examples':len(Y),'eval_holdouts':len(set(hid)),'ce':ces,'best_noninteraction':bname,'delta_ce_transport':delta,'relative_reduction':rel,'bootstrap_99':ci,'holdout_win_fraction':float(np.mean(hwin)),'q_shift_null_99':null99,'q_shift_real_beats_99':bool(real_beats),'primary_development_pass':bool(primary_pass),'delta_ce_velocity':dvel,'velocity_relative_reduction':relvel,'velocity_bootstrap_99':civel,'velocity_holdout_win_fraction':float(np.mean(vw)),'velocity_gate_pass':bool(vel_pass),'training':trainmeta}
    (out/'v47_development_result.json').write_text(json.dumps(res,indent=2,sort_keys=True)+'\n');print(json.dumps({k:res[k] for k in ['eval_examples','eval_holdouts','ce','best_noninteraction','delta_ce_transport','relative_reduction','bootstrap_99','holdout_win_fraction','q_shift_null_99','q_shift_real_beats_99','primary_development_pass','delta_ce_velocity','velocity_gate_pass']},sort_keys=True))
if __name__=='__main__':main()
