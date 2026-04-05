const CACHE='aquabri-v3';
const STATIC=[
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://maps.googleapis.com/maps/api/js',
];
self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll([])));
  self.skipWaiting();
});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch',e=>{
  const url=e.request.url;
  // No cachear Supabase (datos en tiempo real)
  if(url.includes('supabase.co'))return;
  // Cachear CDN estáticos
  if(url.includes('jsdelivr.net')||url.includes('googleapis.com')){
    e.respondWith(caches.open(CACHE).then(async c=>{
      const cached=await c.match(e.request);
      if(cached)return cached;
      const res=await fetch(e.request);
      c.put(e.request,res.clone());
      return res;
    }).catch(()=>fetch(e.request)));
    return;
  }
  // index.html: siempre red primero
  e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)));
});
