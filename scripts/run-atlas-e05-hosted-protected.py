#!/usr/bin/env python3
"""E05: protected hosted-Linux signed test on fresh job-owned PostgreSQL 17.

Input: protected read-only production schema/roles dump FILES; never the
production connection. All Auth users, Work, Result, grants for transport,
and native services exist only inside the disposable local named database.
"""
import argparse
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import platform
import secrets
import subprocess
import tempfile
import threading
import time

PG_IMAGE=('supabase/postgres:17.6.1.136@sha256:'
          'f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00')
GO_URL='https://go.dev/dl/go1.24.13.linux-amd64.tar.gz'
GO_SHA='1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730'
REST_URL=('https://github.com/PostgREST/postgrest/releases/download/v13.0.8/'
          'postgrest-v13.0.8-linux-static-x86-64.tar.xz')
REST_SHA='eb4471a7b8112a54e103539f2348c4d7f1c5b9b390649700ad62836e9211e279'

class Held(RuntimeError):pass

def require(ok,reason):
    if not ok:raise Held(reason)

def private_command(argv,env=None,timeout=120):
    # Never emit raw subprocess output: SQL, tokens or passwords may be present.
    try:
        result=subprocess.run([str(a) for a in argv],env=env,capture_output=True,
                              text=True,timeout=timeout,check=False)
    except (OSError,subprocess.SubprocessError):
        raise Held('Protected test command unavailable') from None
    require(result.returncode==0,'Protected test command failed (private output withheld)')
    return result.stdout.strip()

def local_sql(db,query,env):
    return private_command(['psql',db,'-X','-A','-t','-v','ON_ERROR_STOP=1',
                            '-c',query],env=env,timeout=35)

def clean_docker(resources,temp):
    name,root=resources.get('name'),resources.get('dbroot')
    if name:
        subprocess.run(['docker','stop','--time','8',name],
                       capture_output=True,text=True,timeout=30,check=False)
        subprocess.run(['docker','rm','-f',name],
                       capture_output=True,text=True,timeout=30,check=False)
    if root:
        require(temp in root.resolve().parents and root.name.startswith('e05-hosted-pg.'),
                'Refuse foreign PGDATA deletion')
        subprocess.run(['sudo','rm','-rf','--',str(root)],
                       capture_output=True,text=True,timeout=90,check=False)
        require(not root.exists(),'Job-local PGDATA cleanup incomplete')

def db_start(runtime,native,temp,resources):
    root=Path(tempfile.mkdtemp(prefix='e05-hosted-pg.',dir=temp))
    resources['dbroot']=root
    folder=root/'db'
    folder.mkdir(mode=0o700)
    data=str(folder.resolve(strict=True))
    database='atlas_e05_'+secrets.token_hex(8)
    passwd=secrets.token_urlsafe(40)
    port=native.free_port()
    name='atlas-e05-'+secrets.token_hex(8)
    resources['name']=name
    # Bind mount a path whose string is identical on the HOST and IN Docker.
    # Existing Noel PGDATA guard independently verifies it belongs to
    # RUNNER_TEMP; the Docker volume default is not silently grandfathered.
    private_command(['docker','run','--detach','--name',name,
        '--mount',f'type=bind,source={data},target={data}',
        '--publish',f'127.0.0.1:{port}:5432',
        '--env','PGDATA='+data,'--env','POSTGRES_DB='+database,
        '--env','POSTGRES_PASSWORD='+passwd,
        PG_IMAGE,'postgres','-c','config_file=/etc/postgresql/postgresql.conf'],
        timeout=180)
    env=dict(runtime.env,PGHOST='127.0.0.1',PGPORT=str(port),
             PGUSER='postgres',PGPASSWORD=passwd,PGDATABASE=database,
             PGCONNECT_TIMEOUT='3',PSQLRC='/dev/null')
    db=f'postgresql://postgres@127.0.0.1:{port}/{database}'
    for _ in range(45):
        try:
            row=local_sql(db,('SELECT current_database(),host(inet_server_addr()),'
                              "current_setting('data_directory'),"
                              "current_setting('server_version_num');"),env)
        except Held:
            time.sleep(1)
            continue
        # An actual connected but mismatched server is a hard failure, not a
        # temporary network issue to conceal behind retries.
        p=row.split('|')
        require(len(p)==4 and p[0]==database and p[1]=='127.0.0.1'
                and p[2]==data and int(p[3])//10000==17,
                'Disposable PG17 database, loopback or PGDATA mismatch')
        require(temp in Path(p[2]).resolve(strict=True).parents,
                'Disposable image PGDATA not inside job temporary directory')
        return db,env,port,passwd,database
    raise Held('Pinned container PostgreSQL 17 did not become ready')

def auth_start(runtime,native,db,env,port,password,database):
    secret=secrets.token_urlsafe(48)
    authport=native.free_port()
    base=f'http://127.0.0.1:{authport}'
    auth_env=dict(runtime.env,
        DATABASE_URL=f'postgresql://postgres:{password}@127.0.0.1:{port}/{database}?sslmode=disable',
        GOTRUE_DB_DRIVER='postgres',DB_NAMESPACE='auth',
        GOTRUE_DB_MIGRATIONS_PATH=str(runtime.root/'auth-source/migrations'),
        GOTRUE_API_HOST='127.0.0.1',PORT=str(authport),
        API_EXTERNAL_URL=base,GOTRUE_SITE_URL=base,
        GOTRUE_JWT_SECRET=secret,GOTRUE_JWT_AUD='authenticated',
        GOTRUE_JWT_DEFAULT_GROUP_NAME='authenticated',
        GOTRUE_EXTERNAL_EMAIL_ENABLED='true',GOTRUE_DISABLE_SIGNUP='true',
        GOTRUE_MAILER_AUTOCONFIRM='true',
        GOTRUE_EXTERNAL_PHONE_ENABLED='false',GOTRUE_LOG_LEVEL='error')
    auth=runtime.service([runtime.root/'auth'],auth_env,'auth')
    native.wait_health(auth,base,'/health')
    values=local_sql(db,("SELECT to_regclass('auth.users') IS NOT NULL,"
        "to_regclass('auth.sessions') IS NOT NULL,"
        "to_regclass('auth.identities') IS NOT NULL,"
        "(SELECT count(*) FROM auth.schema_migrations)>0;"),env)
    require(values=='t|t|t|t','Pinned GoTrue did not initialize managed local Auth')
    require(local_sql(db,'SELECT count(*) FROM auth.users;',env)=='0',
            'Disposable Auth contains real or existing users')
    return authport,secret

def rest_start(runtime,native,db,env,port,database,secret):
    restport=native.free_port()
    pw=secrets.token_urlsafe(36)
    local_sql(db,"ALTER ROLE authenticator LOGIN PASSWORD '"+pw+"';",env)
    envrest=dict(runtime.env,
        PGRST_DB_URI=f'postgresql://authenticator:{pw}@127.0.0.1:{port}/{database}',
        PGRST_DB_SCHEMAS='public',PGRST_DB_ANON_ROLE='anon',
        PGRST_JWT_SECRET=secret,PGRST_SERVER_HOST='127.0.0.1',
        PGRST_SERVER_PORT=str(restport),PGRST_DB_CONFIG='false',
        PGRST_DB_CHANNEL_ENABLED='false',PGRST_LOG_LEVEL='error')
    rest=runtime.service([runtime.root/'rest/postgrest'],envrest,'rest')
    native.wait_health(rest,f'http://127.0.0.1:{restport}','/')
    return restport

def run(noel,atlas,roles_path,schema_path):
    require(platform.system()=='Linux' and platform.machine()=='x86_64',
            'Only the protected hosted Ubuntu amd64 job is admitted')
    raw=os.environ.get('RUNNER_TEMP','')
    require(raw and not Path(raw).is_symlink(),'Explicit job-only RUNNER_TEMP required')
    temp=Path(raw).resolve(strict=True)
    require(temp.is_dir() and noel.is_dir() and atlas.is_dir(),
            'Source trees or job directory absent')
    # Authoritative Noel owner supplies the exact RPC and fixture contracts.
    import importlib.util
    source=noel/'scripts/run-atlas-e05-owner-protected-signed.py'
    spec=importlib.util.spec_from_file_location('e05_owner',source)
    require(spec and spec.loader,'Reviewed E05 source contract unavailable')
    owner=importlib.util.module_from_spec(spec);spec.loader.exec_module(owner)
    for rel,expected in owner.PINNED_BLOBS.items():
        path=atlas/rel
        require(path.is_file() and not path.is_symlink() and
                owner.git_blob(path)==expected,'Unreviewed Atlas signed source')
    roles=owner.safe_file(roles_path,temp)
    schema=owner.safe_file(schema_path,temp)
    native=owner.source_module(atlas/'scripts/atlas-riversong-signed-transport.py',
                               'e05_pinned_native_transport')
    # Same reviewed GoTrue commit and PostgREST version as RiverSong; Linux
    # binary releases are SHA256 verified rather than running macOS code.
    native.GO_URL,native.GO_SHA=GO_URL,GO_SHA
    native.REST_URL,native.REST_SHA=REST_URL,REST_SHA
    runtime=None
    proxy=None
    thread=None
    resources={'name':None,'dbroot':None}
    stage='PINNED_SOURCE_AND_PRIVATE_INPUTS'
    result=1
    try:
        runtime=native.Runtime(Path(tempfile.mkdtemp(prefix='e05-hosted-native.',dir=temp)))
        stage='FRESH_PINNED_SUPABASE_POSTGRESQL17'
        db,env,port,password,database=db_start(runtime,native,temp,resources)
        stage='PINNED_NATIVE_GOTRUE_AND_POSTGREST_BUILD'
        binary=native.build(runtime)
        require(binary.is_file(),'Verified PostgREST binary unavailable')
        stage='DISPOSABLE_PRODUCTION_ROLE_RESTORE'
        private_command(['psql',db,'-X','-v','ON_ERROR_STOP=1','-f',roles],env=env,timeout=350)
        # CLI schema-only dump intentionally EXCLUDES managed Auth. Genuine
        # GoTrue migrations create its managed tables before app SQL restores.
        stage='PINNED_LOCAL_AUTH_INITIALIZATION'
        authport,secret=auth_start(runtime,native,db,env,port,password,database)
        stage='DISPOSABLE_APP_SCHEMA_RESTORE'
        private_command(['psql',db,'-X','-v','ON_ERROR_STOP=1','-f',schema],env=env,timeout=400)
        stage='CURRENT_SOURCE_AND_ACL_ELIGIBILITY'
        receipt=runtime.root/'e05-source-gate.json'
        gate=subprocess.run(['python3',str(noel/'scripts/check-atlas-e05-current-source.py'),
            '--db-url',db,'--output',str(receipt)],env=dict(os.environ,**env),
            capture_output=True,text=True,timeout=80)
        require(gate.returncode==0 and receipt.is_file(),
                'E05 source/ACL/empty clone eligibility refused')
        report=json.loads(receipt.read_text())
        require(report.get('state')=='E05_SOURCE_ELIGIBLE_NOT_FULL_PARITY'
                and report.get('productionChanges') is False,
                'Unrecognized E05 source gate receipt')
        stage='REAL_LOCAL_POSTGREST'
        restport=rest_start(runtime,native,db,env,port,database,secret)
        proxy=ThreadingHTTPServer(('127.0.0.1',0),owner.Proxy)
        proxy.auth_port=authport
        proxy.rest_port=restport
        thread=threading.Thread(target=proxy.serve_forever,daemon=True)
        thread.start()
        credentials={}
        for actor in ('governor','recipient','outsider'):
            credentials['ATLAS_E05_'+actor.upper()+'_EMAIL']=(
                'e05-'+actor+'-'+secrets.token_hex(8)+'@example.invalid')
            credentials['ATLAS_E05_'+actor.upper()+'_PASSWORD']=secrets.token_urlsafe(36)
        credentials['ATLAS_E05_LOCAL_ANON_KEY']=secrets.token_urlsafe(36)
        stage='THREE_REAL_SIGNED_ATLAS_WORK_ACTORS'
        bridge=subprocess.run(['python3',str(noel/'scripts/run-atlas-e05-isolated-riversong.py'),
            '--db-url',db,'--api-url',f'http://127.0.0.1:{proxy.server_port}',
            '--atlas-runner',str(atlas/'scripts/atlas-riversong-e05-signed-acceptance.py')],
            env=dict(os.environ,**env,**credentials),capture_output=True,
            text=True,timeout=850)
        require(bridge.returncode==0 and
                'E05_SIGNED_SOURCE_ACCEPTANCE=PASS;' in bridge.stdout,
                'Unmodified E05 genuine signed native Work test failed')
        print('E05_HOSTED_SIGNED_SOURCE=PASS; REAL_GOTRUE_USERS=3; BROWSER=NOT_RUN; RECIPIENT_HISTORY=HELD')
        result=0
    except (Held,native.Blocked,OSError,ValueError,subprocess.SubprocessError):
        print('E05_HOSTED_SIGNED_SOURCE=HELD; STAGE='+stage+'; PRIVATE_DIAGNOSTICS_WITHHELD')
        result=1
    finally:
        if proxy:proxy.shutdown();proxy.server_close()
        if thread:thread.join(timeout=8)
        if runtime:
            try:runtime.cleanup()
            except (native.Blocked,OSError,subprocess.SubprocessError):
                print('E05_HOSTED_NATIVE_CLEANUP=FAILED')
                result=1
        try:clean_docker(resources,temp)
        except (Held,OSError,subprocess.SubprocessError):
            print('E05_HOSTED_PGDATA_CLEANUP=FAILED')
            result=1
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--noel-source',type=Path,required=True)
    p.add_argument('--atlas-source',type=Path,required=True)
    p.add_argument('--roles-dump',type=Path,required=True)
    p.add_argument('--schema-dump',type=Path,required=True)
    a=p.parse_args()
    os.umask(0o077)
    return run(a.noel_source.resolve(strict=True),a.atlas_source.resolve(strict=True),
               a.roles_dump,a.schema_dump)

if __name__=='__main__':
    try:raise SystemExit(main())
    except (Held,OSError,ValueError,subprocess.SubprocessError):
        print('E05_HOSTED_SIGNED_SOURCE=HELD; PRIVATE_DIAGNOSTICS_WITHHELD')
        raise SystemExit(1) from None
