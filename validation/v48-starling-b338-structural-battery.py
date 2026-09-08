#!/usr/bin/env python3
"""V48 European starling B338 blind structural battery.

Consumes a provenance-verified anonymous bout CSV with columns:
    bout_id, recording_id, day, sequence
where sequence is comma-separated positive integer symbol IDs.

This program implements the target-blind/descriptive and discrete predictive
parts of the frozen V48 preregistration. It does not use audio, acoustic
coordinates, biological labels, published starling findings, or Hebrew data.

Latent HMM/HSMM comparison is deliberately a separate execution module because
it requires substantially heavier fitting. This file freezes the common
corpus split, lag/radius landscape, Markov decomposition, block entropy,
transition geometry, and surrogate construction before B338 scoring.
"""
from __future__ import annotations
import argparse,csv,hashlib,json,math
from collections import Counter,defaultdict
from pathlib import Path
import numpy as np

SEED_SPLIT=48
SEED_DEV=480048
MAX_LAG=64
MAX_RADIUS=16
MAX_BLOCK_N=8
VO_ORDERS=(3,4,6,8)
ALPHA=0.5


def stable_bucket(text:str,seed:int,mod:int=10000)->int:
    h=hashlib.sha256(f"{seed}:{text}".encode()).digest()
    return int.from_bytes(h[:8],'big')%mod


def load_bouts(path:Path):
    bouts=[]
    with path.open(newline='',encoding='utf-8') as f:
        for r in csv.DictReader(f):
            x=np.array([int(v) for v in r['sequence'].split(',') if v!=''],dtype=np.int32)
            if len(x)==0: continue
            if np.any(x<=0): raise ValueError('symbols must be positive integers')
            bouts.append({'bout_id':r['bout_id'],'recording_id':r.get('recording_id',''),
                          'day':r.get('day',''),'x':x})
    if not bouts: raise RuntimeError('no bouts')
    ids=[b['bout_id'] for b in bouts]
    if len(ids)!=len(set(ids)): raise RuntimeError('bout_id must be unique')
    return bouts


def split_bouts(bouts):
    dev=[];hold=[]
    for b in bouts:
        (dev if stable_bucket(b['bout_id'],SEED_SPLIT)<7000 else hold).append(b)
    dtrain=[];dval=[]
    for b in dev:
        (dtrain if stable_bucket(b['bout_id'],SEED_DEV)>=2000 else dval).append(b)
    return dev,hold,dtrain,dval


def inventory(bouts):
    lens=np.array([len(b['x']) for b in bouts],dtype=int)
    allx=np.concatenate([b['x'] for b in bouts])
    c=Counter(map(int,allx)); runs=[]
    for b in bouts:
        x=b['x']; run=1
        for i in range(1,len(x)):
            if x[i]==x[i-1]: run+=1
            else: runs.append(run);run=1
        runs.append(run)
    return {
        'bouts':len(bouts),'tokens':int(len(allx)),'alphabet_size':len(c),
        'bout_length':summary(lens),'state_counts':dict(sorted(c.items())),
        'singleton_states':sum(1 for n in c.values() if n==1),
        'states_lt5':sum(1 for n in c.values() if n<5),
        'run_length':summary(np.array(runs,dtype=int)),
    }


def summary(a):
    if len(a)==0:return None
    return {'min':float(np.min(a)),'q10':float(np.quantile(a,.1)),'median':float(np.median(a)),
            'mean':float(np.mean(a)),'q90':float(np.quantile(a,.9)),'max':float(np.max(a))}


def entropy_counts(counts):
    a=np.asarray(list(counts),dtype=float); a=a[a>0]
    if len(a)==0:return float('nan')
    p=a/a.sum();return float(-(p*np.log(p)).sum())


def mutual_info_pairs(pairs):
    if not pairs:return float('nan')
    joint=Counter(pairs); cx=Counter(a for a,b in pairs); cy=Counter(b for a,b in pairs); n=len(pairs)
    mi=0.0
    for (a,b),v in joint.items():
        p=v/n; mi+=p*math.log(p/((cx[a]/n)*(cy[b]/n)))
    return mi


def lag_landscape(bouts,rng):
    out=[]
    for d in range(1,MAX_LAG+1):
        pairs=[];shpairs=[]
        for b in bouts:
            x=b['x']
            if len(x)<=d:continue
            pairs.extend(zip(map(int,x[:-d]),map(int,x[d:])))
            y=x.copy();rng.shuffle(y)
            shpairs.extend(zip(map(int,y[:-d]),map(int,y[d:])))
        if len(pairs)<100:break
        mi=mutual_info_pairs(pairs); null=mutual_info_pairs(shpairs)
        joint=Counter(pairs); left=Counter(a for a,b in pairs)
        cond=0.0;n=len(pairs)
        for a,na in left.items():
            vals=[v for (aa,_),v in joint.items() if aa==a]
            cond += (na/n)*entropy_counts(vals)
        recur=sum(a==b for a,b in pairs)/n
        out.append({'lag':d,'n_pairs':n,'mi_nats':mi,'shuffle_mi_nats':null,
                    'excess_mi_nats':mi-null,'conditional_entropy_nats':cond,'recurrence':recur})
    return out


def js_from_counts(a,b):
    keys=sorted(set(a)|set(b)); pa=np.array([a[k] for k in keys],float);pb=np.array([b[k] for k in keys],float)
    if pa.sum()==0 or pb.sum()==0:return float('nan')
    pa/=pa.sum();pb/=pb.sum();m=.5*(pa+pb)
    def kl(p,q):
        z=p>0;return float(np.sum(p[z]*np.log(p[z]/q[z])))
    return .5*kl(pa,m)+.5*kl(pb,m)


def radius_landscape(bouts):
    rows=[]
    for r in range(1,MAX_RADIUS+1):
        vals=[]
        for b in bouts:
            x=b['x']
            for t in range(r,len(x)-r):
                l=Counter(map(int,x[t-r:t])); rr=Counter(map(int,x[t+1:t+r+1]));both=l+rr
                total=2*r; ent=entropy_counts(both.values())/math.log(max(2,len(both))) if len(both)>1 else 0.0
                conc=max(both.values())/total
                inter=sum(min(l[k],rr[k]) for k in set(l)|set(rr)); union=sum(max(l[k],rr[k]) for k in set(l)|set(rr))
                vals.append((len(both),ent,conc,inter/union if union else 0,js_from_counts(l,rr),
                             int(x[t] in l or x[t] in rr)))
        if not vals:break
        a=np.asarray(vals,float)
        rows.append({'radius':r,'n_centers':len(vals),'mean_distinct':float(a[:,0].mean()),
                     'mean_normalized_entropy':float(a[:,1].mean()),'mean_concentration':float(a[:,2].mean()),
                     'mean_left_right_overlap':float(a[:,3].mean()),'mean_left_right_js':float(a[:,4].mean()),
                     'center_recurrence_any':float(a[:,5].mean())})
    return rows


def make_ngram_counts(bouts,order):
    ctx=defaultdict(Counter); unig=Counter()
    for b in bouts:
        x=list(map(int,b['x']));unig.update(x)
        for t in range(order,len(x)):ctx[tuple(x[t-order:t])][x[t]]+=1
    return ctx,unig


def pred_prob(symbol,context,tables,unig,K):
    # deterministic longest supported backoff; any observed context is supported.
    for o in sorted(tables,reverse=True):
        if len(context)>=o:
            c=tuple(context[-o:]); cc=tables[o].get(c)
            if cc:
                den=sum(cc.values())+ALPHA*K;return (cc.get(symbol,0)+ALPHA)/den
    den=sum(unig.values())+ALPHA*K;return (unig.get(symbol,0)+ALPHA)/den


def score_ngram(train,test,max_order):
    alph=sorted(set(np.concatenate([b['x'] for b in train])));K=len(alph)
    tables={o:make_ngram_counts(train,o)[0] for o in range(1,max_order+1)}
    unig=make_ngram_counts(train,1)[1]
    losses=[]
    for b in test:
        x=list(map(int,b['x']))
        for t in range(len(x)):
            p=pred_prob(x[t],x[:t],tables,unig,K);losses.append(-math.log(max(p,1e-300)))
    return float(np.mean(losses)),len(losses)


def markov_decomposition(dtrain,dval,hold):
    # Development validation is reported for audit; blind holdout uses architecture fixed a priori.
    models={'frequency':0,'markov1':1,'markov2':2,'vo3':3,'vo4':4,'vo6':6,'vo8':8}
    out={}
    for name,o in models.items():
        out[name]={'dev_validation_ce':score_ngram(dtrain,dval,o)[0] if dval else None,
                   'blind_holdout_ce':score_ngram(dtrain+dval,hold,o)[0] if hold else None}
    return out


def block_entropy(bouts):
    out=[]
    prev=None
    for n in range(1,MAX_BLOCK_N+1):
        c=Counter()
        for b in bouts:
            x=list(map(int,b['x']))
            for t in range(0,len(x)-n+1):c[tuple(x[t:t+n])]+=1
        if sum(c.values())<100:break
        h=entropy_counts(c.values());inc=None if prev is None else h-prev
        out.append({'n':n,'samples':sum(c.values()),'distinct_blocks':len(c),'H_n_nats':h,'increment_nats':inc})
        prev=h
    return out


def transition_geometry(bouts):
    states=sorted(set(np.concatenate([b['x'] for b in bouts])));ix={s:i for i,s in enumerate(states)};K=len(states)
    C=np.zeros((K,K),float)
    freq=np.zeros(K,float)
    for b in bouts:
        x=list(map(int,b['x']));
        for s in x:freq[ix[s]]+=1
        for a,bv in zip(x[:-1],x[1:]):C[ix[a],ix[bv]]+=1
    P=(C+ALPHA)/(C.sum(1,keepdims=True)+ALPHA*K)
    marg=freq/freq.sum();res=P-marg[None,:]
    s=np.linalg.svd(res,compute_uv=False);pr=(s.sum()**2)/(np.square(s).sum()) if np.square(s).sum()>0 else 0
    sym=.5*(P+P.T);directional=.5*(P-P.T)
    return {'states':states,'transition_count':int(C.sum()),'singular_values_residual':s.tolist(),
            'residual_participation_ratio':float(pr),'directional_frobenius':float(np.linalg.norm(directional)),
            'symmetric_frobenius':float(np.linalg.norm(sym))}


def simulate_markov(bouts,rng):
    states=sorted(set(np.concatenate([b['x'] for b in bouts])));ix={s:i for i,s in enumerate(states)};K=len(states)
    C=np.ones((K,K))*ALPHA;init=np.ones(K)*ALPHA
    for b in bouts:
        x=list(map(int,b['x']));init[ix[x[0]]]+=1
        for a,c in zip(x[:-1],x[1:]):C[ix[a],ix[c]]+=1
    P=C/C.sum(1,keepdims=True);init/=init.sum();out=[]
    for b in bouts:
        n=len(b['x']);z=np.empty(n,dtype=np.int32);z[0]=rng.choice(states,p=init)
        for t in range(1,n):z[t]=rng.choice(states,p=P[ix[z[t-1]]])
        out.append({**b,'x':z})
    return out


def shuffled_within_bouts(bouts,rng):
    out=[]
    for b in bouts:
        x=b['x'].copy();rng.shuffle(x);out.append({**b,'x':x})
    return out


def main():
    ap=argparse.ArgumentParser();ap.add_argument('csv',type=Path);ap.add_argument('--out',type=Path,default=Path('v48_b338'))
    a=ap.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    bouts=load_bouts(a.csv);dev,hold,dtrain,dval=split_bouts(bouts)
    if not dev or not hold:raise RuntimeError('intact-bout 70/30 split empty')
    rng=np.random.default_rng(48)
    real={'inventory':inventory(bouts),'split':{'development_bouts':len(dev),'blind_holdout_bouts':len(hold),'development_train_bouts':len(dtrain),'development_validation_bouts':len(dval)},
          'lag':lag_landscape(dev,np.random.default_rng(4801)),'radius':radius_landscape(dev),
          'markov':markov_decomposition(dtrain,dval,hold),'block_entropy':block_entropy(dev),'transition_geometry':transition_geometry(dev)}
    within=shuffled_within_bouts(dev,np.random.default_rng(4802));mk=simulate_markov(dev,np.random.default_rng(4803))
    real['surrogates']={'within_bout_shuffle':{'lag':lag_landscape(within,np.random.default_rng(4804)),'block_entropy':block_entropy(within)},
                        'first_order_markov':{'lag':lag_landscape(mk,np.random.default_rng(4805)),'block_entropy':block_entropy(mk)}}
    payload='\n'.join(f"{b['bout_id']}|{','.join(map(str,b['x']))}" for b in bouts)
    real['anonymous_sequence_sha256']=hashlib.sha256(payload.encode()).hexdigest()
    (a.out/'structural_battery.json').write_text(json.dumps(real,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':'OK','bouts':len(bouts),'tokens':real['inventory']['tokens'],'alphabet':real['inventory']['alphabet_size'],'sha256':real['anonymous_sequence_sha256']},sort_keys=True))

if __name__=='__main__':main()
