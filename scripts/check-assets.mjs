import {readdirSync,statSync,existsSync} from 'node:fs';
import {join} from 'node:path';
const root=existsSync('build/web')?'build/web':'assets';let count=0,total=0;
function visit(dir){for(const name of readdirSync(dir)){const p=join(dir,name),s=statSync(p);if(s.isDirectory())visit(p);else {count++;total+=s.size;if(s.size>25*1024*1024)throw new Error(`${p} exceeds Cloudflare's 25 MiB per-asset limit`);}}}
visit(root);if(count>20000)throw new Error('Exceeds conservative 20,000 static asset budget');console.log(`${count} files, ${(total/1024/1024).toFixed(2)} MiB; every asset below 25 MiB.`);
