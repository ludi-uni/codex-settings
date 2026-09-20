// No network/LLM: exercise the actual installed pi SDK and RPC modes with fake credentials.
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync, spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const repo = resolve(import.meta.dirname, '..');
const root = mkdtempSync(join(tmpdir(), 'pi-compact-runtime-'));
const baseline = join(root, 'baseline'), profile = join(root, 'candidate'), project = join(root, 'project');
for (const path of [baseline, project]) mkdirSync(path);
writeFileSync(join(baseline, 'settings.json'), JSON.stringify({ defaultProvider: 'offline-fixture', defaultModel: 'fixture', packages: ['do-not-load'] }));
writeFileSync(join(baseline, 'auth.json'), '{}');
writeFileSync(join(project, 'AGENTS.md'), '# Local project rule\nPreserve the SENTINEL file.');
const extension = join(root, 'fixture.ts');
writeFileSync(extension, `
import {createAssistantMessageEventStream} from '@earendil-works/pi-ai';
export default pi => pi.registerProvider('offline-fixture', {
 api:'compact-fixture',baseUrl:'http://127.0.0.1:1',apiKey:'fake-no-network',
 models:[{id:'fixture',name:'Fixture',reasoning:false,input:['text'],contextWindow:32768,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}],
 streamSimple(model, context) {
  const s=createAssistantMessageEventStream();
  const valid=context.systemPrompt.includes('Progress rule') && context.systemPrompt.includes('Preserve the SENTINEL');
  const m={role:'assistant',api:model.api,provider:model.provider,model:model.id,
   content:[{type:'text',text:valid ? (context.systemPrompt.includes('Report findings first') && !context.systemPrompt.includes('Reproduce or locate the reported behavior') ? 'REVIEW_ONLY_OK' : 'HARNESS_CONTEXT_OK') : 'MISSING_CONTEXT'}],stopReason:'stop',timestamp:Date.now(),
   usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
  s.push({type:'done',reason:'stop',message:m});s.end();return s;
 }
});
`);
const setup = spawnSync('pwsh', ['-NoProfile', '-File', join(repo, 'scripts/migrate-pi-harness.ps1'), '-SourceAgentDir', baseline, '-ProfileDir', profile, '-RiggingSkillsRoot', '', '-ExtraExtension', extension], { encoding: 'utf8', timeout: 30000 });
assert.equal(setup.status, 0, setup.stderr + setup.stdout);
const cli = join(repo, 'scripts/pi-harness.mjs');
function run(args) {
  const r = spawnSync(process.execPath, [cli, '--profile', profile, '--offline', ...args], { cwd: project, encoding: 'utf8', timeout: 30000 });
  assert.equal(r.error, undefined, r.error?.message);
  assert.equal(r.status, 0, r.stderr + r.stdout);
  return r.stdout;
}
const inspection = JSON.parse(run(['--inspect']));
assert.equal(run(['--version']).trim(), '0.85.1');
const qualified = JSON.parse(run(['--inspect', '--model', 'offline-fixture/fixture:off']));
assert.equal(qualified.model, 'offline-fixture/fixture');
const toolLess = JSON.parse(run(['--inspect', '--no-tools', '--no-context-files', '--system-prompt', 'title helper']));
assert.equal(toolLess.tools.length, 0);
assert.equal(toolLess.contextFiles.length, 0);
assert.deepEqual(inspection.tools, ['read', 'powershell', 'edit', 'write']);
assert(inspection.skills.some(s => s.name === 'pi-workflow'));
assert(inspection.contextFiles.some(f => f.path === join(project, 'AGENTS.md')));
assert.equal(inspection.diagnostics.length, 0);
assert.equal(inspection.extensions.length, 2); // explicit fixture provider and shared guard
assert.match(run(['--no-session', '-p', 'Check context only']), /HARNESS_CONTEXT_OK/);
assert.match(run(['--no-session', '--workflow', 'review', '-p', 'Check selected workflow']), /REVIEW_ONLY_OK/);
// Unknown model must fail instead of silently switching to a cloud/local default.
const wrong = spawnSync(process.execPath, [cli, '--profile', profile, '--offline', '--model', 'missing', '--inspect'], { cwd: project, encoding: 'utf8', timeout: 30000 });
assert.notEqual(wrong.status, 0);
assert.match(wrong.stderr, /no automatic fallback/);

const events = await new Promise((resolveEvents, reject) => {
  const child = spawn(process.execPath, [cli, '--profile', profile, '--offline', '--mode', 'rpc', '--no-session'], { cwd: project, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let buffer = '', stderr = '', done = false;
  const responses = [];
  const timer = setTimeout(() => finish(new Error('RPC timeout: ' + stderr)), 30000);
  function finish(error) { if (done) return; done = true; clearTimeout(timer); child.stdin.end(); child.kill(); if (error) reject(error); else resolveEvents(responses); }
  child.on('error', finish);
  child.on('exit', code => { if (!done) finish(new Error(`RPC exited ${code}: ${stderr}`)); });
  child.stderr.on('data', x => { stderr += x; });
  child.stdout.on('data', chunk => {
    buffer += chunk;
    let i;
    while ((i = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, i); buffer = buffer.slice(i + 1);
      let e; try { e = JSON.parse(line); } catch { continue; }
      if (e.type !== 'response') continue;
      responses.push(e);
      if (e.id === 'commands') child.stdin.write('{"type":"new_session","id":"new"}\n');
      if (e.id === 'new') child.stdin.write('{"type":"get_state","id":"new-state"}\n');
      if (e.id === 'new-state') finish();
    }
  });
  child.stdin.write('{"type":"get_state","id":"state"}\n{"type":"get_commands","id":"commands"}\n');
});
assert(events.every(e => e.success), JSON.stringify(events));
assert.equal(events.find(e => e.command === 'get_state').data.model.id, 'fixture');
assert(events.find(e => e.command === 'get_commands').data.commands.some(c => c.name === 'skill:pi-workflow'));
assert.equal(events.find(e => e.id === 'new-state').data.model.id, 'fixture');
assert.equal(readFileSync(join(baseline, 'auth.json'), 'utf8'), '{}');
assert(!existsSync(join(profile, 'auth.json')), 'Candidate must not create a second credential file');
// pi-web helper flags and management route through the absolute native entry point.
writeFileSync(join(baseline, 'models.json'), JSON.stringify({providers:{'offline-native':{baseUrl:'http://127.0.0.1:1/v1',api:'openai-completions',apiKey:'fixture',models:[{id:'fixture'}]}}}));
assert.match(run(['--no-extensions', '--no-tools', '--no-context-files', '--no-session', '--model', 'offline-native/fixture', '--list-models', 'offline-native']), /offline-native/);
console.log(JSON.stringify({ result: 'PASS', profile, tools: inspection.tools, systemPromptCharacters: inspection.systemPromptCharacters, checks: ['discovery', 'project instructions', 'print', 'RPC/session replacement', 'missing-model refusal', 'auth preservation'] }, null, 2));
