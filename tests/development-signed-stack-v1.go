// Fixed fictional signed-stack probe. Not a candidate executor.
package main

import (
 "bytes"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "io"
 "net"
 "net/http"
 "os"
 "strings"
 "time"
)

const owner = "e5300000-0000-4000-8000-000000000001"
const worker = "e5300000-0000-4000-8000-000000000002"
const outsider = "e5300000-0000-4000-8000-000000000003"
const password = "Fictional-development-boundary-2026!"
func require(ok bool, msg string) { if !ok { fmt.Fprintln(os.Stderr,"REFUSE:",msg); os.Exit(1) } }
func dial(addr string) bool { c,e:=net.DialTimeout("tcp",addr,2*time.Second); if e!=nil{return false}; c.Close();return true }
func endpoint(s string) bool { h,p,e:=net.SplitHostPort(s); return e==nil && net.ParseIP(h)!=nil && net.ParseIP(h).To4()!=nil && p!="" }
func main() {
 require(len(os.Args)>=2,"missing mode")
 switch os.Args[1] {
 case "serve":
  l,e:=net.Listen("tcp4",":18080"); require(e==nil,"fictional peer bind")
  for { c,e:=l.Accept(); if e==nil {c.Close()} }
 case "network":
  require(len(os.Args)==4&&endpoint(os.Args[2])&&endpoint(os.Args[3]),"invalid network inputs")
  require(dial(os.Args[2]),"admitted peer unreachable");require(!dial(os.Args[3]),"excluded peer reachable")
  fmt.Println("PASS actual stack network namespace selected-peer boundary")
 case "positive":
  require(len(os.Args)==3&&endpoint(os.Args[2]),"invalid positive control");require(dial(os.Args[2]),"excluded peer control unreachable")
 case "signed":
  require(len(os.Args)==3&&endpoint(os.Args[2]),"invalid local gateway")
  raw,e:=io.ReadAll(io.LimitReader(os.Stdin,8193)); require(e==nil&&len(raw)<=8192,"invalid local key input")
  key:=strings.TrimSpace(string(raw)); require(len(key)>20&&!strings.ContainsAny(key," \r\n\t"),"missing local anon key")
  api:="http://"+os.Args[2]
  client:=&http.Client{Timeout:15*time.Second,Transport:&http.Transport{Proxy:nil},CheckRedirect:func(*http.Request,[]*http.Request)error{return http.ErrUseLastResponse}}
  request:=func(path string,body any,token string)(int,any){
   data,e:=json.Marshal(body);require(e==nil,"encode test body")
   r,e:=http.NewRequest("POST",api+path,bytes.NewReader(data));require(e==nil,"local request")
   r.Header.Set("Content-Type","application/json");r.Header.Set("apikey",key)
   if token!=""{r.Header.Set("Authorization","Bearer "+token)}
   resp,e:=client.Do(r);require(e==nil,"local HTTP unavailable");defer resp.Body.Close()
   b,e:=io.ReadAll(io.LimitReader(resp.Body,65537));require(e==nil&&len(b)<=65536,"bounded local response")
   var v any;require(json.Unmarshal(b,&v)==nil,"non-JSON local response")
   return resp.StatusCode,v
  }
  sign:=func(name,id string)(string,string){
   status,v:=request("/auth/v1/token?grant_type=password",map[string]string{"email":"dev-boundary-"+name+"@example.invalid","password":password},"")
   m,ok:=v.(map[string]any);require(status==200&&ok,"GoTrue sign-in "+name)
   token,_:=m["access_token"].(string);p:=strings.Split(token,".");require(len(p)==3&&p[2]!="","missing signed JWT")
   b,e:=base64.RawURLEncoding.DecodeString(p[1]);require(e==nil,"JWT payload encoding")
   var claims map[string]any;require(json.Unmarshal(b,&claims)==nil,"JWT claims")
   session,_:=claims["session_id"].(string);require(claims["sub"]==id&&claims["role"]=="authenticated"&&session!="","independent signed identity")
   return token,session
  }
  a,sa:=sign("owner",owner);b,sb:=sign("worker",worker);c,sc:=sign("outsider",outsider)
  require(sa!=sb&&sa!=sc&&sb!=sc,"sessions not independent")
  call:=func(fn,token string)(int,any){return request("/rest/v1/rpc/"+fn,map[string]any{},token)}
  allow:=func(token,expected string){status,v:=call("development_boundary_read_v1",token);require(status==200&&v==expected,"signed positive read")}
  deny:=func(token string){status,v:=call("development_boundary_read_v1",token);m,ok:=v.(map[string]any);require((status==401||status==403)&&ok&&m["code"]=="42501","expected source permission denial 42501")}
  allow(a,"fictional-original");allow(b,"fictional-original");deny(c);deny("")
  p:=strings.Split(a,"."); if p[2][0]=='A'{p[2]="B"+p[2][1:]}else{p[2]="A"+p[2][1:]}
  status,_:=call("development_boundary_read_v1",strings.Join(p,"."));require(status==401||status==403,"tampered JWT admitted")
  status,v:=call("development_boundary_revoke_v1",a);require(status==200&&v==true,"owner revocation")
  deny(b);allow(a,"fictional-original");deny(c)
  fmt.Println("PASS fictional PG17/GoTrue/PostgREST signed owner worker outsider anonymous tamper and revocation")
 default: require(false,"unknown mode")
 }
}
