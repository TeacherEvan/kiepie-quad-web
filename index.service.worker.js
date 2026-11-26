// This service worker is required to expose an exported Godot project as a
// Progressive Web App. It provides an offline fallback page telling the user
// that they need an Internet connection to run the project if desired.
// Incrementing CACHE_VERSION will kick off the install event and force
// previously cached resources to be updated from the network.
/** @type {string} */
const CACHE_VERSION = '1795711048|12034167|f06c0eb91c61';
/** @type {string} */
const CACHE_PREFIX = 'KiepieBike-sw-cache-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
const ENGINE_PREFIX = 'KiepieBike-engine-';
const ENGINE_CACHE = ENGINE_PREFIX + 'fe5cebc59075';
const ENGINE_FILES = ['index.wasm'];
/** @type {string} */
const OFFLINE_URL = 'index.offline.html';
/** @type {boolean} */
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;
// Files that will be cached on load.
/** @type {string[]} */
const CACHED_FILES = ["index.html","index.js","index.offline.html","index.audio.worklet.js"];
// Files that we might not want the user to preload, and will only be cached on first load.
/** @type {string[]} */
const CACHABLE_FILES = ["index.pck"];
const FULL_CACHE = CACHED_FILES.concat(CACHABLE_FILES);

self.addEventListener('install', (event) => {
	event.waitUntil(Promise.all([
		caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)),
		caches.open(ENGINE_CACHE).then((cache) => cache.match('index.wasm').then((hit) => hit ? undefined : cache.add('index.wasm'))),
	]).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
	event.waitUntil(caches.keys().then(
		function (keys) {
			// Remove old caches.
			return Promise.all(keys.filter((key) => (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) || (key.startsWith(ENGINE_PREFIX) && key !== ENGINE_CACHE)).map((key) => caches.delete(key)));
		}
	).then(function () {
		return self.clients.claim();
	}).then(function () {
		// Enable navigation preload if available.
		return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();
	}));
});

/**
 * Ensures that the response has the correct COEP/COOP headers
 * @param {Response} response
 * @returns {Response}
 */
function ensureCrossOriginIsolationHeaders(response) {
	if (!response || response.status === 0 || response.type === 'opaque'
		|| [204, 205, 206, 304].includes(response.status)) {
		return response;
	}
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') {
		return response;
	}

	const crossOriginIsolatedHeaders = new Headers(response.headers);
	crossOriginIsolatedHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
	crossOriginIsolatedHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
	const newResponse = new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: crossOriginIsolatedHeaders,
	});

	return newResponse;
}

/**
 * Calls fetch and cache the result if it is cacheable
 * @param {FetchEvent} event
 * @param {Cache} cache
 * @param {boolean} isCacheable
 * @returns {Response}
 */
async function fetchAndCache(event, cache, isCacheable) {
	// Use the preloaded response, if it's there
	/** @type { Response } */
	let response = await event.preloadResponse;
	if (response == null) {
		// Or, go over network.
		response = await self.fetch(event.request);
	}

	if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		response = ensureCrossOriginIsolationHeaders(response);
	}

	if (isCacheable && response.ok) {
		// And update the cache (ignore storage quota rejections cleanly)
		cache.put(event.request, response.clone()).catch(() => {});
	}

	return response;
}

self.addEventListener(
	'fetch',
	/**
	 * Triggered on fetch
	 * @param {FetchEvent} event
	 */
	(event) => {
		if (event.request.method !== 'GET') {
			return;
		}
		const isNavigate = event.request.mode === 'navigate';
		const url = event.request.url || '';
		let local = '';
		try {
			const u = new URL(url, self.location.href);
			if (u.origin !== self.location.origin) {
				return;
			}
			if (u.pathname.indexOf('/web-assets/') !== -1 || event.request.headers.has('range')) {
				return;
			}
			local = u.pathname.slice(u.pathname.lastIndexOf('/') + 1);
		} catch (_) {
			return;
		}
		const isEngine = ENGINE_FILES.includes(local);
		const isCachable = FULL_CACHE.some((v) => v === local) || (isNavigate && local === '');
		const networkFirst = isNavigate || local === '' || local === 'index.html' || local === 'index.js' || local === 'index.manifest.json';
		if (isNavigate || isCachable || isEngine) {
			event.respondWith((async () => {
				const targetCacheName = isEngine ? ENGINE_CACHE : CACHE_NAME;
				const cache = await caches.open(targetCacheName);
				if (networkFirst) {
					const netPromise = fetchAndCache(event, cache, isCachable);
					netPromise.catch(() => {});
					let tid = null;
					try {
						return await Promise.race([
							netPromise,
							new Promise((_, rej) => { tid = setTimeout(() => rej(new Error('sw-timeout')), 2500); }),
						]);
					} catch (e) {
						let cached = await cache.match(event.request);
						if (cached == null && isNavigate) {
							cached = await cache.match('index.html');
						}
						if (cached != null) {
							return ENSURE_CROSSORIGIN_ISOLATION_HEADERS ? ensureCrossOriginIsolationHeaders(cached) : cached;
						}
						if (e && e.message === 'sw-timeout') {
							return await netPromise;
						}
						if (isNavigate) {
							const off = await caches.match(OFFLINE_URL);
							if (off != null) {
								return off;
							}
						}
						throw e;
					} finally {
						if (tid !== null) clearTimeout(tid);
					}
				}
				// Cache-First for immutable ENGINE_CACHE (index.wasm) and content-hashed CACHE_NAME (index.pck)
				let cached = await cache.match(event.request);
				if (cached != null) {
					if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
						cached = ensureCrossOriginIsolationHeaders(cached);
					}
					return cached;
				}
				return await fetchAndCache(event, cache, isCachable || isEngine);
			})());
		} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
			event.respondWith((async () => {
				let response = await fetch(event.request);
				response = ensureCrossOriginIsolationHeaders(response);
				return response;
			})());
		}
	}
);

self.addEventListener('message', (event) => {
	// No cross origin
	if (event.origin !== self.origin) {
		return;
	}
	const id = event.source.id || '';
	const msg = event.data || '';
	// Ensure it's one of our clients.
	self.clients.get(id).then(function (client) {
		if (!client) {
			return; // Not a valid client.
		}
		if (msg === 'claim') {
			self.skipWaiting().then(() => self.clients.claim());
		} else if (msg === 'clear') {
			caches.delete(CACHE_NAME);
		} else if (msg === 'update') {
			self.skipWaiting().then(() => self.clients.claim()).then(() => self.clients.matchAll()).then((all) => all.forEach((c) => c.navigate(c.url)));
		}
	});
});

