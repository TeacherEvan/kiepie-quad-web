#!/usr/bin/env python3
"""Unit tests for patch_web_sw.py: fail-fast on template drift & double-patching."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import patch_web_sw  # noqa: E402


SW_FIXTURE = (
    "const CACHE_PREFIX = 'KiepieBike-';\n"
    "const CACHE_VERSION = '2026-11-24';\n"
    "const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;\n"
    "const CACHED_FILES = ['index.html', 'index.pck', 'index.wasm', 'index.worker.js'];\n"
    "const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;\n"
    "function ensureCrossOriginIsolationHeaders(response) {\n"
    "\tif (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp') return response;\n"
    "\treturn response;\n"
    "}\n"
    "self.addEventListener('install', (event) => {\n"
    "\tevent.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));\n"
    "});\n"
    "self.addEventListener('activate', (event) => {\n"
    "\tevent.waitUntil(caches.keys().then((keys) => Promise.all(\n"
    "\t\tkeys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME).map((k) => caches.delete(k))\n"
    "\t).then(function () {\n"
    "\t\t// Enable navigation preload if available.\n"
    "\t\treturn ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();\n"
    "\t}));\n"
    "});\n"
    "async function fetchAndCache(event, cache, isCacheable) {\n"
    "\tconst response = await fetch(event.request);\n"
    "\tif (isCacheable) {\n"
    "\t\t// And update the cache\n"
    "\t\tcache.put(event.request, response.clone());\n"
    "\t}\n"
    "\treturn response;\n"
    "}\n"
    "self.addEventListener('fetch', (event) => {\n"
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
    "\t\t\t})());\n"
    "\t\t}\n"
    "});\n"
)


def run_tests() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "index.pck").write_bytes(b"pck-bytes")
        (root / "index.wasm").write_bytes(b"wasm-bytes")
        sw_path = root / "index.service.worker.js"

        # 1. Valid fixture patches cleanly
        patched = patch_web_sw.patch_service_worker(SW_FIXTURE, "wasm1234", "pck1234")
        assert "const ENGINE_CACHE =" in patched, "missing ENGINE_CACHE"
        assert "self.clients.claim()" in patched, "missing clients.claim()"
        assert "cache.put(event.request, response.clone()).catch(() => {})" in patched, "missing quota catch"

        # 2. Double-patching raises RuntimeError
        try:
            patch_web_sw.patch_service_worker(patched, "wasm1234", "pck1234")
            raise AssertionError("expected RuntimeError on double-patch")
        except RuntimeError:
            pass

        # 3. Mutating any of the 8 markers raises RuntimeError
        mutations = [
            ("CACHE_VERSION", "const CACHE_VERSION = '2026-11-24';", "// no version"),
            ("CACHE_NAME", "const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;", "// no cache name"),
            ("old_install", "caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES))", "// no install"),
            ("old_clean", "keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)", "// no clean"),
            ("old_activate", "// Enable navigation preload if available.", "// no preload"),
            ("old_coep_fn", "function ensureCrossOriginIsolationHeaders(response) {", "function ensureCOEP(response) {"),
            ("old_fetch_fn", "// And update the cache\n\t\tcache.put(event.request, response.clone());", "// no cache put"),
            ("old_fetch_block", "const isNavigate = event.request.mode === 'navigate';", "// no fetch block"),
        ]
        for name, target, repl in mutations:
            broken = SW_FIXTURE.replace(target, repl, 1)
            assert broken != SW_FIXTURE, f"fixture did not contain {name}"
            try:
                patch_web_sw.patch_service_worker(broken, "wasm1234", "pck1234")
                raise AssertionError(f"expected RuntimeError when {name} is missing")
            except RuntimeError:
                pass


if __name__ == "__main__":
    run_tests()
    print("test_patch_web_sw OK (valid + double-patch + 8 drift markers)")
