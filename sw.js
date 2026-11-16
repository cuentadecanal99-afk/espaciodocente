// Service worker de Espacio Docente (PWA).
// Estrategia "red primero": siempre intenta traer la versión nueva y solo
// usa la caché si no hay conexión. Las llamadas a Supabase (otro dominio)
// y todo lo que no sea GET pasan directo, sin caché.
// Al cambiar archivos importantes, subí la versión (v1 -> v2).
const CACHE = 'espacio-docente-v1';
const SHELL = [
  '/',
  '/index.html',
  '/austin-tokens.css',
  '/austin-ui.js',
  '/austin-pasos.js',
  '/pud-contexto.js',
  '/nivel-inicial.js',
  '/manifest.json',
  '/icon-192.png',
  '/austin-eco-bilingual-school-campana-argentina.jpg'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      // allSettled: si falta algún archivo, la instalación no se cae.
      Promise.allSettled(SHELL.map((url) => c.add(url)))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  if (new URL(req.url).origin !== self.location.origin) return;

  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copia = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copia));
        }
        return res;
      })
      .catch(() =>
        caches.match(req).then((r) => r || (req.mode === 'navigate' ? caches.match('/') : undefined))
      )
  );
});
