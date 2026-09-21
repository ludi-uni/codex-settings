// Verify the official CLI and public extension/Skill contracts, not internal SDK modes.
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync,spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const repo=resolve(import.meta.dirname,'..');
const root=mkdtempSync(join(tmpdir(),'pi-native-runtime-'));
const agent=join(root,'agent'),project=join(root,'project');
mkdirSync(agent);mkdirSync(project);
writeFileSync(join(agent,'settings.json'),JSON.stringify({defaultProvider:'fixture',defaultModel:'fixture'}));
writeFileSync(join(agent,'auth.json'),'{}');
writeFileSync(join(project,'AGENTS.md'),'# Project\nPreserve the SENTINEL.');
const migration=spawnSync('pwsh',['-NoProfile','-File',join(repo,'scripts/migrate-pi-harness.ps1'),'-AgentDir',agent,'-ExternalSkillsRoot','','-NoActivate'],{encoding:'utf8',timeout:30000});
assert.equal(migration.status,0,migration.stdout+migration.stderr);
const ext=join(root,'fixture.ts');
writeFileSync(ext,`
import {createAssistantMessageEventStream} from '@earendil-works/pi-ai';
export default pi => pi.registerProvider('fixture',{
 api:'fixture-api',baseUrl:'http://127.0.0.1:1',apiKey:'fixture-only',
 models:[{id:'fixture',name:'Fixture',reasoning:false,input:['text'],contextWindow:32768,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}],
 streamSimple(model,context){ const s=createAssistantMessageEventStream();
 const ok=context.systemPrompt.includes('Progress rule')&&context.systemPrompt.includes('Preserve the SENTINEL')&&context.systemPrompt.includes('pi-workflow');
 const m={role:'assistant',api:model.api,provider:model.provider,model:model.id,content:[{type:'text',text:ok?'NATIVE_HARNESS_OK':'MISSING_CONTEXT'}],stopReason:'stop',timestamp:Date.now(),usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
 s.push({type:'done',reason:'stop',message:m});s.end();return s;
 }});
`);
const settings=JSON.parse(readFileSync(join(agent,'settings.json'),'utf8'));
settings.extensions=[ext];writeFileSync(join(agent,'settings.json'),JSON.stringify(settings));
const cli=join(process.env.APPDATA,'npm/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js');
const env={...process.env,PI_CODING_AGENT_DIR:agent,PI_OFFLINE:'1'};
const run=spawnSync(process.execPath,[cli,'--offline','--no-session','--no-approve','-p','Verify context.'],{cwd:project,env,encoding:'utf8',timeout:30000});
assert.equal(run.status,0,run.stderr);assert.match(run.stdout,/NATIVE_HARNESS_OK/);
const responses=await new Promise((resolveAll,reject)=>{
 const child=spawn(process.execPath,[cli,'--offline','--no-session','--no-approve','--mode','rpc'],{cwd:project,env,windowsHide:true});
 let buffer='',err='',done=false;const results=[];
 const timer=setTimeout(()=>finish(new Error('RPC timeout '+err)),30000);
 function finish(e){if(done)return;done=true;clearTimeout(timer);child.stdin.end();child.kill();e?reject(e):resolveAll(results);}
 child.on('error',finish);child.on('exit',code=>{if(!done)finish(new Error('RPC exited '+code+' '+err));});
 child.stderr.on('data',x=>err+=x);child.stdout.on('data',x=>{buffer+=x;let n;while((n=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,n);buffer=buffer.slice(n+1);let e;try{e=JSON.parse(line)}catch{continue}if(e.type==='response'){results.push(e);if(results.length===2)finish();}}});
 child.stdin.write('{"type":"get_state"}\n{"type":"get_commands"}\n');
});
assert(responses.every(r=>r.success));
assert(responses.find(r=>r.command==='get_commands').data.commands.some(c=>c.name==='skill:pi-workflow'));
assert.equal(readFileSync(join(agent,'auth.json'),'utf8'),'{}');
console.log('PASS: official pi CLI print/RPC, native AGENTS/Skill discovery, project instructions, and auth preservation');
