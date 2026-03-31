// Aquabri Service Worker v1.0
const CACHE = 'aquabri-v1';
const OFFLINE_ASSETS = ['/'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(OFFLINE_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  // Solo cachear requests GET
  if (e.request.method !== 'GET') return;
  // No cachear Supabase ni Google Maps (datos en tiempo real)
  const url = e.request.url;
  if (url.includes('supabase.co') || url.includes('googleapis.com') || url.includes('google.com')) return;
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(cache => cache.put(e.request, clone));
        return res;
      })
      .catch(() => caches.match(e.request).then(r => r || caches.match('/')))
  );
});
