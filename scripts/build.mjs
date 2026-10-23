import {existsSync, mkdirSync, cpSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(existsSync('pubspec.yaml')) {
 const r=spawnSync('flutter',['build','web','--release','--no-web-resources-cdn'],{stdio:'inherit'});
 if(r.status!==0) process.exit(r.status??1);
} else {mkdirSync('build/web',{recursive:true});cpSync('landing','build/web',{recursive:true});}
