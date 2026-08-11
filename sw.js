// ============================================================
// Pickup – Service Worker (Network-First)
//
// Strategie: Immer zuerst das Netzwerk fragen. Nur wenn keine
// Verbindung besteht, wird auf den Cache zurückgegriffen.
// Dadurch sehen alle Nutzer neue Deployments sofort — ohne
// dass die CACHE-Version manuell hochgezählt werden muss.
// ============================================================

const CACHE = 'pickup-runtime';
const FALLBACK_ASSETS = ['/', '/index.html', '/manifest.json', '/icon.svg'];

// ---- Installation: Grundgerüst für Offline-Fall vorladen ----
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(FALLBACK_ASSETS))
  );
  // Sofort aktiv werden, nicht auf Schließen aller Tabs warten
  self.skipWaiting();
});

// ---- Aktivierung: alte Caches aufräumen ----
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// ---- Fetch: Network-First mit Cache-Fallback ----
self.addEventListener('fetch', event => {
  const req = event.request;

  // Nur GET-Requests behandeln
  if (req.method !== 'GET') return;

  // Fremde Domains (Supabase, Google Fonts, CDN) durchreichen
  if (!req.url.startsWith(self.location.origin)) return;

  // Supabase-Aufrufe niemals cachen
  if (req.url.includes('supabase.co')) return;

  event.respondWith(
    fetch(req)
      .then(response => {
        // Erfolgreiche Antwort im Hintergrund für Offline speichern
        if (response && response.ok && response.type === 'basic') {
          const copy = response.clone();
          caches.open(CACHE).then(cache => cache.put(req, copy));
        }
        return response;
      })
      .catch(() => {
        // Kein Netz → aus dem Cache bedienen
        return caches.match(req).then(cached => {
          if (cached) return cached;
          // Navigations-Anfragen auf die Startseite umleiten
          if (req.mode === 'navigate') return caches.match('/index.html');
          return new Response('Offline', {
            status: 503,
            statusText: 'Offline',
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          });
        });
      })
  );
});

// ---- Optional: Update per Nachricht erzwingen ----
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
