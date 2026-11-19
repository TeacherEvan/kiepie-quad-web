extends Node
## Mobile Web text-entry bridge for LineEdit controls.
## Godot 4.3's experimental virtual keyboard focuses a hidden <input> inside
## requestAnimationFrame (blocked by iOS Safari outside a direct user gesture)
## and places it behind the canvas where landscape keyboards cover the field.
## On touch/mobile Web browsers this helper registers the LineEdit's normalized
## screen rect so a synchronous touchend/click listener opens a visible top bar
## above the keyboard and syncs text/submit back into the LineEdit.
## Desktop and headless runs are untouched.

var _le: LineEdit
var _id := ""
var _title := ""
var _placeholder := ""
var _submit_label := "DONE"
var _enter_hint := "done"
var _uppercase := false
var _commit_on_close := false
var _max_len := 0
var _web_active := false
var _mobile_like := false
var _last_rect := Rect2(-1, -1, 0, 0)
var _last_text := ""
var _last_visible := false

static var _next_id := 0


static func attach(line_edit: LineEdit, opts: Dictionary = {}) -> Node:
	## Attach mobile Web text input support to a LineEdit. Safe on all platforms.
	if line_edit == null:
		return null
	var bridge := load("res://src/ui/MobileTextInput.gd").new() as Node
	bridge.name = "MobileTextInput"
	bridge.set("_le", line_edit)
	bridge.set("_title", str(opts.get("title", line_edit.placeholder_text)))
	bridge.set("_placeholder", str(opts.get("placeholder", line_edit.placeholder_text)))
	bridge.set("_submit_label", str(opts.get("submit_label", "DONE")))
	bridge.set("_enter_hint", str(opts.get("enter_key_hint", "done")))
	bridge.set("_uppercase", bool(opts.get("uppercase", false)))
	bridge.set("_commit_on_close", bool(opts.get("commit_on_close", false)))
	bridge.set("_max_len", int(opts.get("max_length", line_edit.max_length)))
	line_edit.add_child(bridge)
	return bridge


func _ready() -> void:
	set_process(false)
	if _le == null:
		return
	_next_id += 1
	_id = "kpin_%d" % _next_id
	_last_text = _le.text
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		_install_js_bridge()
		_mobile_like = bool(JavaScriptBridge.eval("!!(window.__kiepieVk && window.__kiepieVk.isMobileLike())", true))
		if _mobile_like:
			_web_active = true
			set_process(true)
			# Prevent Godot's hidden zIndex:-1 input from stealing focus inside rAF.
			_le.virtual_keyboard_enabled = false
			_le.gui_input.connect(_on_le_gui_input)
			_sync_field(true)


func _process(_delta: float) -> void:
	if not _web_active or _le == null or not is_instance_valid(_le):
		return
	_sync_field(false)
	var raw: Variant = JavaScriptBridge.eval(
			"window.__kiepieVk ? window.__kiepieVk.poll(%s) : ''" % JSON.stringify(_id), true)
	if raw is String and raw != "":
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			apply_dom_state(_le, parsed as Dictionary, _uppercase, _commit_on_close)
			_last_text = _le.text


func _exit_tree() -> void:
	if _web_active and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval(
				"window.__kiepieVk && window.__kiepieVk.removeField(%s);" % JSON.stringify(_id), true)


func _on_le_gui_input(event: InputEvent) -> void:
	if not _web_active or _le == null or not _le.editable or not _mobile_like:
		return
	var released := false
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		released = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			released = true
	if released:
		var is_open := bool(JavaScriptBridge.eval(
				"!!(window.__kiepieVk && window.__kiepieVk.isOpen())", true))
		if not is_open:
			_sync_field(true)
			JavaScriptBridge.eval(
					"window.__kiepieVk && window.__kiepieVk.openById(%s, %s);" % [
							JSON.stringify(_id), JSON.stringify(_le.text)], true)


func _sync_field(force: bool) -> void:
	var vis := _le.is_visible_in_tree() and _le.editable
	var rect := compute_clipped_norm_rect(_le) if vis else Rect2()
	var hittable := vis and rect.size.x > 0.001 and rect.size.y > 0.001
	if not force and vis == _last_visible and _le.text == _last_text \
			and _rect_approx_eq(rect, _last_rect):
		return
	_last_visible = vis
	_last_rect = rect
	_last_text = _le.text
	var payload := {
		"visible": vis,
		"hittable": hittable,
		"nx0": rect.position.x,
		"ny0": rect.position.y,
		"nx1": rect.end.x,
		"ny1": rect.end.y,
		"title": _title,
		"placeholder": _placeholder,
		"submitLabel": _submit_label,
		"enterHint": _enter_hint,
		"uppercase": _uppercase,
		"maxLen": _max_len,
		"text": _le.text,
	}
	JavaScriptBridge.eval(
			"window.__kiepieVk && window.__kiepieVk.setField(%s, %s);" % [
					JSON.stringify(_id), JSON.stringify(payload)], true)


static func _rect_approx_eq(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) < 0.002 \
			and absf(a.position.y - b.position.y) < 0.002 \
			and absf(a.size.x - b.size.x) < 0.002 \
			and absf(a.size.y - b.size.y) < 0.002


static func compute_clipped_norm_rect(ctrl: Control) -> Rect2:
	## Normalized (0..1) window rect clipped to any ScrollContainer / clip_contents ancestors.
	if ctrl == null or not ctrl.is_inside_tree() or not ctrl.is_visible_in_tree():
		return Rect2()
	var win_sz := Vector2(DisplayServer.window_get_size())
	if win_sz.x <= 0.0 or win_sz.y <= 0.0:
		return Rect2()
	var r := _window_pixel_rect(ctrl)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return Rect2()
	var parent := ctrl.get_parent()
	while parent != null:
		if parent is Control:
			var pc := parent as Control
			if pc is ScrollContainer or pc.clip_contents:
				r = r.intersection(_window_pixel_rect(pc))
				if r.size.x <= 1.0 or r.size.y <= 1.0:
					return Rect2()
		parent = parent.get_parent()
	return Rect2(r.position / win_sz, r.size / win_sz)


static func _window_pixel_rect(ctrl: Control) -> Rect2:
	var xf := ctrl.get_viewport_transform() * ctrl.get_global_transform()
	var p0 := xf * Vector2.ZERO
	var p1 := xf * ctrl.size
	return Rect2(
			Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)),
			Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y)))


static func apply_dom_state(le: LineEdit, payload: Dictionary,
		uppercase: bool = false, commit_on_close: bool = false) -> void:
	## Pure state applicator tested offline without needing a browser.
	if le == null or not is_instance_valid(le):
		return
	var raw := str(payload.get("text", le.text))
	var text := raw.to_upper() if uppercase else raw
	if le.max_length > 0 and text.length() > le.max_length:
		text = text.substr(0, le.max_length)
	if le.text != text:
		le.text = text
		le.caret_column = text.length()
	var submitted := bool(payload.get("submitted", false))
	var closed := bool(payload.get("closed", false))
	if submitted:
		if le.is_inside_tree():
			le.release_focus()
		le.text_submitted.emit(text)
	elif closed:
		if le.is_inside_tree():
			le.release_focus()
		if commit_on_close:
			le.text_submitted.emit(text)


static func _install_js_bridge() -> void:
	var js := """
(function() {
  if (window.__kiepieVk) return;
  const canvas = document.getElementById('canvas') || document.querySelector('canvas');
  if (!canvas) return;

  const style = document.createElement('style');
  style.id = 'kiepie-vk-style';
  style.textContent =
    '#kiepie-vk-overlay{position:fixed;inset:0;z-index:9999;display:none;align-items:flex-start;justify-content:center;padding:max(14px,env(safe-area-inset-top)) 12px 12px;background:rgba(6,10,28,0.58);box-sizing:border-box;touch-action:manipulation;}' +
    '#kiepie-vk-card{width:min(460px,100%);background:#0f141e;border:2px solid #ffd16b;border-radius:14px;padding:12px;box-shadow:0 14px 36px rgba(0,0,0,0.68);display:flex;flex-direction:column;gap:8px;box-sizing:border-box;}' +
    '#kiepie-vk-title{font:700 12px/1.2 system-ui,-apple-system,sans-serif;letter-spacing:1.6px;color:#ffd16b;text-transform:uppercase;}' +
    '#kiepie-vk-form{display:flex;gap:8px;align-items:center;width:100%;}' +
    '#kiepie-vk-input{flex:1 1 auto;min-width:0;height:44px;padding:0 12px;border-radius:10px;border:1px solid rgba(130,150,180,0.55);background:#080b12;color:#e8edf7;font:600 16px/1.2 system-ui,-apple-system,sans-serif;outline:none;-webkit-user-select:text;user-select:text;touch-action:auto;box-sizing:border-box;}' +
    '#kiepie-vk-input:focus{border-color:#ffd16b;}' +
    '#kiepie-vk-submit{flex:0 0 auto;height:44px;padding:0 16px;border-radius:10px;border:1px solid #ffd16b;background:#ff8c29;color:#090b10;font:800 14px/1 system-ui,-apple-system,sans-serif;letter-spacing:0.8px;cursor:pointer;touch-action:manipulation;}' +
    '#kiepie-vk-close{flex:0 0 auto;height:44px;min-width:44px;padding:0 12px;border-radius:10px;border:1px solid rgba(130,150,180,0.45);background:#171d29;color:#e8edf7;font:700 13px/1 system-ui,-apple-system,sans-serif;cursor:pointer;touch-action:manipulation;}';
  document.head.appendChild(style);

  const overlay = document.createElement('div');
  overlay.id = 'kiepie-vk-overlay';
  const card = document.createElement('div');
  card.id = 'kiepie-vk-card';
  const titleEl = document.createElement('div');
  titleEl.id = 'kiepie-vk-title';
  const form = document.createElement('form');
  form.id = 'kiepie-vk-form';
  const input = document.createElement('input');
  input.id = 'kiepie-vk-input';
  input.type = 'text';
  input.autocomplete = 'off';
  input.autocorrect = 'off';
  input.spellcheck = false;
  const submitBtn = document.createElement('button');
  submitBtn.id = 'kiepie-vk-submit';
  submitBtn.type = 'submit';
  const closeBtn = document.createElement('button');
  closeBtn.id = 'kiepie-vk-close';
  closeBtn.type = 'button';
  closeBtn.textContent = 'DONE';
  form.appendChild(input);
  form.appendChild(submitBtn);
  form.appendChild(closeBtn);
  card.appendChild(titleEl);
  card.appendChild(form);
  overlay.appendChild(card);
  document.body.appendChild(overlay);

  const fields = Object.create(null);
  const pending = Object.create(null);
  let activeId = '';
  let pendingTouch = null;
  let lastTouchHandledAt = 0;

  function isMobileLike() {
    const coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
    const fineHover = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    const uaMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent || '');
    const touchOnly = (('ontouchstart' in window) || navigator.maxTouchPoints > 0) && !fineHover;
    return !!(coarse || uaMobile || touchOnly);
  }

  function hitField(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    if (!rect || rect.width <= 1 || rect.height <= 1) return null;
    const nx = (clientX - rect.left) / rect.width;
    const ny = (clientY - rect.top) / rect.height;
    for (const id of Object.keys(fields)) {
      const f = fields[id];
      if (!f || !f.visible || !f.hittable) continue;
      if (nx >= f.nx0 && nx <= f.nx1 && ny >= f.ny0 && ny <= f.ny1) {
        return { id: id, field: f };
      }
    }
    return null;
  }

  function openField(id, f, textOverride) {
    if (!f) return;
    activeId = id;
    titleEl.textContent = f.title || f.placeholder || 'INPUT';
    input.placeholder = f.placeholder || '';
    input.value = (typeof textOverride === 'string') ? textOverride : (f.text || '');
    input.autocapitalize = f.uppercase ? 'characters' : 'off';
    input.style.textTransform = f.uppercase ? 'uppercase' : 'none';
    input.setAttribute('enterkeyhint', f.enterHint || 'done');
    if (f.maxLen > 0) input.maxLength = f.maxLen; else input.removeAttribute('maxlength');
    submitBtn.textContent = f.submitLabel || 'DONE';
    closeBtn.style.display = (f.submitLabel && f.submitLabel !== 'DONE') ? 'inline-block' : 'none';
    overlay.style.display = 'flex';
    pending[id] = { text: input.value, submitted: false, closed: false };
    input.focus();
    try {
      const len = input.value.length;
      input.setSelectionRange(len, len);
    } catch (_) {}
  }

  function closeActive(submitted) {
    if (!activeId) return;
    const id = activeId;
    const val = input.value;
    activeId = '';
    pending[id] = { text: val, submitted: !!submitted, closed: !submitted };
    overlay.style.display = 'none';
    try { input.blur(); } catch (_) {}
    try { canvas.focus(); } catch (_) {}
  }

  input.addEventListener('input', function() {
    if (!activeId) return;
    pending[activeId] = { text: input.value, submitted: false, closed: false };
  });

  input.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      closeActive(false);
    }
  });

  form.addEventListener('submit', function(e) {
    e.preventDefault();
    e.stopPropagation();
    closeActive(true);
  });

  closeBtn.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    closeActive(false);
  });

  card.addEventListener('touchstart', function(e) { e.stopPropagation(); }, { passive: true });
  card.addEventListener('touchend', function(e) { e.stopPropagation(); }, { passive: true });
  card.addEventListener('mousedown', function(e) { e.stopPropagation(); });
  card.addEventListener('click', function(e) { e.stopPropagation(); });

  overlay.addEventListener('touchstart', function(e) {
    if (e.target === overlay) e.stopPropagation();
  }, { passive: true });
  overlay.addEventListener('touchend', function(e) {
    if (e.target === overlay) {
      e.preventDefault();
      e.stopPropagation();
      lastTouchHandledAt = performance.now();
      closeActive(false);
    }
  }, { passive: false });
  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) {
      e.stopPropagation();
      if (performance.now() - lastTouchHandledAt > 400) closeActive(false);
    }
  });

  canvas.addEventListener('touchstart', function(evt) {
    if (activeId || evt.touches.length !== 1) {
      pendingTouch = null;
      return;
    }
    const t = evt.touches[0];
    pendingTouch = { id: t.identifier, x: t.clientX, y: t.clientY };
  }, { capture: true, passive: true });

  canvas.addEventListener('touchend', function(evt) {
    if (activeId || !pendingTouch) return;
    const list = evt.changedTouches;
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.identifier === pendingTouch.id) {
        const dist = Math.hypot(t.clientX - pendingTouch.x, t.clientY - pendingTouch.y);
        pendingTouch = null;
        if (dist <= 18) {
          const hit = hitField(t.clientX, t.clientY);
          if (hit) {
            if (evt.cancelable) evt.preventDefault();
            lastTouchHandledAt = performance.now();
            openField(hit.id, hit.field);
          }
        }
        break;
      }
    }
  }, { capture: true, passive: false });

  canvas.addEventListener('click', function(evt) {
    if (activeId || (performance.now() - lastTouchHandledAt) < 500) return;
    if (!isMobileLike()) return;
    const hit = hitField(evt.clientX, evt.clientY);
    if (hit) {
      openField(hit.id, hit.field);
    }
  }, { capture: true });

  window.__kiepieVk = {
    isMobileLike: isMobileLike,
    isOpen: function() { return !!activeId; },
    close: function() { closeActive(false); },
    setField: function(id, cfg) {
      fields[id] = cfg;
      if (activeId === id && (!cfg || !cfg.visible)) {
        closeActive(false);
      }
    },
    removeField: function(id) {
      delete fields[id];
      delete pending[id];
      if (activeId === id) {
        activeId = '';
        overlay.style.display = 'none';
      }
    },
    openById: function(id, textOverride) {
      const f = fields[id];
      if (f && f.visible) openField(id, f, textOverride);
    },
    poll: function(id) {
      const p = pending[id];
      if (!p) return '';
      delete pending[id];
      return JSON.stringify(p);
    }
  };
})();
"""
	JavaScriptBridge.eval(js, true)
