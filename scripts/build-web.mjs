import { mkdir, readdir, copyFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
const root=process.cwd(),out=join(root,'www');
await rm(out,{recursive:true,force:true});
await mkdir(out,{recursive:true});
const excluded=new Set(['.git','.github','node_modules','android','ios','www','scripts','.vscode']);
const allowed=new Set(['.html','.css','.js','.mjs','.json','.png','.jpg','.jpeg','.webp','.svg','.ico','.woff','.woff2','.ttf','.webmanifest']);
const recursive=async (from,to,depth=0)=>{
  if(depth>8)return;
  for(const ent of await readdir(from,{withFileTypes:true})){
    if(excluded.has(ent.name)||ent.name.startsWith('.'))continue;
    const src=join(from,ent.name),dest=join(to,ent.name);
    if(ent.isDirectory()){await mkdir(dest,{recursive:true});await recursive(src,dest,depth+1);}
    else if(ent.isFile() && allowed.has(ent.name.slice(ent.name.lastIndexOf('.')).toLowerCase()) && !['package.json','package-lock.json','capacitor.config.json'].includes(ent.name)){
      await copyFile(src,dest);
    }
  }
};
await recursive(root,out);
console.log('AQUABRI web assets copied to www for Capacitor.');
