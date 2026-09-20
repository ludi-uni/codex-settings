// Read-only resource and real CLI/RPC startup check. Never sends an LLM prompt.
import { readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const [pkg, agentDir] = process.argv.slice(2);
process.env.PI_OFFLINE = '1';
process.env.PI_CODING_AGENT_DIR = agentDir;
const { DefaultResourceLoader } = await import(pathToFileURL(join(pkg, 'dist/core/resource-loader.js')));
const { SettingsManager } = await import(pathToFileURL(join(pkg, 'dist/core/settings-manager.js')));
const settingsManager = SettingsManager.create(process.cwd(), agentDir);
const loader = new DefaultResourceLoader({ cwd: process.cwd(), agentDir, settingsManager });
await loader.reload();
const { skills, diagnostics } = loader.getSkills();
const state = JSON.parse(readFileSync(join(agentDir, 'codex-settings/pi.json'), 'utf8'));
const expected = ['visual-verification', 'project-management'];
if (state.links['skills/rigging']) expected.push('2d-rigging-knowledge', 'live2d-rigging-skill');
for (const name of expected) assert(skills.some(s => s.name === name), `Missing skill: ${name}`);
assert.equal(diagnostics.length, 0, JSON.stringify(diagnostics));
assert.equal(loader.getExtensions().errors.length, 0, 'Extension load errors');
const context = loader.getAgentsFiles().agentsFiles.find(f => realpathSync(f.path) === realpathSync(join(agentDir, 'AGENTS.md')));
assert(context?.content.includes('## Pi native Windows adapter'), 'Global AGENTS adapter missing');
assert(!context.content.includes('## Multi-agent routing'), 'Codex routing included');

const responses = await new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [join(pkg, 'dist/bundle/cli.js'), '--mode', 'rpc', '--offline', '--no-session', '--no-approve'], {
    cwd: process.cwd(), env: process.env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
  });
  let buffer = '', errors = '', done = false;
  const result = {};
  const finish = error => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    child.stdin.end();
    child.kill();
    if (error) reject(error); else resolve(result);
  };
  const timer = setTimeout(() => finish(new Error(`pi RPC timed out: ${errors.slice(-1000)}`)), 30000);
  child.on('error', finish);
  child.on('exit', code => { if (!done) finish(new Error(`pi exited early (${code}): ${errors.slice(-1000)}`)); });
  child.stderr.on('data', chunk => { errors += chunk; });
  child.stdout.on('data', chunk => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
      let event;
      try { event = JSON.parse(line); } catch { continue; }
      if (event.type !== 'response' || !['get_commands', 'get_state'].includes(event.command)) continue;
      if (!event.success) return finish(new Error(`RPC failed: ${event.command}`));
      result[event.command] = event.data;
      if (result.get_commands && result.get_state) finish();
    }
  });
  child.stdin.on('error', finish);
  child.stdin.write('{"id":"skills","type":"get_commands"}\n{"id":"state","type":"get_state"}\n');
});
for (const name of expected) assert(responses.get_commands.commands.some(c => c.name === `skill:${name}`), `CLI missing skill command: ${name}`);
console.log(JSON.stringify({
  result: 'PASS', version: JSON.parse(readFileSync(join(pkg, 'package.json'))).version,
  agentDir, context: context.path, skills: skills.map(s => ({ name: s.name, path: s.filePath })),
  diagnostics, model: responses.get_state.model?.id, provider: responses.get_state.model?.provider,
  inferenceRequests: 0,
}, null, 2));
