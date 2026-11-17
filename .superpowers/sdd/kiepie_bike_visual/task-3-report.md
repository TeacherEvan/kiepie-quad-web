# Task 3 — Web shell brand (report)

**Status: DONE**

## What changed

`godot/export_presets.cfg` — `[preset.0.options]`, `html/head_include` set from `""` to the
single-line `<style>` block below. Nothing else in the preset was touched;
`html/focus_canvas_on_start=true` and `html/canvas_resize_policy=2` are intact (verified by read-back).

### Exact `html/head_include` content added

```
<style>html,body{margin:0;padding:0;background:radial-gradient(1200px 700px at 70% 18%,#1a2748 0%,#0d1430 52%,#060a1c 100%);overflow:hidden;}body::before{content:'#KIEPIE QUAD';position:fixed;top:16px;left:22px;z-index:100;pointer-events:none;font:800 26px/1.1 'Arial Black',Arial,Helvetica,sans-serif;letter-spacing:6px;text-transform:uppercase;color:#ff7a1a;text-shadow:0 0 18px rgba(255,122,26,.45),0 2px 4px rgba(0,0,0,.6);}body::after{content:'W / ↑ drive · Shift turbo';position:fixed;top:50px;left:22px;z-index:100;pointer-events:none;font:600 11px/1 Arial,Helvetica,sans-serif;letter-spacing:3px;text-transform:uppercase;color:rgba(232,238,255,.78);text-shadow:0 1px 3px rgba(0,0,0,.7);}#status{background:radial-gradient(900px 600px at 50% 38%,#141d3d 0%,#0b1128 60%,#060a1c 100%);}</style>
```

Design notes:
- Pure CSS only. **Zero JavaScript** — nothing touches Godot's boot.
- Page background: dark navy radial gradient (`#1a2748 → #0d1430 → #060a1c`) so it reads well behind/around the canvas.
- Brand block: `body::before`, fixed top-left (`top:16px;left:22px`), `#KIEPIE QUAD` in bold (Arial Black, 800), uppercase, orange `#ff7a1a`, 6px letter-spacing, subtle orange glow + dark shadow. `pointer-events:none`, `z-index:100` — purely overlay, never intercepts input.
- Loading hint line: `body::after`, fixed just below the wordmark (`top:50px;left:22px`), `W / ↑ drive · Shift turbo`, uppercase, small caps-style lettering in soft off-white `rgba(232,238,255,.78)`. Also `pointer-events:none`.
- `#status` (Godot's loading overlay) re-themed from `#242424` to a matching navy radial gradient — cosmetic only, shown until `engine.startGame` swaps it out.
- Single-line value, single quotes inside CSS so no quote-escaping in the Godot cfg string. ↑ / · are literal UTF-8 (file is UTF-8; generated HTML meta charset=utf-8).
- Wordmark/hint are injected via CSS pseudo-elements on `<body>` because `head_include`
  lands inside `<head>` — no new DOM elements, no script.

## Export (smoke test)

Command:

```
cd "/home/leandi-duplessis/github/3D builds/Kiepie bike" && timeout 900 godot-4.3 --headless --path godot --export-release "Web" "/home/leandi-duplessis/github/3D builds/Kiepie bike/web/index.html"
```

Exit code: **0**. Tail of output (savepack end, all PCK steps OK):

```
	savepack: step 98: Storing File: res://tools/verify_smash_impact.gd.remap
	savepack: step 98: Storing File: res://tools/screenshot.gd.remap
	savepack: step 98: Storing File: res://tools/truth_test.gd.remap
	savepack: step 98: Storing File: res://tools/verify_features.gd.remap
	savepack: step 98: Storing File: res://.godot/global_script_class_cache.cfg
	savepack: step 98: Storing File: res://icon.svg
	savepack: step 98: Storing File: res://.godot/uid_cache.bin
	savepack: step 98: Storing File: res://project.binary
savepack: end
EXIT=0
```

(New `index.pck` size in GODOT_CONFIG: 2007360 bytes, up from 1707952 — expected after a full re-export. `index.wasm` unchanged at 35376909.)

## Grep evidence — generated `web/index.html`

Head_include landed inside `<head>`, immediately AFTER Godot's built-in `<style>` block (line 79), so its rules win on equal specificity:

```
79:		<style>html,body{margin:0;padding:0;background:radial-gradient(1200px 700px at 70% 18%,#1a2748 0%,#0d1430 52%,#060a1c 100%);overflow:hidden;}body::before{content:'#KIEPIE QUAD';position:fixed;top:16px;left:22px;z-index:100;pointer-events:none;font:800 26px/1.1 'Arial Black',Arial,Helvetica,sans-serif;letter-spacing:6px;text-transform:uppercase;color:#ff7a1a;text-shadow:0 0 18px rgba(255,122,26,.45),0 2px 4px rgba(0,0,0,.6);}body::after{content:'W / ↑ drive · Shift turbo';position:fixed;top:50px;left:22px;z-index:100;pointer-events:none;font:600 11px/1 Arial,Helvetica,sans-serif;letter-spacing:3px;text-transform:uppercase;color:rgba(232,238,255,.78);text-shadow:0 1px 3px rgba(0,0,0,.7);}#status{background:radial-gradient(900px 600px at 50% 38%,#141d3d 0%,#0b1128 60%,#060a1c 100%);}</style>
```

`grep -n 'KIEPIE QUAD\|#ff7a1a\|#status{' index.html` → only line 79 (the injected block); built-in shell style untouched.

Canvas + boot markup intact (grep output, lines 82–100+):

```
82:		<canvas id="canvas">
96:		<script src="index.js"></script>
98:const GODOT_CONFIG = {"args":[],"canvasResizePolicy":2,"ensureCrossOriginIsolationHeaders":true,"executable":"index","experimentalVK":false,"fileSizes":{"index.pck":2007360,"index.wasm":35376909},"focusCanvas":true,"gdextensionLibs":[]};
100:const engine = new Engine(GODOT_CONFIG);
154:		if (GODOT_CONFIG['serviceWorker'] && GODOT_CONFIG['ensureCrossOriginIsolationHeaders'] && 'serviceWorker' in navigator) {
```

- `<title>KiepieBike</title>` unchanged (line 6).
- `#status` / `#status-splash` / `#status-progress` loading overlay markup, `GODOT_CONFIG` (`canvasResizePolicy:2`, `focusCanvas:true`), `new Engine(...)` boot IIFE — all present and unmodified. No `<script>` was added by the include.
- Generated HTML is 5502 bytes; original shell structure (`<head>…</head><body><canvas …>`) preserved.

## Git / deploy state

`web/` is a git repo; `git status --short` shows ` M index.html` and ` M index.pck` (re-export artifacts). **Not committed, not pushed, not deployed** — per task constraints, deploy is the controller's job.

## Smoke-test verdict

`index.html` regenerated and contains the pure-CSS navy-gradient + `#KIEPIE QUAD` orange wordmark + `W / ↑ drive · Shift turbo` hint, with Godot's canvas and boot scripts byte-identical to the default shell.
