## Task 3 — Web shell brand (implementer)

Add `html/head_include` to `godot/export_presets.cfg` for the Web preset: a small inline
`<style>` in the head — dark navy/gradient page background, `#KIEPIE QUAD` wordmark in bold
(uppercase, orange `#ff7a1a`) in a fixed top-left brand block, and a styled loading hint line
("W / ↑ drive · Shift turbo"). The canvas + Godot engine must keep working untouched — keep the
include purely cosmetic (no JS that touches Godot's boot). Keep `html/focus_canvas_on_start=true`
and `html/canvas_resize_policy=2`. Then run one `godot-4.3 --headless --path godot --export-release "Web" web/index.html` as a smoke test and report the generated title/loading markup (do not deploy, deploy is the controller's job).
