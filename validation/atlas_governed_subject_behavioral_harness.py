from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from typing import Any, Optional
import hashlib, json, uuid


def iso(s: str) -> datetime:
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


def fingerprint(obj: Any) -> str:
    payload = json.dumps(obj, sort_keys=True, separators=(',', ':'), default=str)
    return hashlib.md5(payload.encode()).hexdigest()


@dataclass(frozen=True)
class Resource:
    id: str
    state: str = 'active'

@dataclass(frozen=True)
class Org:
    id: str
    status: str = 'active'

@dataclass(frozen=True)
class Responsibility:
    id: str
    org_id: str
    stable_key: str
    kind: str = 'stewardship'
    status: str = 'active'

@dataclass(frozen=True)
class Scope:
    id: str
    org_id: str
    responsibility_id: str
    scope_kind: str
    scope_id: str
    relation_kind: str

@dataclass(frozen=True)
class Observation:
    id: str
    resource_id: str
    observation_type: str
    payload: dict
    observer_ref: str
    observer_entity_id: Optional[str]
    observed_at: datetime
    recorded_at: datetime
    provenance: dict
    idempotency_key: str
    payload_fingerprint: str

@dataclass(frozen=True)
class Applicability:
    id: str
    scope_id: str
    resource_id: str
    operation_key: str
    effective_from: datetime
    effective_until: Optional[datetime]
    provenance: dict
    admitted_at: datetime
    idempotency_key: str
    payload_fingerprint: str

class Conflict(Exception): pass
class Invalid(Exception): pass

class Harness:
    def __init__(self):
        self.resources: dict[str, Resource] = {}
        self.orgs: dict[str, Org] = {}
        self.responsibilities: dict[str, Responsibility] = {}
        self.scopes: dict[str, Scope] = {}
        self.observations: list[Observation] = []
        self.obs_keys: dict[str, Observation] = {}
        self.apps: list[Applicability] = []
        self.app_keys: dict[str, Applicability] = {}
        self.clock = iso('2026-09-28T18:00:00Z')

    def tick(self, seconds=1):
        self.clock += timedelta(seconds=seconds)
        return self.clock

    def record_observation(self, resource_id, observation_type, payload, observer_ref,
                           observed_at, idempotency_key, observer_entity_id=None, provenance=None):
        provenance = provenance or {}
        if resource_id not in self.resources: raise Invalid('resource does not exist')
        if self.resources[resource_id].state != 'active': raise Invalid('resource must be active')
        if not observation_type.strip(): raise Invalid('observation_type required')
        if not isinstance(payload, dict): raise Invalid('payload object required')
        if not observer_ref.strip(): raise Invalid('observer_ref required')
        if not idempotency_key.strip(): raise Invalid('idempotency key required')
        basis = {
            'resource_id': resource_id, 'observation_type': observation_type.strip(),
            'observation_payload': payload, 'observer_ref': observer_ref.strip(),
            'observer_entity_id': observer_entity_id, 'observed_at': observed_at.isoformat(),
            'provenance': provenance,
        }
        fp = fingerprint(basis)
        if idempotency_key in self.obs_keys:
            old = self.obs_keys[idempotency_key]
            if old.payload_fingerprint != fp: raise Conflict('observation idempotency conflict')
            return {'state':'replayed','observationId':old.id,'resourceId':old.resource_id}
        row = Observation(str(uuid.uuid4()), resource_id, observation_type.strip(), payload,
                          observer_ref.strip(), observer_entity_id, observed_at, self.tick(),
                          provenance, idempotency_key, fp)
        self.observations.append(row); self.obs_keys[idempotency_key] = row
        assert any(o.id == row.id and o.payload_fingerprint == fp for o in self.observations)
        return {'state':'admitted','observationId':row.id,'resourceId':row.resource_id,
                'observedAt':row.observed_at,'recordedAt':row.recorded_at}

    def resolve_latest_observation(self, resource_id, observation_type, observed_as_of, recorded_as_of):
        if resource_id not in self.resources:
            return {'state':'indeterminate','reason':'resource_not_found'}
        rows = [o for o in self.observations if o.resource_id == resource_id and
                o.observation_type == observation_type and o.observed_at <= observed_as_of and
                o.recorded_at <= recorded_as_of]
        if not rows:
            return {'state':'indeterminate','reason':'no_admitted_observation',
                    'resourceId':resource_id,'observationType':observation_type}
        row = sorted(rows, key=lambda o:(o.observed_at,o.recorded_at,o.id), reverse=True)[0]
        return {'state':'established_latest','reason':'latest_admitted_observation_found',
                'resourceId':row.resource_id,'observationId':row.id,
                'observationType':row.observation_type,'observationPayload':row.payload,
                'observedAt':row.observed_at,'recordedAt':row.recorded_at,
                'provenance':row.provenance,'payloadFingerprint':row.payload_fingerprint}

    def admit_applicability(self, scope_id, resource_id, operation_key, effective_from,
                            effective_until, idempotency_key, provenance=None):
        provenance = provenance or {}
        if scope_id not in self.scopes: raise Invalid('scope missing')
        if resource_id not in self.resources: raise Invalid('resource missing')
        s = self.scopes[scope_id]
        r = self.responsibilities.get(s.responsibility_id)
        o = self.orgs.get(s.org_id)
        if not r or r.org_id != s.org_id: raise Invalid('scope structurally invalid')
        if r.status != 'active' or not o or o.status != 'active': raise Invalid('org/responsibility inactive')
        if self.resources[resource_id].state != 'active': raise Invalid('resource inactive')
        if not operation_key.strip(): raise Invalid('operation required')
        if effective_until is not None and effective_until <= effective_from: raise Invalid('bad interval')
        basis = {'responsibility_scope_id':scope_id,'resource_id':resource_id,
                 'operation_key':operation_key.strip(),'effective_from':effective_from.isoformat(),
                 'effective_until':effective_until.isoformat() if effective_until else None,
                 'provenance':provenance}
        fp = fingerprint(basis)
        if idempotency_key in self.app_keys:
            old = self.app_keys[idempotency_key]
            if old.payload_fingerprint != fp: raise Conflict('applicability idempotency conflict')
            return {'state':'replayed','applicabilityId':old.id}
        def overlaps(a: Applicability):
            if (a.scope_id,a.resource_id,a.operation_key)!=(scope_id,resource_id,operation_key.strip()): return False
            a_end = a.effective_until or datetime.max.replace(tzinfo=timezone.utc)
            b_end = effective_until or datetime.max.replace(tzinfo=timezone.utc)
            return a.effective_from < b_end and effective_from < a_end
        if any(overlaps(a) for a in self.apps): raise Conflict('applicability overlap')
        row = Applicability(str(uuid.uuid4()),scope_id,resource_id,operation_key.strip(),effective_from,
                            effective_until,provenance,self.tick(),idempotency_key,fp)
        self.apps.append(row); self.app_keys[idempotency_key]=row
        assert any(a.id == row.id and a.payload_fingerprint == fp for a in self.apps)
        return {'state':'admitted','applicabilityId':row.id}

    def resolve_applicability(self, scope_id, resource_id, operation_key, as_of):
        if scope_id not in self.scopes: return {'state':'indeterminate','reason':'responsibility_scope_not_found'}
        if resource_id not in self.resources: return {'state':'indeterminate','reason':'resource_not_found'}
        rows=[a for a in self.apps if (a.scope_id,a.resource_id,a.operation_key)==(scope_id,resource_id,operation_key)]
        cur=[a for a in rows if a.effective_from <= as_of and (a.effective_until is None or as_of < a.effective_until)]
        if len(cur)>1: return {'state':'indeterminate','reason':'multiple_current_applicability_rows'}
        if not cur:
            return {'state':'indeterminate','reason':'applicability_not_recorded'} if not rows else {'state':'established_not_current','reason':'applicability_exists_but_not_current'}
        a=cur[0]; s=self.scopes[scope_id]; r=self.responsibilities[s.responsibility_id]
        return {'state':'established_current','item':{
            'applicabilityId':a.id,'organizationId':s.org_id,'responsibilityId':r.id,
            'responsibilityKey':r.stable_key,'responsibilityKind':r.kind,
            'responsibilityScopeId':s.id,'scopeKind':s.scope_kind,'scopeId':s.scope_id,
            'scopeRelationKind':s.relation_kind,'resourceId':a.resource_id,
            'operationKey':a.operation_key,'effectiveFrom':a.effective_from,'effectiveUntil':a.effective_until}}


def assert_raises(exc, fn):
    try: fn()
    except exc: return
    raise AssertionError(f'expected {exc.__name__}')


def run():
    h=Harness(); now=iso('2026-09-28T18:30:00Z')
    grounds='059f65d9-e41d-4366-bd8a-742ef6ad34bd'; other='other-resource'
    org='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'; resp='0c95d93a-2dc2-46f6-864f-a222b7f9e85b'; scope='7b36de04-e752-41f9-a069-82e2120ffbc3'
    h.resources[grounds]=Resource(grounds); h.resources[other]=Resource(other)
    h.orgs[org]=Org(org); h.responsibilities[resp]=Responsibility(resp,org,'grounds_readiness')
    h.scopes[scope]=Scope(scope,org,resp,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards')
    results=[]
    def ok(name): results.append(name)

    q=h.resolve_latest_observation(grounds,'surface_height_v1',now,now)
    assert q['state']=='indeterminate' and q['reason']=='no_admitted_observation'; ok('missing observation is indeterminate')

    t0=iso('2026-09-27T18:00:00Z')
    a=h.record_observation(grounds,'surface_height_v1',{'height_inches':8},'observer:test',t0,'obs:1',provenance={'test':True})
    assert a['state']=='admitted' and a['observedAt']==t0 and a['recordedAt']>t0
    r=h.record_observation(grounds,'surface_height_v1',{'height_inches':8},'observer:test',t0,'obs:1',provenance={'test':True})
    assert r['state']=='replayed' and r['observationId']==a['observationId']; ok('observation replay is canonical')
    assert_raises(Conflict,lambda:h.record_observation(grounds,'surface_height_v1',{'height_inches':9},'observer:test',t0,'obs:1',provenance={'test':True})); ok('observation conflicting replay fails closed')
    q=h.resolve_latest_observation(other,'surface_height_v1',now,now)
    assert q['reason']=='no_admitted_observation'; ok('observation does not leak across resources')

    t1=iso('2026-09-28T18:10:00Z')
    b=h.record_observation(grounds,'surface_height_v1',{'height_inches':4},'observer:test',t1,'obs:2',provenance={'test':True})
    q=h.resolve_latest_observation(grounds,'surface_height_v1',now,now)
    assert q['observationId']==b['observationId'] and q['observationPayload']['height_inches']==4
    hist=h.resolve_latest_observation(grounds,'surface_height_v1',t0+timedelta(minutes=1),now)
    assert hist['observationId']==a['observationId'] and hist['observationPayload']['height_inches']==8; ok('observation history survives supersession')

    afrom=iso('2026-09-01T00:00:00Z')
    ap=h.admit_applicability(scope,grounds,'acquire_current_grounds_observation',afrom,None,'app:1',{'test':True})
    assert ap['state']=='admitted'
    apr=h.admit_applicability(scope,grounds,'acquire_current_grounds_observation',afrom,None,'app:1',{'test':True})
    assert apr['state']=='replayed' and apr['applicabilityId']==ap['applicabilityId']; ok('applicability replay is canonical')
    assert_raises(Conflict,lambda:h.admit_applicability(scope,grounds,'acquire_current_grounds_observation',now-timedelta(days=1),now+timedelta(days=1),'app:overlap',{'test':True})); ok('overlapping applicability fails closed')
    q=h.resolve_applicability(scope,grounds,'acquire_current_grounds_observation',now)
    assert q['state']=='established_current' and q['item']['resourceId']==grounds and q['item']['responsibilityScopeId']==scope; ok('exact applicability resolves current')
    q=h.resolve_applicability(scope,other,'acquire_current_grounds_observation',now)
    assert q['state']=='indeterminate' and q['reason']=='applicability_not_recorded'; ok('missing applicability stays unknown')

    h2=Harness(); h2.resources[grounds]=Resource(grounds); h2.orgs[org]=Org(org); h2.responsibilities[resp]=Responsibility(resp,org,'grounds_readiness'); h2.scopes[scope]=h.scopes[scope]
    x0=iso('2026-09-01T00:00:00Z'); x1=iso('2026-09-15T00:00:00Z')
    first=h2.admit_applicability(scope,grounds,'acquire_current_grounds_observation',x0,x1,'a1')
    second=h2.admit_applicability(scope,grounds,'acquire_current_grounds_observation',x1,None,'a2')
    assert h2.resolve_applicability(scope,grounds,'acquire_current_grounds_observation',x0+timedelta(days=1))['item']['applicabilityId']==first['applicabilityId']
    assert h2.resolve_applicability(scope,grounds,'acquire_current_grounds_observation',x1+timedelta(days=1))['item']['applicabilityId']==second['applicabilityId']; ok('adjacent applicability replacement preserves history')

    e=Harness(); e.resources[grounds]=Resource(grounds); e.resources[other]=Resource(other); e.orgs[org]=Org(org); e.responsibilities[resp]=Responsibility(resp,org,'grounds_readiness'); e.scopes[scope]=h.scopes[scope]
    e.admit_applicability(scope,grounds,'acquire_current_grounds_observation',afrom,None,'elm-app')
    carrier={'person_id':'998e6116-6d9d-4ee5-9d48-6c239d58507b','responsibility_id':resp,'scope_id':scope,'current':True}
    def encounter(engine:Harness, resource_id=grounds, carrier_state=carrier, scope_id=scope, responsibility_id=resp):
        obs=engine.resolve_latest_observation(resource_id,'grounds_observation_v1',now,now)
        app=engine.resolve_applicability(scope_id,resource_id,'acquire_current_grounds_observation',now)
        supported=(obs['state']=='indeterminate' and obs.get('reason')=='no_admitted_observation' and carrier_state and carrier_state.get('current') and carrier_state.get('responsibility_id')==responsibility_id and carrier_state.get('scope_id')==scope_id and app['state']=='established_current' and app['item']['responsibilityId']==responsibility_id and app['item']['resourceId']==resource_id)
        return {'silence':not supported,'encounter': {'recipient':carrier_state['person_id'],'subject':resource_id} if supported else None}
    before=encounter(e); assert before['silence'] is False and before['encounter']['subject']==grounds; ok('missing Grounds observation + carrier + applicability derives encounter')
    assert encounter(e,resource_id=other)['silence'] is True; ok('wrong subject gives silence')
    assert encounter(e,carrier_state=None)['silence'] is True; ok('no current carrier gives silence')
    e.record_observation(grounds,'grounds_observation_v1',{'observed':'current'},'elm-observer',now-timedelta(minutes=5),'elm-obs')
    after=encounter(e); assert after['silence'] is True; ok('canonical writeback causes natural silence')

    return {'status':'PASS','tests':len(results),'passed':results,
            'not_proven':['PostgreSQL parser/plpgsql compilation','RLS enforcement','GRANT/REVOKE privilege behavior','advisory-lock concurrency under real Postgres']}

if __name__=='__main__':
    print(json.dumps(run(), indent=2, default=str))
