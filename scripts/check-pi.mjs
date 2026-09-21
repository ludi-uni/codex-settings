// Read-only resource and real CLI/RPC startup check. Never sends an LLM prompt.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const [pkg, agentDir] = process.argv.slice(2);
process.env.PI_OFFLINE = '1';
process.env.PI_CODING_AGENT_DIR = agentDir;
const packageInfo = JSON.parse(readFileSync(join(pkg, 'package.json'), 'utf8'));
const cli = join(pkg, typeof packageInfo.bin === 'string' ? packageInfo.bin : packageInfo.bin.pi);
const state = JSON.parse(readFileSync(join(agentDir, 'codex-settings/pi.json'), 'utf8'));
const expected = ['visual-verification', 'project-management'];
for (const [relative, target] of Object.entries(state.links ?? {})) {
  if (!relative.startsWith('skills/') || relative === 'skills/pi-workflow') continue;
  if (expected.some(name => relative === `skills/${name}`)) continue;
  for (const entry of readdirSync(target, { withFileTypes: true })) {
    if (entry.isDirectory() && existsSync(join(target, entry.name, 'SKILL.md'))) expected.push(entry.name);
  }
}
if (existsSync(join(agentDir, 'skills/pi-workflow/SKILL.md'))) expected.push('pi-workflow');
const context = readFileSync(join(agentDir, 'AGENTS.md'), 'utf8');
assert(context.includes('Progress rule'), 'Global AGENTS policy missing');
assert(!context.includes('## Multi-agent routing'), 'Codex routing included');

const responses = await new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [cli, '--mode', 'rpc', '--offline', '--no-session', '--no-approve'], {
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
  result: 'PASS', version: packageInfo.version,
  agentDir, contextFile: join(agentDir, 'AGENTS.md'),
  skills: responses.get_commands.commands.filter(c => c.source === 'skill').map(c => c.name),
  model: responses.get_state.model?.id, provider: responses.get_state.model?.provider,
  inferenceRequests: 0,
}, null, 2));
