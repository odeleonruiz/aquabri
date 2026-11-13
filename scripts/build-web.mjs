import { mkdir, readdir, copyFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
const root=process.cwd(),out=join(root,'www');
const qaMode=process.env.AQUABRI_BUILD_TARGET==='qa';
await rm(out,{recursive:true,force:true});
await mkdir(out,{recursive:true});
const excluded=new Set(['.git','.github','node_modules','android','ios','www','scripts','.vscode']);
const allowed=new Set(['.html','.css','.js','.mjs','.json','.png','.jpg','.jpeg','.webp','.svg','.ico','.woff','.woff2','.ttf','.webmanifest']);
const recursive=async (from,to,depth=0)=>{
  if(depth>8)return;
  for(const ent of await readdir(from,{withFileTypes:true})){
    if(excluded.has(ent.name)||ent.name.startsWith('.'))continue;
    if(qaMode && depth===0){
      // Never package the production auxiliary pages or staging/admin tools.
      const files=new Set(['index.html','manifest.json','sw.js','icon-192.png','icon-512.png']);
      const dirs=new Set(['js','vendor']);
      if(ent.isDirectory()? !dirs.has(ent.name): !files.has(ent.name))continue;
    }
    const src=join(from,ent.name),dest=join(to,ent.name);
    if(ent.isDirectory()){await mkdir(dest,{recursive:true});await recursive(src,dest,depth+1);}
    else if(ent.isFile() && allowed.has(ent.name.slice(ent.name.lastIndexOf('.')).toLowerCase()) && !['package.json','package-lock.json','capacitor.config.json'].includes(ent.name)){
      await copyFile(src,dest);
    }
  }
};
await recursive(root,out);
// QA builds use ONLY the isolated frontend, which points at Supabase staging.
// Default behavior remains the exact existing production frontend.
if(qaMode){
  const qaSource=join(root,'qa-seguridad','index.html');
  await copyFile(qaSource,join(out,'index.html'));
  const {readFile}=await import('node:fs/promises');
  const qaHtml=await readFile(join(out,'index.html'),'utf8');
  if(!qaHtml.includes("const SURL='https://xzbawbkstaqvkwtqlqai.supabase.co'")){
    throw new Error('QA build aborted: staging Supabase URL is absent.');
  }
  // Examine EVERY packaged text asset, not only the entrypoint.
  const verify=async dir=>{
    for(const ent of await readdir(dir,{withFileTypes:true})){
      const pathname=join(dir,ent.name);
      if(ent.isDirectory()){await verify(pathname);continue;}
      if(!ent.isFile()||!['.html','.js','.mjs','.json','.webmanifest'].some(ext=>ent.name.endsWith(ext)))continue;
      if((await readFile(pathname,'utf8')).includes('odwccqqvxpsggggehjtt')){
        throw new Error('QA build aborted: production Supabase reference found in '+pathname);
      }
    }
  };
  await verify(out);
  console.log('AQUABRI QA: isolated staging frontend selected.');
}else if(process.env.AQUABRI_BUILD_TARGET && process.env.AQUABRI_BUILD_TARGET!=='production'){
  throw new Error('Unsupported AQUABRI_BUILD_TARGET.');
}
console.log('AQUABRI web assets copied to www for Capacitor.');
