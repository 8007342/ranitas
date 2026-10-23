import {existsSync, mkdirSync, cpSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
function run(command,args){const r=spawnSync(command,args,{stdio:'inherit'});if(r.error)throw r.error;if(r.status!==0)process.exit(r.status??1);}
if(existsSync('pubspec.yaml')) {
 let flutter=process.env.FLUTTER_BIN || 'flutter';
 const probe=spawnSync(flutter,['--version'],{stdio:'ignore'});
 if(probe.error?.code==='ENOENT') {
   const sdk=resolve('.cache/flutter');
   if(!existsSync(`${sdk}/bin/flutter`))run('git',['clone','--depth','1','--branch','3.47.7','https://github.com/flutter/flutter.git',sdk]);
   flutter=`${sdk}/bin/flutter`;
 }
 run(flutter,['pub','get']);
 run(flutter,['build','web','--release','--no-web-resources-cdn']);
 run('node',['scripts/check-assets.mjs']);
} else {mkdirSync('build/web',{recursive:true});cpSync('landing','build/web',{recursive:true});}
