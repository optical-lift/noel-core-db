declare const Deno: any;

type Json = Record<string, unknown>;
type Observation = {
  id:string; observation_key:string; observation_kind:string; ordinal:number|null;
  text_candidate:string|null; coordinate_unit:string; x:number|null; y:number|null;
  width:number|null; height:number|null; confidence:number|null; derivation_method:string;
  source_format:string; processor:Json; external_locator:Json; metadata:Json;
};
type ObservationRelation = {
  id:string; source_asset_id:string; container_observation_id:string; child_observation_id:string;
  relation_kind:string; ordinal:number|null; derivation_method:string; evidence:Json;
};
type ObservationClassification = {
  id:string; source_asset_id:string; observation_id:string; classification_key:string;
  classification_scope:string; classification_kind:string; classification_state:string;
  reading_disposition:string; classification_authority:string; derivation_method:string;
  confidence:number|null; evidence:Json;
};
type ReadingAdjudication = {
  id:string; source_package_id:string; adjudication_key:string;
  adjudication_kind:"reading_text"|"paragraph_continuity";
  start_asset_id:string; start_observation_id:string; end_asset_id:string|null;
  end_observation_id:string|null;
  result:"replace_reading_text"|"retain_observed_text"|"join_across_boundary"|"break_at_boundary"|"unresolved";
  adjudicated_text:string|null; adjudication_authority:string; derivation_method:string;
  confidence:number|null; rationale:string; evidence:Json;
};
type Surface = {
  id:string; asset_key:string; media_type:string|null; storage_uri:string|null;
  source_locator:Json; metadata:Json; observations:Observation[];
};
type SourceSpan = {
  id:string; span_key:string; start_asset_id:string; start_asset_key:string;
  start_observation_id:string|null; start_boundary:"asset_start"|"at_observation"|"after_observation";
  end_asset_id:string; end_asset_key:string; end_observation_id:string|null;
  end_boundary:"asset_end"|"at_observation"|"before_observation";
  boundary_authority:string; derivation_method:string; evidence:Json;
};
type SourcePacket = {
  source_package_key:string; source_package_id:string;
  target_parent_block:{id:string; block_key:string; block_type:string; semantic_role:string|null; properties:Json};
  source_span:SourceSpan|null; observation_relations:ObservationRelation[];
  observation_classifications:ObservationClassification[]; reading_adjudications:ReadingAdjudication[];
  existing_child_count:number; existing_max_ordinal:number; surfaces:Surface[];
};
type SourceMode = "region"|"region_fragment"|"line"|"page_text";
type Unit = {
  text:string; observationIds:string[]; locator:Json; assetKey:string; surfaceIndex:number;
  x:number|null; y:number|null; width:number|null; height:number|null; confidence:number|null;
  explicitBoundaryBefore:boolean; sourceMode:SourceMode; continuesForward?:boolean;
  continuesBackward?:boolean; readingAdjudicationIds?:string[];
};
type ParagraphDraft = {
  text:string; observationIds:Set<string>; locators:Json[]; assetKeys:Set<string>;
  reviewReasons:Set<string>; structuralScores:number[]; sourceConfidences:number[];
  sourceModes:Set<string>; readingAdjudicationIds:Set<string>; kind:"paragraph"|"heading";
};

function response(status:number, body:unknown){
  return new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
}
function decodeJwtPayload(token:string):Json|null{
  try{
    const part=token.split(".")[1]; if(!part)return null;
    const normalized=part.replace(/-/g,"+").replace(/_/g,"/").padEnd(Math.ceil(part.length/4)*4,"=");
    return JSON.parse(atob(normalized));
  }catch{return null;}
}
async function sha256Hex(text:string){
  const digest=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(text)));
  return Array.from(digest,(b)=>b.toString(16).padStart(2,"0")).join("");
}
async function rpc(name:string, body:Json){
  const base=Deno.env.get("SUPABASE_URL"); const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!base||!key)throw new Error("Supabase runtime credentials unavailable");
  const r=await fetch(`${base}/rest/v1/rpc/${name}`,{
    method:"POST",
    headers:{apikey:key,authorization:`Bearer ${key}`,"content-type":"application/json",accept:"application/json"},
    body:JSON.stringify(body)
  });
  const text=await r.text();
  if(!r.ok)throw new Error(`${name} ${r.status}: ${text.slice(0,2000)}`);
  return text?JSON.parse(text):null;
}
function median(values:number[]){
  if(!values.length)return null;
  const a=[...values].sort((x,y)=>x-y); const m=Math.floor(a.length/2);
  return a.length%2?a[m]:(a[m-1]+a[m])/2;
}
function cleanText(s:string){ return s.replace(/[\u00a0\t]+/g," ").replace(/ {2,}/g," ").trim(); }
function isHeading(text:string){
  const t=cleanText(text);
  if(/^(chapter|part|book)\s+(?:\d+|[ivxlcdm]+)\b/i.test(t))return true;
  const letters=t.replace(/[^A-Za-z]/g,"");
  return t.length>0&&t.length<=90&&letters.length>=4&&letters===letters.toUpperCase()&&/[A-Z]/.test(letters);
}
function terminal(text:string){ return /[.!?][”’"')\]]?$/.test(cleanText(text)); }
function startsLower(text:string){ const m=cleanText(text).match(/[A-Za-z]/); return !!m&&m[0]===m[0].toLowerCase(); }
function startsQuote(text:string){ return /^[“‘"']/.test(cleanText(text)); }
function makeLocator(surface:Surface):Json{
  const s=surface.source_locator??{}; const out:Json={source_asset_id:surface.id,source_asset_key:surface.asset_key};
  for(const key of ["sequence_index","printed_page","source_pdf_page","pdf_page","loc_image","iiif_canvas_uri","iiif_image_service_uri","image_uri","pdf_uri","item_uri"]){
    if(s[key]!==undefined&&s[key]!==null)out[key]=s[key];
  }
  return out;
}
function joinPhysicalLines(lines:Observation[]){
  let out="";
  for(const line of lines){
    const t=cleanText(line.text_candidate??""); if(!t)continue;
    if(!out)out=t;
    else if(/-$/.test(out)&&startsLower(t))out=out.slice(0,-1)+t;
    else out+=` ${t}`;
  }
  return cleanText(out);
}
function lineUnits(surface:Surface,surfaceIndex:number):Unit[]{
  const obs=surface.observations??[];
  const regions=obs.filter((o)=>(o.observation_kind==="region"||o.observation_kind==="layout_region")&&cleanText(o.text_candidate??""));
  if(regions.length){
    return regions.sort((a,b)=>(a.ordinal??1e9)-(b.ordinal??1e9)||(a.y??1e9)-(b.y??1e9)||(a.x??1e9)-(b.x??1e9)).map((o,i)=>({
      text:cleanText(o.text_candidate??""),observationIds:[o.id],locator:makeLocator(surface),assetKey:surface.asset_key,
      surfaceIndex,x:o.x,y:o.y,width:o.width,height:o.height,confidence:o.confidence,explicitBoundaryBefore:i>0,sourceMode:"region" as const
    }));
  }
  const lines=obs.filter((o)=>o.observation_kind==="line"&&cleanText(o.text_candidate??""));
  if(lines.length){
    return lines.sort((a,b)=>(a.ordinal??1e9)-(b.ordinal??1e9)||(a.y??1e9)-(b.y??1e9)||(a.x??1e9)-(b.x??1e9)).map((o)=>({
      text:cleanText(o.text_candidate??""),observationIds:[o.id],locator:makeLocator(surface),assetKey:surface.asset_key,
      surfaceIndex,x:o.x,y:o.y,width:o.width,height:o.height,confidence:o.confidence,explicitBoundaryBefore:false,sourceMode:"line" as const
    }));
  }
  const pages=obs.filter((o)=>o.observation_kind==="page_text"&&cleanText(o.text_candidate??""));
  if(!pages.length)return[];
  const page=[...pages].sort((a,b)=>{
    const an=(a.text_candidate??"").split(/\r?\n/).length; const bn=(b.text_candidate??"").split(/\r?\n/).length;
    return bn-an||(b.confidence??-1)-(a.confidence??-1);
  })[0];
  const raw=(page.text_candidate??"").split(/\r?\n/); const out:Unit[]=[]; let blankBefore=false;
  for(const part of raw){
    const t=cleanText(part); if(!t){blankBefore=true;continue;}
    out.push({text:t,observationIds:[page.id],locator:makeLocator(surface),assetKey:surface.asset_key,surfaceIndex,
      x:null,y:null,width:null,height:null,confidence:page.confidence,explicitBoundaryBefore:blankBefore,sourceMode:"page_text"});
    blankBefore=false;
  }
  return out;
}
function unitFromObservations(unit:Unit,kept:Observation[],overrides:Partial<Unit>={}):Unit{
  const boxed=kept.filter((o)=>o.x!==null&&o.y!==null&&o.width!==null&&o.height!==null);
  const x=boxed.length?Math.min(...boxed.map((o)=>o.x!)):unit.x;
  const y=boxed.length?Math.min(...boxed.map((o)=>o.y!)):unit.y;
  const right=boxed.length?Math.max(...boxed.map((o)=>o.x!+o.width!)):null;
  const bottom=boxed.length?Math.max(...boxed.map((o)=>o.y!+o.height!)):null;
  const confs=kept.map((o)=>o.confidence).filter((v):v is number=>typeof v==="number");
  return {...unit,text:joinPhysicalLines(kept),observationIds:kept.map((o)=>o.id),x,y,
    width:right!==null&&x!==null?right-x:unit.width,height:bottom!==null&&y!==null?bottom-y:unit.height,
    confidence:confs.length?Math.min(...confs):unit.confidence,sourceMode:"region_fragment",...overrides};
}
function childRelations(packet:SourcePacket,containerId:string){
  return (packet.observation_relations??[]).filter((r)=>r.relation_kind==="contains"&&r.container_observation_id===containerId)
    .sort((a,b)=>(a.ordinal??1e9)-(b.ordinal??1e9));
}
function fragmentRegionUnit(packet:SourcePacket,surface:Surface,unit:Unit,anchorId:string,
  boundary:"at_observation"|"after_observation"|"before_observation",isStart:boolean):Unit[]|null{
  const anchorRelation=(packet.observation_relations??[]).find((r)=>r.relation_kind==="contains"&&r.child_observation_id===anchorId&&unit.observationIds.includes(r.container_observation_id));
  if(!anchorRelation)return null;
  const relations=childRelations(packet,anchorRelation.container_observation_id);
  if(!relations.length)throw new Error(`Governed boundary container ${anchorRelation.container_observation_id} has no active child observations`);
  const byId=new Map(surface.observations.map((o)=>[o.id,o]));
  const children=relations.map((r)=>byId.get(r.child_observation_id)).filter((o):o is Observation=>!!o);
  if(children.length!==relations.length)throw new Error(`Governed boundary container ${anchorRelation.container_observation_id} has child observations missing from the selected source surface`);
  const anchorIndex=relations.findIndex((r)=>r.child_observation_id===anchorId);
  if(anchorIndex<0)throw new Error(`Governed boundary child ${anchorId} disappeared from its active containment relation`);
  const kept=isStart?(boundary==="after_observation"?children.slice(anchorIndex+1):children.slice(anchorIndex)):
    (boundary==="before_observation"?children.slice(0,anchorIndex):children.slice(0,anchorIndex+1));
  if(!kept.length)return[];
  return[unitFromObservations(unit,kept,{continuesForward:isStart,continuesBackward:!isStart})];
}
function applySourceSpan(packet:SourcePacket,surfaceUnits:Unit[][]):Unit[][]{
  const span=packet.source_span; if(!span)return surfaceUnits;
  const bounded=surfaceUnits.map((units)=>[...units]);
  const applyBoundary=(surfaceIndex:number,anchorId:string|null,boundary:"at_observation"|"after_observation"|"before_observation",isStart:boolean)=>{
    const units=bounded[surfaceIndex];
    if(!anchorId)throw new Error("Governed source-span observation boundary is missing its observation id");
    const directIndex=units.findIndex((unit)=>unit.observationIds.includes(anchorId));
    if(directIndex>=0){
      bounded[surfaceIndex]=isStart?(boundary==="after_observation"?units.slice(directIndex+1):units.slice(directIndex)):
        (boundary==="before_observation"?units.slice(0,directIndex):units.slice(0,directIndex+1));
      return;
    }
    const relation=(packet.observation_relations??[]).find((r)=>r.relation_kind==="contains"&&r.child_observation_id===anchorId);
    if(!relation)throw new Error(`Governed source-span ${isStart?"start":"end"} observation ${anchorId} was not present in the selected reconstruction evidence mode or an active containment relation`);
    const containerIndex=units.findIndex((unit)=>unit.observationIds.includes(relation.container_observation_id));
    if(containerIndex<0)throw new Error(`Governed source-span ${isStart?"start":"end"} observation ${anchorId} belongs to container ${relation.container_observation_id}, but that container was not present in the selected source evidence mode`);
    const fragment=fragmentRegionUnit(packet,packet.surfaces[surfaceIndex],units[containerIndex],anchorId,boundary,isStart);
    if(fragment===null)throw new Error(`Governed source-span ${isStart?"start":"end"} observation ${anchorId} could not be resolved through active containment`);
    bounded[surfaceIndex]=isStart?[...fragment,...units.slice(containerIndex+1)]:[...units.slice(0,containerIndex),...fragment];
  };
  const startSurfaceIndex=packet.surfaces.findIndex((s)=>s.asset_key===span.start_asset_key);
  if(startSurfaceIndex>=0&&span.start_boundary!=="asset_start")applyBoundary(startSurfaceIndex,span.start_observation_id,span.start_boundary,true);
  const endSurfaceIndex=packet.surfaces.findIndex((s)=>s.asset_key===span.end_asset_key);
  if(endSurfaceIndex>=0&&span.end_boundary!=="asset_end")applyBoundary(endSurfaceIndex,span.end_observation_id,span.end_boundary,false);
  return bounded;
}
function governedReadingExclusions(packet:SourcePacket){
  return new Set((packet.observation_classifications??[]).filter((c)=>c.classification_scope==="page_furniture"&&c.reading_disposition==="exclude"&&(c.classification_state==="verified"||c.classification_state==="adjudicated")).map((c)=>c.observation_id));
}
function applyReadingExclusions(packet:SourcePacket,surfaceUnits:Unit[][]):Unit[][]{
  const excluded=governedReadingExclusions(packet); if(!excluded.size)return surfaceUnits;
  return surfaceUnits.map((units,surfaceIndex)=>{
    const surface=packet.surfaces[surfaceIndex]; const byId=new Map(surface.observations.map((o)=>[o.id,o])); const out:Unit[]=[];
    for(const unit of units){
      const directlyExcluded=unit.observationIds.filter((id)=>excluded.has(id));
      if(directlyExcluded.length){
        if(unit.sourceMode==="line")continue;
        if(unit.sourceMode==="page_text"){
          if(directlyExcluded.length===unit.observationIds.length)continue;
          throw new Error(`Governed reading exclusion cannot partially fragment page_text evidence on ${unit.assetKey}`);
        }
        if(unit.sourceMode==="region_fragment"){
          const kept=unit.observationIds.filter((id)=>!excluded.has(id)).map((id)=>byId.get(id)).filter((o):o is Observation=>!!o);
          if(!kept.length)continue;
          if(kept.length!==unit.observationIds.length-directlyExcluded.length)throw new Error(`Governed reading exclusion references fragment children missing from ${unit.assetKey}`);
          out.push(unitFromObservations(unit,kept,{continuesForward:unit.continuesForward,continuesBackward:unit.continuesBackward}));
          continue;
        }
        if(unit.sourceMode==="region")continue;
      }
      if(unit.sourceMode==="region"){
        const containerId=unit.observationIds[0]; const relations=childRelations(packet,containerId);
        const excludedChildren=relations.filter((r)=>excluded.has(r.child_observation_id));
        if(excludedChildren.length){
          const kept=relations.filter((r)=>!excluded.has(r.child_observation_id)).map((r)=>byId.get(r.child_observation_id)).filter((o):o is Observation=>!!o);
          if(kept.length!==relations.length-excludedChildren.length)throw new Error(`Governed page-furniture exclusion container ${containerId} has children missing from ${unit.assetKey}`);
          if(!kept.length)continue;
          out.push(unitFromObservations(unit,kept));
          continue;
        }
      }
      out.push(unit);
    }
    return out;
  });
}
function activeTextAdjudications(packet:SourcePacket){
  return (packet.reading_adjudications??[]).filter((a)=>a.adjudication_kind==="reading_text"&&a.result!=="unresolved");
}
function unitContainsAnchor(packet:SourcePacket,unit:Unit,anchorId:string){
  if(unit.observationIds.includes(anchorId))return true;
  return (packet.observation_relations??[]).some((r)=>r.relation_kind==="contains"&&r.child_observation_id===anchorId&&unit.observationIds.includes(r.container_observation_id));
}
function applyTextAdjudications(packet:SourcePacket,surfaceUnits:Unit[][]):Unit[][]{
  const adjudications=activeTextAdjudications(packet); if(!adjudications.length)return surfaceUnits;
  const used=new Map<string,number>();
  const result=surfaceUnits.map((units,surfaceIndex)=>{
    const surface=packet.surfaces[surfaceIndex]; const byId=new Map(surface.observations.map((o)=>[o.id,o]));
    return units.map((unit)=>{
      const matching=adjudications.filter((a)=>a.start_asset_id===surface.id&&unitContainsAnchor(packet,unit,a.start_observation_id));
      if(!matching.length)return unit;
      let text=unit.text; const appliedIds:string[]=[];
      if(unit.sourceMode==="line"){
        const a=matching.find((x)=>unit.observationIds.includes(x.start_observation_id));
        if(a){
          if(a.result==="replace_reading_text")text=cleanText(a.adjudicated_text??"");
          appliedIds.push(a.id); used.set(a.id,(used.get(a.id)??0)+1);
        }
      }else if(unit.sourceMode==="region"||unit.sourceMode==="region_fragment"){
        const observationIds=unit.sourceMode==="region_fragment"?unit.observationIds:childRelations(packet,unit.observationIds[0]).map((r)=>r.child_observation_id);
        const lines=observationIds.map((id)=>byId.get(id)).filter((o):o is Observation=>!!o);
        if(lines.length!==observationIds.length)throw new Error(`Governed reading adjudication cannot resolve all child observations on ${unit.assetKey}`);
        const transformed=lines.map((line)=>{
          const a=matching.find((x)=>x.start_observation_id===line.id);
          if(!a)return line;
          appliedIds.push(a.id); used.set(a.id,(used.get(a.id)??0)+1);
          if(a.result==="replace_reading_text")return {...line,text_candidate:cleanText(a.adjudicated_text??"")};
          return line;
        });
        text=joinPhysicalLines(transformed);
      }else if(unit.sourceMode==="page_text"){
        const a=matching.find((x)=>unit.observationIds.includes(x.start_observation_id));
        if(a){
          if(a.result==="replace_reading_text")text=cleanText(a.adjudicated_text??"");
          appliedIds.push(a.id); used.set(a.id,(used.get(a.id)??0)+1);
        }
      }
      const unique=[...new Set([...(unit.readingAdjudicationIds??[]),...appliedIds])];
      return {...unit,text,readingAdjudicationIds:unique};
    });
  });
  for(const a of adjudications){
    const count=used.get(a.id)??0;
    const survives=result.some((units)=>units.some((unit)=>unitContainsAnchor(packet,unit,a.start_observation_id)));
    if(survives&&count!==1)throw new Error(`Governed reading adjudication ${a.adjudication_key} was expected to apply exactly once; applied ${count} times`);
  }
  return result;
}
function continuityDecision(packet:SourcePacket,previousUnit:Unit,unit:Unit):ReadingAdjudication|null{
  const matches=(packet.reading_adjudications??[]).filter((a)=>
    a.adjudication_kind==="paragraph_continuity"&&a.end_observation_id!==null&&
    unitContainsAnchor(packet,previousUnit,a.start_observation_id)&&unitContainsAnchor(packet,unit,a.end_observation_id)
  );
  if(matches.length>1)throw new Error(`Multiple governed paragraph-continuity decisions match ${previousUnit.assetKey} -> ${unit.assetKey}`);
  return matches[0]??null;
}
function addUnit(draft:ParagraphDraft,unit:Unit){
  const t=cleanText(unit.text);
  if(!draft.text)draft.text=t;
  else if(/-$/.test(draft.text)&&startsLower(t))draft.text=draft.text.slice(0,-1)+t;
  else draft.text+=` ${t}`;
  for(const id of unit.observationIds)draft.observationIds.add(id);
  for(const id of unit.readingAdjudicationIds??[])draft.readingAdjudicationIds.add(id);
  if(!draft.assetKeys.has(unit.assetKey))draft.locators.push(unit.locator);
  draft.assetKeys.add(unit.assetKey); draft.sourceModes.add(unit.sourceMode);
  if(typeof unit.confidence==="number")draft.sourceConfidences.push(unit.confidence);
}
function newDraft(kind:"paragraph"|"heading"):ParagraphDraft{
  return{text:"",observationIds:new Set(),locators:[],assetKeys:new Set(),reviewReasons:new Set(),structuralScores:[],sourceConfidences:[],sourceModes:new Set(),readingAdjudicationIds:new Set(),kind};
}
function dedupeLocators(locators:Json[]){
  const seen=new Set<string>(); const out:Json[]=[];
  for(const loc of locators){ const key=JSON.stringify(loc); if(!seen.has(key)){seen.add(key);out.push(loc);} }
  return out;
}
function isRegionMode(unit:Unit){ return unit.sourceMode==="region"||unit.sourceMode==="region_fragment"; }
function buildDrafts(packet:SourcePacket):ParagraphDraft[]{
  const bounded=applySourceSpan(packet,packet.surfaces.map((s,i)=>lineUnits(s,i)));
  const exclusionsApplied=applyReadingExclusions(packet,bounded);
  const surfaceUnits=applyTextAdjudications(packet,exclusionsApplied);
  const drafts:ParagraphDraft[]=[]; let current:ParagraphDraft|null=null; let previousUnit:Unit|null=null;
  const usedContinuity=new Map<string,number>();
  for(let si=0;si<surfaceUnits.length;si++){
    const units=surfaceUnits[si]; if(!units.length)continue;
    const xVals=units.map((u)=>u.x).filter((v):v is number=>typeof v==="number"); const baselineX=median(xVals);
    const pageWidth=Number(packet.surfaces[si].source_locator?.pixel_width??0)||null; const gapVals:number[]=[];
    for(let i=1;i<units.length;i++){
      const a=units[i-1],b=units[i];
      if(typeof a.y==="number"&&typeof a.height==="number"&&typeof b.y==="number"){
        const g=b.y-(a.y+a.height); if(g>=0)gapVals.push(g);
      }
    }
    const medianGap=median(gapVals);
    for(const unit of units){
      if(isHeading(unit.text)){
        if(current?.text)drafts.push(current);
        current=newDraft("heading"); addUnit(current,unit);
        current.reviewReasons.add("heading_or_chapter_boundary_requires_parentage_review"); current.structuralScores.push(0.99);
        drafts.push(current); current=null; previousUnit=unit; continue;
      }
      let breakBefore=false; let score=0.5; let reason:string|null=null; let boundaryAdjudication:ReadingAdjudication|null=null;
      if(!current||!previousUnit){breakBefore=true;score=1;}
      else if(unit.surfaceIndex!==previousUnit.surfaceIndex){
        boundaryAdjudication=continuityDecision(packet,previousUnit,unit);
        if(boundaryAdjudication){
          usedContinuity.set(boundaryAdjudication.id,(usedContinuity.get(boundaryAdjudication.id)??0)+1);
          if(boundaryAdjudication.result==="join_across_boundary"){
            breakBefore=false; score=boundaryAdjudication.confidence??0.99;
          }else if(boundaryAdjudication.result==="break_at_boundary"){
            breakBefore=true; score=boundaryAdjudication.confidence??0.99;
          }else{
            breakBefore=false; score=0.5; reason="governed_paragraph_continuity_unresolved";
          }
        }else if(/-$/.test(previousUnit.text)||(!terminal(previousUnit.text)&&startsLower(unit.text))){breakBefore=false;score=0.95;}
        else if(!terminal(previousUnit.text)){breakBefore=false;score=0.82;reason="cross_page_continuation_inferred_without_terminal_punctuation";}
        else{breakBefore=true;score=0.60;reason="page_boundary_paragraph_break_ambiguous";}
      }else if(previousUnit.continuesForward&&isRegionMode(unit)){
        if(!terminal(previousUnit.text)||startsLower(unit.text)){breakBefore=false;score=0.95;}
        else{breakBefore=true;score=0.62;reason="boundary_fragment_adjacent_region_continuity_ambiguous";}
      }else if(unit.continuesBackward&&isRegionMode(previousUnit)){
        if(!terminal(previousUnit.text)||startsLower(unit.text)){breakBefore=false;score=0.95;}
        else{breakBefore=true;score=0.62;reason="boundary_fragment_adjacent_region_continuity_ambiguous";}
      }else if(isRegionMode(unit)){breakBefore=unit.explicitBoundaryBefore;score=0.96;}
      else if(unit.explicitBoundaryBefore){breakBefore=true;score=0.98;}
      else{
        const indentThreshold=pageWidth?Math.max(8,pageWidth*0.015):16;
        const indented=typeof baselineX==="number"&&typeof unit.x==="number"&&unit.x>baselineX+indentThreshold;
        let largeGap=false;
        if(typeof previousUnit.y==="number"&&typeof previousUnit.height==="number"&&typeof unit.y==="number"&&typeof medianGap==="number"){
          const gap=unit.y-(previousUnit.y+previousUnit.height); largeGap=gap>Math.max(4,medianGap*1.6);
        }
        if(indented||largeGap){breakBefore=true;score=indented&&largeGap?0.99:0.94;}
        else if(startsQuote(unit.text)&&terminal(previousUnit.text)){breakBefore=true;score=0.72;reason="dialogue_paragraph_boundary_inferred_without_layout_signal";}
        else{breakBefore=false;score=unit.sourceMode==="page_text"?0.58:0.82;if(unit.sourceMode==="page_text")reason="physical_line_joined_without_layout_coordinates";}
      }
      if(breakBefore&&current?.text)drafts.push(current);
      if(breakBefore||!current)current=newDraft("paragraph");
      if(boundaryAdjudication)current.readingAdjudicationIds.add(boundaryAdjudication.id);
      addUnit(current,unit); current.structuralScores.push(score); if(reason)current.reviewReasons.add(reason); previousUnit=unit;
    }
  }
  if(current?.text)drafts.push(current);
  for(const a of (packet.reading_adjudications??[]).filter((x)=>x.adjudication_kind==="paragraph_continuity"&&x.result!=="unresolved")){
    const survives=surfaceUnits.some((units)=>units.some((u)=>unitContainsAnchor(packet,u,a.start_observation_id)))&&
      surfaceUnits.some((units)=>units.some((u)=>a.end_observation_id!==null&&unitContainsAnchor(packet,u,a.end_observation_id)));
    const count=usedContinuity.get(a.id)??0;
    if(survives&&count!==1)throw new Error(`Governed paragraph-continuity adjudication ${a.adjudication_key} was expected to apply exactly once; applied ${count} times`);
  }
  return drafts;
}
function inferPrefix(parentBlockKey:string){
  if(parentBlockKey.endsWith(":paragraph-stream"))return parentBlockKey.slice(0,-":paragraph-stream".length)+":paragraph";
  return `${parentBlockKey}:reconstructed`;
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return response(405,{error:"POST required"});
  const claims=decodeJwtPayload((req.headers.get("authorization")??"").replace(/^Bearer\s+/i,""));
  if(!claims||claims.role!=="service_role")return response(403,{error:"WNPH reading reconstruction currently requires service-role authorization"});
  try{
    const body=await req.json() as Record<string,unknown>;
    const sourcePackageKey=String(body.source_package_key??"").trim();
    const targetParentBlockKey=String(body.target_parent_block_key??"").trim();
    if(!sourcePackageKey||!targetParentBlockKey)return response(400,{error:"source_package_key and target_parent_block_key are required"});
    const assetKeys=Array.isArray(body.asset_keys)?body.asset_keys.map(String):null;
    const desiredState=body.proposed_reading_state==="usable"?"usable":"candidate";
    const allowUsableAutoAdmit=body.allow_usable_auto_admit===true;
    const packet=await rpc("wnph_reconstruction_source_packet_v6",{p_source_package_key:sourcePackageKey,p_target_parent_block_key:targetParentBlockKey,p_asset_keys:assetKeys}) as SourcePacket;
    if(packet.target_parent_block.semantic_role==="paragraph_stream"&&!packet.source_span){
      return response(422,{error:"A governed semantic source span is required before reconstructing a paragraph stream",source_package_key:sourcePackageKey,target_parent_block_key:targetParentBlockKey});
    }
    const drafts=buildDrafts(packet);
    if(!drafts.length)return response(422,{error:"No text-bearing observations were available inside the governed source span",source_package_key:sourcePackageKey});
    const prefix=String(body.proposed_block_key_prefix??inferPrefix(targetParentBlockKey));
    let ordinal=Number.isInteger(body.start_ordinal)?Number(body.start_ordinal):Number(packet.existing_max_ordinal??0)+1;
    const exclusionIds=[...governedReadingExclusions(packet)];
    const readingAdjudicationIds=(packet.reading_adjudications??[]).map((a)=>a.id);
    const sourceFingerprint=await sha256Hex(JSON.stringify({
      source_package_key:sourcePackageKey,target_parent_block_key:targetParentBlockKey,source_span:packet.source_span,
      asset_keys:packet.surfaces.map((s)=>s.asset_key),observation_ids:packet.surfaces.flatMap((s)=>s.observations.map((o)=>o.id)),
      observation_relation_ids:(packet.observation_relations??[]).map((r)=>r.id),
      observation_classification_ids:(packet.observation_classifications??[]).map((c)=>c.id),
      reading_adjudication_ids:readingAdjudicationIds,governed_reading_exclusion_ids:exclusionIds,algorithm:"deterministic-layout-v5"
    }));
    const reconstructionKey=String(body.reconstruction_key??`reconstruction:${sourceFingerprint.slice(0,24)}`);
    const proposals:Json[]=[]; let paragraphNo=ordinal; let headingNo=1;
    for(const draft of drafts){
      const structuralConfidence=draft.structuralScores.length?Math.min(...draft.structuralScores):0.5;
      const sourceConfidence=draft.sourceConfidences.length?Math.min(...draft.sourceConfidences):null;
      const reasons=new Set(draft.reviewReasons); const proposedReadingState=desiredState;
      if(draft.kind==="heading")reasons.add("heading_or_chapter_boundary_requires_parentage_review");
      if(desiredState==="usable"){
        const processors=new Set<string>();
        for(const surface of packet.surfaces){
          for(const obs of surface.observations){
            if(draft.observationIds.has(obs.id))processors.add(`${String(obs.processor?.provider??"")}:${String(obs.processor?.engine??"")}`);
          }
        }
        if(!allowUsableAutoAdmit||sourceConfidence===null||sourceConfidence<0.98||processors.size<2){
          reasons.add("usable_state_requires_high_confidence_multi_basis_or_explicit_override");
        }
      }
      const disposition=reasons.size===0&&draft.kind==="paragraph"?"auto_admit":"review";
      const blockOrdinal=ordinal++; let proposedBlockKey:string; let proposedBlockType:string; let proposedSemanticRole:string;
      if(draft.kind==="heading"){
        proposedBlockKey=`${prefix}:heading:${String(headingNo++).padStart(3,"0")}`; proposedBlockType="heading";
        proposedSemanticRole=/^(chapter)\b/i.test(draft.text)?"chapter_heading":"section_heading";
      }else{
        proposedBlockKey=`${prefix}:${String(paragraphNo++).padStart(3,"0")}`; proposedBlockType="paragraph"; proposedSemanticRole="body_paragraph";
      }
      const locators=dedupeLocators(draft.locators);
      const confidence=Math.max(0,Math.min(1,sourceConfidence===null?structuralConfidence:Math.min(structuralConfidence,sourceConfidence)));
      proposals.push({
        proposal_key:`${reconstructionKey}:${proposedBlockKey}`,target_parent_block_id:packet.target_parent_block.id,
        proposed_block_key:proposedBlockKey,proposed_ordinal:blockOrdinal,proposed_block_type:proposedBlockType,
        proposed_semantic_role:proposedSemanticRole,proposed_text_content:draft.text,proposed_reading_state:proposedReadingState,
        source_observation_ids:[...draft.observationIds],confidence,disposition,review_reasons:[...reasons],
        proposed_properties:{
          reconstruction_kind:draft.kind,reconstruction_source_modes:[...draft.sourceModes],source_surface_keys:[...draft.assetKeys],
          semantic_source_span_key:packet.source_span?.span_key??null,machine_structural_confidence:structuralConfidence,
          machine_source_confidence_floor:sourceConfidence,governed_page_furniture_exclusion_count:exclusionIds.length,
          governed_reading_adjudication_ids:[...draft.readingAdjudicationIds]
        },
        proposed_source_provenance:{
          text_authority:"machine_reconstruction_from_source_observations_with_governed_reading_adjudications",
          derivation_method:"deterministic_layout_reconstruction_v5",verification_status:"machine_derived_not_source_verified",
          source_locators:locators,governed_reading_adjudication_ids:[...draft.readingAdjudicationIds]
        },
        algorithm:{
          engine:"wnph-reading-reconstructor",version:"5",
          auto_admit_rule:"governed semantic source span is applied before reconstruction; coarse containers may fragment only through active source containment; only verified/adjudicated page-furniture classifications with reading_disposition=exclude may remove source observations; governed reading adjudications may replace semantic reading text or decide cross-surface paragraph continuity without rewriting source observations; candidate paragraphs auto-admit only when no structural review reason survives; headings always require parentage review; usable auto-admit additionally requires explicit override, confidence floor >=0.98, and at least two processor bases"
        }
      });
    }
    const appliedAdjudicationIds=[...new Set(drafts.flatMap((d)=>[...d.readingAdjudicationIds]))];
    const runMetadata:Json={
      worker:"wnph-reading-reconstructor",worker_version:5,source_packet_version:6,source_fingerprint_sha256:sourceFingerprint,
      semantic_source_span_key:packet.source_span?.span_key??null,selected_surface_count:packet.surfaces.length,
      observation_relation_count:(packet.observation_relations??[]).length,
      observation_classification_count:(packet.observation_classifications??[]).length,
      reading_adjudication_count:(packet.reading_adjudications??[]).length,
      applied_reading_adjudication_count:appliedAdjudicationIds.length,
      applied_reading_adjudication_ids:appliedAdjudicationIds,
      governed_reading_exclusion_count:exclusionIds.length,proposal_count:proposals.length,
      proposed_reading_state:desiredState,allow_usable_auto_admit:allowUsableAutoAdmit
    };
    const stats={
      total:proposals.length,auto_admit:proposals.filter((p)=>p.disposition==="auto_admit").length,
      review:proposals.filter((p)=>p.disposition==="review").length,
      headings:proposals.filter((p)=>p.proposed_block_type==="heading").length,
      paragraphs:proposals.filter((p)=>p.proposed_block_type==="paragraph").length,
      reading_adjudications_applied:appliedAdjudicationIds.length
    };
    if(body.dry_run===true)return response(200,{dry_run:true,reconstruction_key:reconstructionKey,stats,source_span:packet.source_span,run_metadata:runMetadata,proposals});
    const committed=await rpc("wnph_commit_reconstruction_batch_v1",{p_source_package_key:sourcePackageKey,p_reconstruction_key:reconstructionKey,p_proposals:proposals,p_run_metadata:runMetadata});
    return response(200,{ok:true,reconstruction_key:reconstructionKey,stats,source_span:packet.source_span,database:committed});
  }catch(e){ return response(500,{error:e instanceof Error?e.message:String(e)}); }
});
