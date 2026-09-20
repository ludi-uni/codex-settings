// Exercises the installed pi CLI with an offline synthetic provider, never Devin.
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';

const pkg = process.argv[2] ?? join(process.env.APPDATA, 'npm/node_modules/@earendil-works/pi-coding-agent');
const providerId = process.argv[3] ?? 'devin';
const modelId = process.argv[4] ?? 'swe-2-high';
const fixture = mkdtempSync(join(tmpdir(), 'swe-loop-runtime-'));
const agentDir = join(fixture, 'agent');
mkdirSync(join(agentDir, 'extensions'), { recursive: true });
symlinkSync(fileURLToPath(new URL('../pi/extensions', import.meta.url)), join(agentDir, 'extensions/codex-settings'), 'junction');
const provider = join(fixture, 'fake-provider.ts');
writeFileSync(provider, `
import { createAssistantMessageEventStream } from '@earendil-works/pi-ai';
export default function(pi) {
  let calls = 0;
  pi.registerTool({name:'probe', label:'Probe', description:'Offline deterministic fixture',
    parameters:{type:'object',properties:{query:{type:'string'}},required:['query']},
    async execute() { return {content:[{type:'text',text:'no matches'}]}; }
  });
  pi.registerProvider(${JSON.stringify(providerId)}, {
    baseUrl:'http://127.0.0.1:1', apiKey:'offline-fixture', api:'swe-loop-fixture',
    models:[{id:${JSON.stringify(modelId)},name:'Offline loop fixture',reasoning:false,input:['text'],
      contextWindow:32768,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}],
    streamSimple(model) {
      const stream=createAssistantMessageEventStream();
      calls++;
      const message={role:'assistant',api:model.api,provider:model.provider,model:model.id,
        content:calls<=10 ? [{type:'toolCall',id:'fixture-'+calls,name:'probe',arguments:{query:['A','B','C'][(calls-1)%3]}}] : [{type:'text',text:'UNGUARDED_LIMIT'}],
        stopReason:calls<=10?'toolUse':'stop',timestamp:Date.now(),
        usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
      stream.push({type:'done',reason:message.stopReason,message}); stream.end();
      return stream;
    }
  });
}
`);
const run = spawnSync(process.execPath, [resolve(pkg, 'dist/bundle/cli.js'), '--offline', '--no-session', '--no-skills', '--no-context-files', '--no-approve', '-e', provider, '--provider', providerId, '--model', modelId, '--tools', 'probe', '--mode', 'json', '-p', 'Exercise the offline loop fixture'], {
  cwd: fixture, env: { ...process.env, PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1' },
  encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 2 ** 20,
});
assert.equal(run.error, undefined, run.error?.message);
const events = run.stdout.split(/\r?\n/).flatMap(line => { try { return [JSON.parse(line)]; } catch { return []; } });
writeFileSync(join(fixture, 'events.json'), JSON.stringify(events, null, 2));
assert.equal(run.status, 0, run.stderr);
assert.equal(events.filter(e => e.type === 'tool_execution_end').length, 7, `Expected 7 executions before abort. ${run.stderr}`);
assert(!run.stdout.includes('UNGUARDED_LIMIT'), 'Agent kept requesting after guard');
assert(run.stdout.includes('loop-guard'), 'Stop explanation not emitted');
console.log('PASS: actual pi CLI auto-discovered Junction extension, executed A/B/C twice + A, stopped at 7, displayed guard message; no network provider. Evidence: ' + fixture);
