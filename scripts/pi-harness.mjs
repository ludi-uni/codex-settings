// Compatibility launcher only: all execution is delegated to the official pi CLI.
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {spawn} from 'node:child_process';
const args=process.argv.slice(2);
let source=join(homedir(),'.pi/agent');
let pkg=join(process.env.APPDATA,'npm/node_modules/@earendil-works/pi-coding-agent');
const profileIndex=args.indexOf('--profile');
if(profileIndex>=0) {
 const manifest=JSON.parse(readFileSync(join(args[profileIndex+1],'harness.json'),'utf8'));
 source=manifest.sourceAgentDir;pkg=manifest.piPackageRoot;args.splice(profileIndex,2);
}
const workflowIndex=args.indexOf('--workflow');
if(workflowIndex>=0) {
 const routes={code:'code-investigation-and-fix',review:'review',visual:'visual-work',research:'research'};
 const file=routes[args[workflowIndex+1]];
 if(!file) throw new Error('Workflow must be code, review, visual or research');
 args.splice(workflowIndex,2,'--append-system-prompt',resolve(import.meta.dirname,'../pi/harness/skills/pi-workflow/references',file+'.md'));
}
if(args.includes('--inspect')) throw new Error('Use scripts/check-pi.ps1 to inspect official pi resource loading.');
const info=JSON.parse(readFileSync(join(pkg,'package.json'),'utf8'));
const child=spawn(process.execPath,[join(pkg,typeof info.bin==='string'?info.bin:info.bin.pi),...args],{stdio:'inherit',windowsHide:true,env:{...process.env,PI_CODING_AGENT_DIR:source}});
child.on('error',error=>{console.error(error.message);process.exitCode=1;});
child.on('exit',code=>{process.exitCode=code??1;});
