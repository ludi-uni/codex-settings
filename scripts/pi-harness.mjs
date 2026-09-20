// Thin host for installed pi 0.85.1 SDK/modes. No credential or provider reimplementation.
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { spawn } from 'node:child_process';

// Preserve native package-management and extension-free helper contracts used by pi-web.
// Use the absolute upstream entry point, never `pi` through our own PATH shim.
async function runNativeIfRequested(argv) {
  const args = [...argv];
  const index = args.indexOf('--profile');
  const profile = index < 0 ? join(homedir(), '.pi/profiles/compact') : args[index + 1];
  if (index >= 0) args.splice(index, 2);
  const management = ['install', 'remove', 'uninstall', 'update', 'list', 'config', 'auth'];
  if (!management.includes(args[0]) && !args.includes('--no-extensions') && !args.includes('-ne')) return false;
  const manifest = JSON.parse(readFileSync(join(profile, 'harness.json'), 'utf8'));
  if (manifest.schema !== 'codex-settings.pi-harness.v1') throw new Error('Invalid harness profile');
  process.exitCode = await new Promise((resolveExit, reject) => {
    const child = spawn(process.execPath, [join(manifest.piPackageRoot, 'dist/bundle/cli.js'), ...args], {
      stdio: 'inherit', windowsHide: true,
      env: { ...process.env, PI_CODING_AGENT_DIR: manifest.sourceAgentDir },
    });
    child.on('error', reject);
    child.on('exit', code => resolveExit(code ?? 1));
  });
  return true;
}

export async function createHarness(options = {}) {
  const profile = resolve(options.profile ?? join(homedir(), '.pi/profiles/compact'));
  const manifest = JSON.parse(readFileSync(join(profile, 'harness.json'), 'utf8').replace(/^\uFEFF/, ''));
  if (manifest.schema !== 'codex-settings.pi-harness.v1' || resolve(manifest.profileDir) !== profile) throw new Error('Invalid harness profile; run migrate-pi-harness.ps1.');
  const pkg = manifest.piPackageRoot;
  const version = JSON.parse(readFileSync(join(pkg, 'package.json'), 'utf8')).version;
  if (version !== '0.85.1') throw new Error(`Harness SDK compatibility is verified for pi 0.85.1; found ${version}. Validate the SDK before upgrading this adapter.`);
  // Set before importing pi: package-level default directories and child agents use this profile.
  process.env.PI_CODING_AGENT_DIR = profile;
  if (options.offline || options.inspect) process.env.PI_OFFLINE = '1';
  const module = rel => import(pathToFileURL(join(pkg, 'dist', rel)));
  const { ModelRuntime } = await module('core/model-runtime.js');
  const { SettingsManager } = await module('core/settings-manager.js');
  const { SessionManager, getDefaultSessionDir } = await module('core/session-manager.js');
  const { createAgentSessionRuntime, createAgentSessionServices, createAgentSessionFromServices } = await module('core/agent-session-runtime.js');
  const source = manifest.sourceAgentDir;
  // Use the same auth path and lock as ordinary pi; never make a second file alias.
  const authFile = join(source, 'auth.json');
  const authPath = existsSync(authFile) ? realpathSync(authFile) : authFile;
  const initialCwd = resolve(options.cwd ?? process.cwd());
  const workflowFiles = { code: 'code-investigation-and-fix.md', review: 'review.md', visual: 'visual-work.md', research: 'research.md' };
  if (options.workflow && !workflowFiles[options.workflow]) throw new Error('Unknown workflow; choose code, review, visual or research');
  const workflow = options.workflow ? readFileSync(join(profile, 'skills/pi-workflow/references', workflowFiles[options.workflow]), 'utf8') : undefined;
  const sessionDir = getDefaultSessionDir(initialCwd, profile);
  const sessions = options.session ? SessionManager.open(resolve(options.session), sessionDir)
    : options.noSession || options.inspect || options.mode === 'rpc' ? SessionManager.inMemory(initialCwd)
    : options.continue ? SessionManager.continueRecent(initialCwd, sessionDir)
    : SessionManager.create(initialCwd, sessionDir);
  const factory = async ({ cwd, agentDir, sessionManager, sessionStartEvent }) => {
    // Rebuild registrations per cwd/session replacement; no stale project providers.
    const modelRuntime = await ModelRuntime.create({ authPath,
      modelsPath: join(source, 'models.json'), modelsStorePath: join(profile, 'models-store.json'),
      allowModelNetwork: false, refreshOnCreate: false });
    // Candidate resources stay explicit. Project AGENTS remain readable; project
    // extensions/settings require --approve for this run, independently of baseline trust.
    const settingsManager = SettingsManager.create(cwd, agentDir, { projectTrusted: options.approve === true });
    const services = await createAgentSessionServices({ cwd, agentDir, settingsManager, modelRuntime,
      resourceLoaderOptions: { additionalExtensionPaths: (options.extension ?? []).map(p => resolve(p)),
        appendSystemPrompt: workflow ? [workflow] : [], noContextFiles: options.noContextFiles,
        systemPrompt: options.systemPrompt } });
    const loader = services.resourceLoader;
    const diagnostics = [...services.diagnostics,
      ...loader.getExtensions().errors.map(e => ({ type: 'error', message: `Extension load failed: ${e.path}: ${e.error}` })),
      ...loader.getSkills().diagnostics.map(d => ({ type: 'warning', message: String(d.message) }))];
    if (diagnostics.some(d => d.type === 'error')) throw new Error(diagnostics.map(d => d.message).join('\n'));
    const restored = sessionManager.buildSessionContext().model;
    const provider = options.provider ?? restored?.provider ?? settingsManager.getDefaultProvider();
    const modelId = options.model ?? restored?.modelId ?? settingsManager.getDefaultModel();
    const model = modelRuntime.getModel(provider, modelId);
    if (!model) throw new Error(`Configured model ${provider}/${modelId} is unavailable. Add its provider extension explicitly; no automatic fallback is performed.`);
    const created = await createAgentSessionFromServices({ services, sessionManager, sessionStartEvent,
      model, thinkingLevel: options.thinking,
      noTools: options.noTools ? 'all' : options.noBuiltinTools ? 'builtin' : undefined,
      tools: options.tools ? options.tools.split(',') : options.noTools || options.noBuiltinTools ? undefined : settingsManager.getDefaultTools() });
    return { ...created, services, diagnostics };
  };
  const runtime = await createAgentSessionRuntime(factory, { cwd: sessions.getCwd(), agentDir: profile, sessionManager: sessions });
  return { runtime, module, manifest, version };
}

export function inspectHarness({ runtime, manifest, version }) {
  const { session, services } = runtime;
  const loader = services.resourceLoader;
  const active = session.getActiveToolNames();
  const activeSchemas = session.getAllTools().filter(t => active.includes(t.name));
  return { version, profile: manifest.profileDir, sourceAgentDir: manifest.sourceAgentDir,
    model: `${session.model?.provider}/${session.model?.id}`,
    authConfigured: services.modelRuntime.hasConfiguredAuth(session.model.provider),
    tools: active, skills: loader.getSkills().skills.map(s => ({ name: s.name, path: s.filePath })),
    contextFiles: loader.getAgentsFiles().agentsFiles.map(f => ({ path: f.path, characters: f.content.length })),
    extensions: loader.getExtensions().extensions.map(e => e.path),
    systemPromptCharacters: session.systemPrompt.length,
    activeToolDefinitionCharacters: JSON.stringify(activeSchemas).length,
    diagnostics: runtime.diagnostics, inferenceRequests: 0 };
}

async function main() {
  if (await runNativeIfRequested(process.argv.slice(2))) return;
  const { values: v, positionals } = parseArgs({ allowPositionals: true, options: {
    profile: { type: 'string' }, mode: { type: 'string' }, print: { type: 'boolean', short: 'p' },
    workflow: { type: 'string' },
    provider: { type: 'string' }, model: { type: 'string' }, thinking: { type: 'string' },
    session: { type: 'string' }, continue: { type: 'boolean', short: 'c' },
    'no-session': { type: 'boolean' }, offline: { type: 'boolean' }, inspect: { type: 'boolean' },
    'no-tools': { type: 'boolean' }, 'no-builtin-tools': { type: 'boolean' },
    'no-context-files': { type: 'boolean' }, 'system-prompt': { type: 'string' },
    approve: { type: 'boolean' }, 'no-approve': { type: 'boolean' },
    extension: { type: 'string', multiple: true, short: 'e' }, tools: { type: 'string' },
    help: { type: 'boolean', short: 'h' },
  } });
  if (v.help) {
    console.log('pi compact harness (pi 0.85.1)\n--profile PATH  --inspect  --offline  -p PROMPT  --mode text|json|rpc\n--workflow code|review|visual|research (preload exactly one workflow)\n--provider ID --model ID --thinking LEVEL --tools read,powershell,edit,write\n--session PATH | --continue | --no-session  --approve  -e EXTENSION\nDefault: native interactive pi TUI. Project AGENTS load; project executable resources require --approve.\nUses baseline auth/model definitions directly; no API keys accepted on the command line.');
    return;
  }
  if (v.mode && !['text', 'json', 'rpc'].includes(v.mode)) throw new Error('Unsupported --mode');
  if (v.session && (v.continue || v['no-session'])) throw new Error('Choose one session mode');
  if (v.approve && v['no-approve']) throw new Error('Conflicting project trust flags');
  if (v.model) {
    const thinking = v.model.match(/:(off|minimal|low|medium|high|xhigh|max)$/);
    if (thinking) { v.thinking ??= thinking[1]; v.model = v.model.slice(0, -thinking[0].length); }
    const slash = v.model.indexOf('/');
    if (slash >= 0) {
      const provider = v.model.slice(0, slash);
      if (v.provider && v.provider !== provider) throw new Error('Conflicting provider and qualified model');
      v.provider = provider; v.model = v.model.slice(slash + 1);
    }
  }
  const created = await createHarness({ ...v, noSession: v['no-session'], noTools: v['no-tools'],
    noBuiltinTools: v['no-builtin-tools'], noContextFiles: v['no-context-files'], systemPrompt: v['system-prompt'] });
  const { runtime, module } = created;
  const { initTheme, stopThemeWatcher } = await module('modes/interactive/theme/theme.js');
  initTheme(runtime.services.settingsManager.getTheme() ?? 'dark', false);
  try {
    if (v.inspect) { console.log(JSON.stringify(inspectHarness(created), null, 2)); return; }
    const { InteractiveMode, runPrintMode, runRpcMode } = await module('modes/index.js');
    if (v.mode === 'rpc') { await runRpcMode(runtime); return; }
    if (v.print || v.mode === 'json' || v.mode === 'text') {
      if (!positionals.length) throw new Error('Print mode requires a prompt');
      process.exitCode = await runPrintMode(runtime, { mode: v.mode === 'json' ? 'json' : 'text', initialMessage: positionals.join(' ') });
    } else {
      if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('Interactive mode requires a terminal; use --mode rpc or -p.');
      await new InteractiveMode(runtime, { initialMessage: positionals.join(' ') || undefined,
        startupDiagnostics: runtime.diagnostics, modelFallbackMessage: runtime.modelFallbackMessage }).run();
    }
  } finally { await runtime.dispose(); stopThemeWatcher(); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
