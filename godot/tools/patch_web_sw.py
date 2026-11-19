#!/usr/bin/env python3
"""Patch Godot 4.3's generated Web PWA service worker for fast local caching + instant updates.

Godot 4.3's template SW has three issues on mobile PWAs/browsers:
1. Precaches a non-existent `index.worker.js` on single-threaded exports.
2. Wipes ALL caches on version bump (forcing returning players to re-download the 35 MB
   `index.wasm` even when the engine didn't change) and serves stale `.pck`/`.html`.
3. Computes relative paths from `event.request.referrer`, which is empty on some reloads.
"""
import hashlib
import os
from pathlib import Path
import re
import sys
import tempfile


def _sha12(path: Path) -> str:
    if not path.is_file():
        return "missing"
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


def patch_service_worker(src: str, wasm_hash: str = "dev", pck_hash: str = "dev") -> str:
    # index.worker.js does not exist on single-threaded exports, and index.wasm
    # must live ONLY in ENGINE_CACHE (keyed by wasm content hash): leaving it in
    # CACHED_FILES makes the install event re-download 35 MB into CACHE_NAME on
    # every .pck deploy, while the fetch handler reads ENGINE_CACHE and downloads
    # it a second time on first load.
    out = src.replace('"index.worker.js",', '').replace('"index.wasm",', '')

    # Incorporate index.pck content hash into CACHE_VERSION so every pck change swaps
    # CACHE_NAME cleanly, allowing index.pck to be Cache-First inside its own version bucket.
    out = re.sub(
        r"const CACHE_VERSION = '([^']+)';",
        f"const CACHE_VERSION = '\\1|{pck_hash}';",
        out,
        count=1,
    )

    engine_line = (
        "const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;\n"
        f"const ENGINE_PREFIX = 'KiepieBike-engine-';\n"
        f"const ENGINE_CACHE = ENGINE_PREFIX + '{wasm_hash}';\n"
        "const ENGINE_FILES = ['index.wasm'];"
    )
    if "const ENGINE_CACHE =" not in out:
        out = out.replace("const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;", engine_line, 1)

    old_install = (
        "self.addEventListener('install', (event) => {\n"
        "\tevent.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));\n"
        "});"
    )
    new_install = (
        "self.addEventListener('install', (event) => {\n"
        "\tevent.waitUntil(Promise.all([\n"
        "\t\tcaches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)),\n"
        "\t\tcaches.open(ENGINE_CACHE).then((cache) => cache.match('index.wasm').then((hit) => hit ? undefined : cache.add('index.wasm'))),\n"
        "\t]).then(() => self.skipWaiting()));\n"
        "});"
    )
    if old_install in out:
        out = out.replace(old_install, new_install, 1)

    old_clean = "keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)"
    new_clean = (
        "keys.filter((key) => (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) "
        "|| (key.startsWith(ENGINE_PREFIX) && key !== ENGINE_CACHE))"
    )
    if old_clean in out:
        out = out.replace(old_clean, new_clean, 1)

    old_activate = (
        "\t).then(function () {\n"
        "\t\t// Enable navigation preload if available.\n"
        "\t\treturn ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();\n"
        "\t}));"
    )
    new_activate = (
        "\t).then(function () {\n"
        "\t\treturn self.clients.claim();\n"
        "\t}).then(function () {\n"
        "\t\t// Enable navigation preload if available.\n"
        "\t\treturn ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();\n"
        "\t}));"
    )
    if old_activate in out:
        out = out.replace(old_activate, new_activate, 1)

    old_coep_fn = (
        "function ensureCrossOriginIsolationHeaders(response) {\n"
        "\tif (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'"
    )
    new_coep_fn = (
        "function ensureCrossOriginIsolationHeaders(response) {\n"
        "\tif (!response || response.status === 0 || response.type === 'opaque'\n"
        "\t\t|| [204, 205, 304].includes(response.status)) {\n"
        "\t\treturn response;\n"
        "\t}\n"
        "\tif (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'"
    )
    if old_coep_fn in out:
        out = out.replace(old_coep_fn, new_coep_fn, 1)

    old_fetch_fn = (
        "\tif (isCacheable) {\n"
        "\t\t// And update the cache\n"
        "\t\tcache.put(event.request, response.clone());\n"
        "\t}"
    )
    new_fetch_fn = (
        "\tif (isCacheable && response.ok) {\n"
        "\t\t// And update the cache (ignore storage quota rejections cleanly)\n"
        "\t\tcache.put(event.request, response.clone()).catch(() => {});\n"
        "\t}"
    )
    if old_fetch_fn in out:
        out = out.replace(old_fetch_fn, new_fetch_fn, 1)

    old_fetch_block = (
        "\t\tconst isNavigate = event.request.mode === 'navigate';\n"
        "\t\tconst url = event.request.url || '';\n"
        "\t\tconst referrer = event.request.referrer || '';\n"
        "\t\tconst base = referrer.slice(0, referrer.lastIndexOf('/') + 1);\n"
        "\t\tconst local = url.startsWith(base) ? url.replace(base, '') : '';\n"
        "\t\tconst isCachable = FULL_CACHE.some((v) => v === local) || (base === referrer && base.endsWith(CACHED_FILES[0]));\n"
        "\t\tif (isNavigate || isCachable) {\n"
        "\t\t\tevent.respondWith((async () => {\n"
        "\t\t\t\t// Try to use cache first\n"
        "\t\t\t\tconst cache = await caches.open(CACHE_NAME);\n"
        "\t\t\t\tif (isNavigate) {\n"
        "\t\t\t\t\t// Check if we have full cache during HTML page request.\n"
        "\t\t\t\t\t/** @type {Response[]} */\n"
        "\t\t\t\t\tconst fullCache = await Promise.all(FULL_CACHE.map((name) => cache.match(name)));\n"
        "\t\t\t\t\tconst missing = fullCache.some((v) => v === undefined);\n"
        "\t\t\t\t\tif (missing) {\n"
        "\t\t\t\t\t\ttry {\n"
        "\t\t\t\t\t\t\t// Try network if some cached file is missing (so we can display offline page in case).\n"
        "\t\t\t\t\t\t\tconst response = await fetchAndCache(event, cache, isCachable);\n"
        "\t\t\t\t\t\t\treturn response;\n"
        "\t\t\t\t\t\t} catch (e) {\n"
        "\t\t\t\t\t\t\t// And return the hopefully always cached offline page in case of network failure.\n"
        "\t\t\t\t\t\t\tconsole.error('Network error: ', e); // eslint-disable-line no-console\n"
        "\t\t\t\t\t\t\treturn caches.match(OFFLINE_URL);\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t}\n"
        "\t\t\t\tlet cached = await cache.match(event.request);\n"
        "\t\t\t\tif (cached != null) {\n"
        "\t\t\t\t\tif (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {\n"
        "\t\t\t\t\t\tcached = ensureCrossOriginIsolationHeaders(cached);\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t\treturn cached;\n"
        "\t\t\t\t}\n"
        "\t\t\t\t// Try network if don't have it in cache.\n"
        "\t\t\t\tconst response = await fetchAndCache(event, cache, isCachable);\n"
        "\t\t\t\treturn response;\n"
        "\t\t\t})());"
    )
    new_fetch_block = (
        "\t\tif (event.request.method !== 'GET') {\n"
        "\t\t\treturn;\n"
        "\t\t}\n"
        "\t\tconst isNavigate = event.request.mode === 'navigate';\n"
        "\t\tconst url = event.request.url || '';\n"
        "\t\tlet local = '';\n"
        "\t\ttry {\n"
        "\t\t\tconst u = new URL(url, self.location.href);\n"
        "\t\t\tif (u.origin !== self.location.origin) {\n"
        "\t\t\t\treturn;\n"
        "\t\t\t}\n"
        "\t\t\tlocal = u.pathname.slice(u.pathname.lastIndexOf('/') + 1);\n"
        "\t\t} catch (_) {\n"
        "\t\t\treturn;\n"
        "\t\t}\n"
        "\t\tconst isEngine = ENGINE_FILES.includes(local);\n"
        "\t\tconst isCachable = FULL_CACHE.some((v) => v === local) || (isNavigate && local === '');\n"
        "\t\tconst networkFirst = isNavigate || local === '' || local === 'index.html' || local === 'index.js' || local === 'index.manifest.json';\n"
        "\t\tif (isNavigate || isCachable || isEngine) {\n"
        "\t\t\tevent.respondWith((async () => {\n"
        "\t\t\t\tconst targetCacheName = isEngine ? ENGINE_CACHE : CACHE_NAME;\n"
        "\t\t\t\tconst cache = await caches.open(targetCacheName);\n"
        "\t\t\t\tif (networkFirst) {\n"
        "\t\t\t\t\tconst netPromise = fetchAndCache(event, cache, isCachable);\n"
        "\t\t\t\t\tnetPromise.catch(() => {});\n"
        "\t\t\t\t\ttry {\n"
        "\t\t\t\t\t\treturn await Promise.race([\n"
        "\t\t\t\t\t\t\tnetPromise,\n"
        "\t\t\t\t\t\t\tnew Promise((_, rej) => setTimeout(() => rej(new Error('sw-timeout')), 2500)),\n"
        "\t\t\t\t\t\t]);\n"
        "\t\t\t\t\t} catch (e) {\n"
        "\t\t\t\t\t\tlet cached = await cache.match(event.request);\n"
        "\t\t\t\t\t\tif (cached == null && isNavigate) {\n"
        "\t\t\t\t\t\t\tcached = await cache.match('index.html');\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (cached != null) {\n"
        "\t\t\t\t\t\t\treturn ENSURE_CROSSORIGIN_ISOLATION_HEADERS ? ensureCrossOriginIsolationHeaders(cached) : cached;\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (e && e.message === 'sw-timeout') {\n"
        "\t\t\t\t\t\t\treturn await netPromise;\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (isNavigate) {\n"
        "\t\t\t\t\t\t\tconst off = await caches.match(OFFLINE_URL);\n"
        "\t\t\t\t\t\t\tif (off != null) {\n"
        "\t\t\t\t\t\t\t\treturn off;\n"
        "\t\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tthrow e;\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t}\n"
        "\t\t\t\t// Cache-First for immutable ENGINE_CACHE (index.wasm) and content-hashed CACHE_NAME (index.pck)\n"
        "\t\t\t\tlet cached = await cache.match(event.request);\n"
        "\t\t\t\tif (cached != null) {\n"
        "\t\t\t\t\tif (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {\n"
        "\t\t\t\t\t\tcached = ensureCrossOriginIsolationHeaders(cached);\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t\treturn cached;\n"
        "\t\t\t\t}\n"
        "\t\t\t\treturn await fetchAndCache(event, cache, isCachable || isEngine);\n"
        "\t\t\t})());"
    )
    if old_fetch_block not in out:
        raise RuntimeError("patch_web_sw: expected Godot 4.3 fetch block not found")
    out = out.replace(old_fetch_block, new_fetch_block, 1)
    return out


def _write_atomic(path: Path, text: str) -> None:
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_web_sw.py <path/to/index.service.worker.js>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    wasm_hash = _sha12(path.parent / "index.wasm")
    pck_hash = _sha12(path.parent / "index.pck")
    patched = patch_service_worker(path.read_text(encoding="utf-8"), wasm_hash, pck_hash)
    _write_atomic(path, patched)
    print(f"patch_web_sw: patched {path} (wasm={wasm_hash} pck={pck_hash})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
