const CACHE='aquabri-v4';

self.addEventListener('install',e=>{
  self.skipWaiting();
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys().then(ks=>Promise.all(
      ks.filter(k=>k!==CACHE).map(k=>caches.delete(k))
    ))
  );
  self.clients.claim();
});

self.addEventListener('fetch',e=>{
  const req=e.request;
  // Solo cachear GET — nunca POST (Supabase usa POST)
  if(req.method!=='GET')return;
  // No cachear Supabase
  if(req.url.includes('supabase.co'))return;
  // No cachear Google Maps API calls
  if(req.url.includes('maps.googleapis.com/maps/api'))return;
  // Cachear CDN estáticos (jsdelivr, fonts, etc)
  if(req.url.includes('jsdelivr.net')||req.url.includes('fonts.googleapis')||req.url.includes('fonts.gstatic')){
    e.respondWith(
      caches.open(CACHE).then(async c=>{
        const cached=await c.match(req);
        if(cached)return cached;
        const res=await fetch(req);
        if(res.ok)c.put(req,res.clone());
        return res;
      }).catch(()=>fetch(req))
    );
    return;
  }
  // Para todo lo demás: red primero, sin cachear
  e.respondWith(fetch(req).catch(()=>caches.match(req)));
});
