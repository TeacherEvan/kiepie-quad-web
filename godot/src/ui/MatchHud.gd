extends CanvasLayer
## Match HUD for the multiplayer combat arena.
## Created on the "HUD" CanvasLayer by tools/build_arena.gd. All child widgets are
## looked up by node name in _ready so the builder owns layout and this script
## owns behaviour. Never releases an Input action it did not press (see AGENTS.md).

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const UI := preload("res://src/ui/UiTheme.gd")

var _combat: Node = null
var _dead := false
var _died_at := 0.0
var _kill_lines: Array = []
var _fps_label: Label
var _fps_accum := 0.0
var _fps_frames := 0
var _vignette: ColorRect
var _announce_label: Label
var _last_respawn_text := ""
# Cached bar fill: mutate one StyleBox instead of allocating per damage tick.
var _hp_fill: StyleBoxFlat
var _reload_fill: StyleBoxFlat
var _hitmarker: Label = null
var _victory_banner: Label = null
var victory_splash_shown := false
var _race_banner_override := ""
var _hit_tween: Tween = null
var _hurt_tween: Tween = null
var _announce_tween: Tween = null
var _hurt_gen := 0
var _hit_gen := 0
var _announce_gen := 0
var _scores_open := false


func _init() -> void:
	add_to_group("match_hud")
	add_to_group("back_handler")


func _ready() -> void:
	# --- local combat controller (group is registered in its own _ready).
	# Fall back to the known scene path to survive _ready ordering differences.
	var combat_nodes := get_tree().get_nodes_in_group("local_combat")
	if not combat_nodes.is_empty():
		_combat = combat_nodes[0]
	if _combat == null:
		_combat = get_node_or_null("../KiepieBike/CombatController")
	if _combat != null:
		if _combat.has_signal("health_changed"):
			_combat.health_changed.connect(_on_health_changed)
		if _combat.has_signal("died"):
			_combat.died.connect(_on_died)
		if _combat.has_signal("respawned"):
			_combat.respawned.connect(_on_respawned)
		if _combat.has_signal("hurt"):
			_combat.hurt.connect(_on_hurt)
		if _combat.has_signal("pickup_collected"):
			_combat.pickup_collected.connect(_on_pickup)
		if _combat.has_signal("hit_confirmed"):
			_combat.hit_confirmed.connect(_on_hit_confirmed)
		var cannons: Node = _combat.get("cannons") if "cannons" in _combat else _combat.get_node_or_null("SideCannons")
		if cannons != null:
			if cannons.has_signal("reload_changed"):
				cannons.connect("reload_changed", _on_reload_changed)
			if cannons.has_signal("weapon_changed"):
				cannons.connect("weapon_changed", _on_weapon_changed)
			if cannons.has_method("weapon_display_name"):
				_on_reload_changed(1.0, 0.0, true, str(cannons.call("weapon_display_name")))

	# --- authoritative match state (autoload). Guarded for headless gates.
	if Match != null:
		Match.score_updated.connect(_on_score_updated)
		Match.match_started.connect(_on_match_started)
		Match.match_finished.connect(_on_match_finished)
		Match.lobby_changed.connect(_on_lobby_changed)
		Match.self_respawn_at.connect(_on_self_respawn_at)

	# --- result & top-right navigation + scoreboard dropdown
	var menu_btn := get_node_or_null("MenuBtn") as Button
	if menu_btn != null:
		menu_btn.pressed.connect(_on_leave_match)
		_compact_btn(menu_btn, 12, 6.0)
	var score_toggle := get_node_or_null("ScoreToggle") as Button
	if score_toggle != null:
		score_toggle.pressed.connect(_on_toggle_scores)
		_compact_btn(score_toggle, 12, 6.0)
	var score := get_node_or_null("Scoreboard") as Control
	if score != null:
		score.visible = false
	_sync_score_toggle()
	Settings.call_deferred("sync_back_handler")
	var again := get_node_or_null("ResultPanel/PlayAgainBtn") as Button
	if again != null:
		again.pressed.connect(_on_leave_match)
	var leave := get_node_or_null("ResultPanel/LeaveBtn") as Button
	if leave != null:
		leave.pressed.connect(_on_leave_match)

	# --- radar: builder creates a plain Control; this script gives it a custom
	# _draw implementation (inner class) so no second .gd file is needed.
	var radar := get_node_or_null("Radar") as Control
	if radar != null:
		radar.set_script(RadarControl)
		radar.set("local_bike_path", NodePath("../../KiepieBike"))

	# --- initial state
	_refresh_banner()
	_refresh_scoreboard()
	_relayout()
	get_viewport().size_changed.connect(_on_viewport_resized)
	var overlay := get_node_or_null("RespawnOverlay")
	if overlay != null:
		overlay.visible = false
	var result := get_node_or_null("ResultPanel")
	if result != null:
		result.visible = false

	# --- cached bar fill (no per-frame StyleBox allocation on mobile Web)
	var health_bar := get_node_or_null("HealthBar") as ProgressBar
	if health_bar != null:
		_hp_fill = UI.bar_fill(UI.OK)
		health_bar.add_theme_stylebox_override("fill", _hp_fill)
	var reload_bar := get_node_or_null("ReloadBar") as ProgressBar
	if reload_bar != null:
		_reload_fill = UI.bar_fill(UI.OK)
		reload_bar.add_theme_stylebox_override("fill", _reload_fill)
	var res_panel := get_node_or_null("ResultPanel") as Control
	if res_panel != null and res_panel.get_node_or_null("VictorySplashBanner") == null:
		_victory_banner = Label.new()
		_victory_banner.name = "VictorySplashBanner"
		_victory_banner.text = "🏁 VICTORY SPLASH · CHAMPION 🏁"
		_victory_banner.anchor_left = 0.0
		_victory_banner.anchor_right = 1.0
		_victory_banner.offset_top = 8.0
		_victory_banner.offset_bottom = 34.0
		_victory_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_victory_banner.add_theme_font_size_override("font_size", 15)
		_victory_banner.add_theme_color_override("font_color", UI.GOLD)
		_victory_banner.visible = false
		res_panel.add_child(_victory_banner)

	# --- hit feedback overlay + streak announcement (runtime-created)
	_vignette = ColorRect.new()
	_vignette.name = "HurtVignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.85, 0.05, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	_announce_label = Label.new()
	_announce_label.name = "Announce"
	_announce_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce_label.offset_top = 96.0
	_announce_label.offset_bottom = 150.0
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.add_theme_font_size_override("font_size", 34)
	_announce_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	_announce_label.add_theme_constant_override("outline_size", 8)
	_announce_label.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.0))
	_announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_announce_label)
	# Crosshair hit confirmation — a 4-tick flash on every landed shot.
	_hitmarker = Label.new()
	_hitmarker.name = "HitMarker"
	_hitmarker.text = "×"
	_hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker.offset_left = -15.0
	_hitmarker.offset_right = 15.0
	_hitmarker.offset_top = -18.0
	_hitmarker.offset_bottom = 12.0
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker.add_theme_font_size_override("font_size", 36)
	_hitmarker.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72, 1.0))
	_hitmarker.add_theme_constant_override("outline_size", 8)
	_hitmarker.add_theme_color_override("font_outline_color", Color(0.2, 0.04, 0.0, 0.9))
	_hitmarker.modulate.a = 0.0
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmarker)


# ------------------------------------------------------------------ signals ---

func _compact_btn(btn: Button, font_sz: int, h_margin: float) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", font_sz)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var dup := sb.duplicate() as StyleBoxFlat
			dup.content_margin_left = h_margin
			dup.content_margin_right = h_margin
			btn.add_theme_stylebox_override(state, dup)


func _on_toggle_scores() -> void:
	_scores_open = not _scores_open
	_sync_score_toggle()


func _sync_score_toggle() -> void:
	var btn := get_node_or_null("ScoreToggle") as Button
	if btn != null:
		btn.text = "SCORES ▴" if _scores_open else "SCORES ▾"
	var score := get_node_or_null("Scoreboard") as Control
	if score != null:
		score.visible = _scores_open


var _relayout_pending := false


func _on_viewport_resized() -> void:
	# Coalesce drag-resize storms into one relayout per 100 ms window.
	if _relayout_pending:
		return
	_relayout_pending = true
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		_relayout_pending = false
		if is_instance_valid(self) and is_inside_tree():
			_relayout())


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var narrow := vp.x <= 640.0
	var short := vp.y <= 500.0
	var corner_w := 120.0 if (narrow or short) else 130.0

	var hl := get_node_or_null("HealthLabel") as Control
	var hb := get_node_or_null("HealthBar") as Control
	if hl != null and hb != null:
		for c in [hl, hb]:
			c.anchor_left = 0.0
			c.anchor_right = 0.0
			c.anchor_top = 0.0
			c.anchor_bottom = 0.0
			c.offset_left = 12.0
			c.offset_right = 12.0 + corner_w
		hl.offset_top = 8.0 if (narrow or short) else 10.0
		hl.offset_bottom = hl.offset_top + 15.0
		hb.offset_top = hl.offset_bottom + 1.0
		hb.offset_bottom = hb.offset_top + 12.0

	var banner := get_node_or_null("Banner") as Label
	if banner != null:
		banner.anchor_left = 0.0
		banner.anchor_right = 0.0
		banner.anchor_top = 0.0
		banner.anchor_bottom = 0.0
		banner.offset_left = 12.0
		banner.offset_right = 12.0 + corner_w + 48.0
		banner.offset_top = 40.0 if (narrow or short) else 42.0
		banner.offset_bottom = banner.offset_top + 18.0
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var wl := get_node_or_null("WeaponLabel") as Control
	var rb := get_node_or_null("ReloadBar") as Control
	if wl != null and rb != null:
		for c in [wl, rb]:
			c.anchor_left = 0.0
			c.anchor_right = 0.0
			c.anchor_top = 0.0
			c.anchor_bottom = 0.0
			c.offset_left = 12.0
		wl.offset_right = 12.0 + corner_w + 64.0
		rb.offset_right = 12.0 + corner_w
		wl.offset_top = 58.0 if (narrow or short) else 60.0
		wl.offset_bottom = wl.offset_top + 15.0
		rb.offset_top = wl.offset_bottom + 1.0
		rb.offset_bottom = rb.offset_top + 10.0

	var menu_btn := get_node_or_null("MenuBtn") as Button
	if menu_btn != null:
		menu_btn.anchor_left = 1.0
		menu_btn.anchor_right = 1.0
		menu_btn.anchor_top = 0.0
		menu_btn.anchor_bottom = 0.0
		if narrow:
			menu_btn.offset_left = -104.0
			menu_btn.offset_right = -10.0
			menu_btn.offset_top = 60.0
			menu_btn.offset_bottom = 104.0
		elif short:
			menu_btn.offset_left = -312.0
			menu_btn.offset_right = -220.0
			menu_btn.offset_top = 10.0
			menu_btn.offset_bottom = 54.0
		else:
			menu_btn.offset_left = -320.0
			menu_btn.offset_right = -224.0
			menu_btn.offset_top = 12.0
			menu_btn.offset_bottom = 56.0

	var score_toggle := get_node_or_null("ScoreToggle") as Button
	if score_toggle != null:
		score_toggle.anchor_left = 1.0
		score_toggle.anchor_right = 1.0
		score_toggle.anchor_top = 0.0
		score_toggle.anchor_bottom = 0.0
		if narrow:
			score_toggle.offset_left = -204.0
			score_toggle.offset_right = -110.0
			score_toggle.offset_top = 10.0
			score_toggle.offset_bottom = 54.0
		elif short:
			score_toggle.offset_left = -212.0
			score_toggle.offset_right = -114.0
			score_toggle.offset_top = 10.0
			score_toggle.offset_bottom = 54.0
		else:
			score_toggle.offset_left = -216.0
			score_toggle.offset_right = -116.0
			score_toggle.offset_top = 12.0
			score_toggle.offset_bottom = 56.0

	var score := get_node_or_null("Scoreboard") as Control
	if score != null:
		var sw := minf(220.0, vp.x * 0.56) if narrow else (minf(240.0, vp.x * 0.28) if short else 250.0)
		var rows_cnt := Match.players.size() if Match != null else 1
		var sh := clampf(float(maxi(1, rows_cnt)) * 24.0 + 20.0, 54.0, 176.0)
		score.anchor_left = 1.0
		score.anchor_right = 1.0
		score.offset_left = -sw - 10.0
		score.offset_right = -10.0
		score.offset_top = 110.0 if narrow else (60.0 if short else 62.0)
		score.offset_bottom = score.offset_top + sh
		score.visible = _scores_open

	var radar := get_node_or_null("Radar") as Control
	if radar != null:
		radar.visible = vp.y >= 260.0
		var rsize := 92.0 if narrow else (80.0 if short else 128.0)
		radar.offset_left = 12.0
		radar.offset_top = 90.0 if (narrow or short) else 94.0
		radar.offset_right = 12.0 + rsize
		radar.offset_bottom = radar.offset_top + rsize

	var feed := get_node_or_null("KillFeed") as Control
	if feed != null:
		if narrow:
			feed.offset_left = 12.0
			feed.offset_right = minf(220.0, vp.x * 0.56)
			feed.offset_top = 160.0
			feed.offset_bottom = 236.0
		else:
			feed.offset_left = 154.0
			feed.offset_right = maxf(240.0, minf(380.0, vp.x - 340.0))
			feed.offset_top = 10.0
			feed.offset_bottom = 106.0

	var respawn := get_node_or_null("RespawnOverlay") as Control
	if respawn != null:
		var rw := minf(560.0, vp.x - 24.0)
		respawn.offset_left = -rw * 0.5
		respawn.offset_right = rw * 0.5

	var result := get_node_or_null("ResultPanel") as Control
	if result != null:
		var pw := minf(600.0, vp.x - 24.0)
		var ph := minf(340.0, vp.y - 24.0)
		result.offset_left = -pw * 0.5
		result.offset_right = pw * 0.5
		result.offset_top = -ph * 0.5
		result.offset_bottom = ph * 0.5


func _reduced_motion() -> bool:
	return Settings.reduced_motion()


func _on_hurt(amount: float, _attacker_id: String) -> void:
	if _vignette == null:
		return
	_hurt_gen += 1
	var gen := _hurt_gen
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	_hurt_tween = null
	var strength := clampf(amount / 100.0, 0.12, 0.5)
	_vignette.color.a = strength
	if _reduced_motion():
		# Static flash - no animated opacity ramp.
		await get_tree().create_timer(0.15).timeout
		if not is_inside_tree() or gen != _hurt_gen:
			return
		if is_instance_valid(_vignette):
			_vignette.color.a = 0.0
		return
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_vignette, "color:a", 0.0, 0.45)


func _on_pickup(kind: String) -> void:
	announce("PICKUP: " + kind.to_upper())


func _on_weapon_changed(_weapon_id: String, label: String) -> void:
	announce("WEAPON: " + label)


func _on_reload_changed(progress: float, remaining: float, is_ready: bool, label: String) -> void:
	var rb := get_node_or_null("ReloadBar") as ProgressBar
	if rb != null:
		rb.value = clampf(progress * 100.0, 0.0, 100.0)
	if _reload_fill != null:
		_reload_fill.bg_color = UI.OK if is_ready else UI.GOLD.lerp(UI.ACCENT, 1.0 - clampf(progress, 0.0, 1.0))
	var wl := get_node_or_null("WeaponLabel") as Label
	if wl != null:
		if is_ready:
			wl.text = "%s · READY" % label
		else:
			wl.text = "%s · %.1fs" % [label, remaining]


func _on_hit_confirmed() -> void:
	if _hitmarker == null:
		return
	_hit_gen += 1
	var gen := _hit_gen
	# Rapid consecutive hits would otherwise race overlapping tweens and can
	# strand the marker at 1.6x scale. Restart cleanly from a known state.
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = null
	_hitmarker.scale = Vector2.ONE
	_hitmarker.modulate.a = 1.0
	if _reduced_motion():
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree() or gen != _hit_gen:
			return
		if is_instance_valid(_hitmarker):
			_hitmarker.modulate.a = 0.0
		return
	_hit_tween = create_tween()
	_hit_tween.tween_property(_hitmarker, "scale", Vector2(1.6, 1.6), 0.08)
	_hit_tween.chain().tween_property(_hitmarker, "modulate:a", 0.0, 0.22)
	_hit_tween.tween_callback(func() -> void:
		if is_instance_valid(_hitmarker):
			_hitmarker.scale = Vector2.ONE)


func announce(text: String) -> void:
	if _announce_label == null:
		return
	_announce_gen += 1
	var gen := _announce_gen
	# Overlapping announcements kill the previous banner instead of stacking
	# tweens on the same label.
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = null
	_announce_label.modulate.a = 1.0
	_announce_label.scale = Vector2.ONE
	_announce_label.text = text
	if _reduced_motion():
		_announce_label.modulate.a = 1.0
		await get_tree().create_timer(1.4).timeout
		if not is_inside_tree() or gen != _announce_gen:
			return
		if is_instance_valid(_announce_label):
			_announce_label.modulate.a = 0.0
			_announce_label.text = ""
		return
	_announce_label.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	_announce_tween = t
	t.tween_property(_announce_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	t.tween_interval(1.2)
	t.tween_property(_announce_label, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void:
		if is_instance_valid(_announce_label):
			# Hidden means hidden: clear the text and leave alpha at 0 like the
			# reduced-motion path. Snapping alpha back to 1 left stale banners
			# stuck on screen for the rest of the match.
			_announce_label.modulate.a = 0.0
			_announce_label.text = "")


func _on_health_changed(current: float, maximum: float) -> void:
	var bar := get_node_or_null("HealthBar") as ProgressBar
	if bar != null:
		bar.max_value = maximum
		bar.value = current
	var label := get_node_or_null("HealthLabel") as Label
	if label != null:
		label.text = "ARMOR %d" % roundi(current)
	if _hp_fill != null and maximum > 0.0:
		# Green → gold → red as armour falls; mutate the cached resource.
		_hp_fill.bg_color = _armor_color(clampf(current / maximum, 0.0, 1.0))


func _armor_color(t: float) -> Color:
	if t >= 0.5:
		return UI.OK.lerp(UI.GOLD, (1.0 - t) * 2.0)
	return UI.GOLD.lerp(UI.DANGER, (0.5 - t) * 2.0)


func _on_died(killer_id: String) -> void:
	_dead = true
	_died_at = Time.get_ticks_msec() / 1000.0
	var overlay := get_node_or_null("RespawnOverlay") as Label
	if overlay != null:
		overlay.visible = true
		overlay.text = "DOWN — RESPAWNING…"


func _on_respawned() -> void:
	_dead = false
	var overlay := get_node_or_null("RespawnOverlay")
	if overlay != null:
		overlay.visible = false


func _on_score_updated(_user_id: String, _score: int) -> void:
	_refresh_banner()
	_refresh_scoreboard()


func _on_match_started() -> void:
	var result := get_node_or_null("ResultPanel")
	if result != null:
		result.visible = false
	var overlay := get_node_or_null("RespawnOverlay")
	if overlay != null:
		overlay.visible = false
	_dead = false
	_refresh_banner()
	_refresh_scoreboard()


func _on_match_finished(winner_id: String) -> void:
	var winner_name := _name_for(winner_id).to_upper() if winner_id != "" else ""
	var winner_label := get_node_or_null("ResultPanel/WinnerLabel") as Label
	if winner_label != null:
		if winner_id == "":
			winner_label.text = "HOST LOST — MATCH VOID"
		else:
			winner_label.text = "%s WINS" % winner_name
	var result := get_node_or_null("ResultPanel")
	if result != null:
		result.visible = true
	if winner_id != "":
		_play_victory_splash(winner_name)
	_refresh_scoreboard()


func _play_victory_splash(winner_name: String) -> void:
	victory_splash_shown = true
	if _victory_banner != null:
		var mode_str := "DEATH RACE" if (Match != null and Match.has_method("game_mode") and str(Match.call("game_mode")) == "death_race") else "BATTLE ROYALE"
		_victory_banner.text = "🏁 %s CHAMPION · %s 🏁" % [mode_str, winner_name]
		_victory_banner.visible = true
	if OS.has_feature("web") and not _reduced_motion():
		var safe_winner := JSON.stringify(winner_name + " WINS!")
		JavaScriptBridge.eval("window.__kiepiePlayVictorySplash && window.__kiepiePlayVictorySplash(%s);" % safe_winner, true)


func set_race_status(current_lap: int, total_laps: int, cp_cleared: int, cp_total: int) -> void:
	_race_banner_override = "LAP %d/%d · CP %d/%d" % [current_lap, total_laps, cp_cleared, cp_total]
	_refresh_banner()


func _on_lobby_changed() -> void:
	_refresh_banner()
	_refresh_scoreboard()


func _on_self_respawn_at(_seconds: float) -> void:
	# CombatController owns the actual respawn timer; nothing to do here.
	pass


# ------------------------------------------------------------------- public ---

func add_kill(killer_id: String, victim_id: String) -> void:
	## Append one kill-feed line ("KILLER  ⚔  VICTIM"), fade after ~5 s, cap 5.
	var feed := get_node_or_null("KillFeed") as VBoxContainer
	if feed == null:
		return
	var line := Label.new()
	line.text = "%s   ⚔   %s" % [_name_for(killer_id), _name_for(victim_id)]
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", Color(1.0, 0.90, 0.66, 1.0))
	line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	line.add_theme_constant_override("outline_size", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(line)
	_kill_lines.append(line)
	while _kill_lines.size() > 5:
		var old = _kill_lines.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var line_ref = line
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(self) or not is_inside_tree() or not is_instance_valid(line_ref):
			return
		if _reduced_motion():
			(line_ref as Node).queue_free()
			_kill_lines.erase(line_ref)
			return
		var tw := create_tween()
		tw.tween_property(line_ref, "modulate:a", 0.0, 1.0)
		tw.tween_callback(func() -> void:
			if is_instance_valid(line_ref):
				(line_ref as Node).queue_free()
			_kill_lines.erase(line_ref)))


# ------------------------------------------------------------------ helpers ---

func _name_for(uid: String) -> String:
	if Match == null:
		return uid.substr(0, 6) if uid.length() > 6 else uid
	for row in Match.scoreboard():
		var d := row as Dictionary
		if d != null and str(d.get("user_id", "")) == uid:
			return str(d.get("name", "RIDER"))
	return uid.substr(0, 6) if uid.length() > 6 else (uid if uid != "" else "RIDER")


func _refresh_banner() -> void:
	var banner := get_node_or_null("Banner") as Label
	if banner == null or Match == null:
		return
	if _race_banner_override != "":
		banner.text = _race_banner_override
	elif Match.has_method("game_mode") and str(Match.call("game_mode")) == "death_race":
		var target_laps := int(Match.call("lap_target")) if Match.has_method("lap_target") else 3
		banner.text = "LAP %d/%d" % [mini(target_laps, Match.my_score() + 1), target_laps]
	else:
		banner.text = "%d/%d" % [Match.my_score(), Match.kill_target()]


func _refresh_scoreboard() -> void:
	var node := get_node_or_null("Scoreboard")
	if node == null or Match == null:
		return
	var rows: Array = Match.scoreboard()
	if node is Control:
		var sc := node as Control
		var sh := clampf(float(maxi(1, rows.size())) * 24.0 + 20.0, 54.0, 176.0)
		sc.offset_bottom = sc.offset_top + sh
	if node is RichTextLabel:
		var rtl := node as RichTextLabel
		rtl.clear()
		for row in rows:
			var d := row as Dictionary
			if d == null:
				continue
			var hex := str(d.get("color", "#ffffff"))
			var col := Color.html(hex) if hex.is_valid_html_color() else Color.WHITE
			var mine := bool(d.get("is_me", false))
			var nm := str(d.get("name", "RIDER"))
			var score := int(d.get("score", 0))
			rtl.push_color(col)
			rtl.add_text("■ ")
			rtl.pop()
			rtl.push_color(Color(1.0, 0.85, 0.42, 1.0) if mine else Color(0.94, 0.96, 1.0, 1.0))
			rtl.add_text(("* " if mine else "  ") + nm)
			rtl.pop()
			rtl.push_color(Color(0.74, 0.82, 0.92, 1.0))
			rtl.add_text("   %d\n" % score)
			rtl.pop()
	elif node is VBoxContainer:
		var box := node as VBoxContainer
		for c in box.get_children():
			c.queue_free()
		for row in rows:
			var d := row as Dictionary
			if d == null:
				continue
			var lbl := Label.new()
			lbl.text = "%s  %s  %d" % ["■", str(d.get("name", "RIDER")), int(d.get("score", 0))]
			var hex := str(d.get("color", "#ffffff"))
			lbl.add_theme_color_override("font_color", Color.html(hex) if hex.is_valid_html_color() else Color.WHITE)
			lbl.add_theme_constant_override("outline_size", 5)
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			box.add_child(lbl)


func _on_leave_match() -> void:
	if Lobby != null:
		Lobby.leave()
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_back_requested() -> void:
	_on_leave_match()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_leave_match()


func _process(delta: float) -> void:
	if Settings.get_value("video", "show_fps", false):
		if _fps_label == null:
			_fps_label = Label.new()
			_fps_label.name = "FpsLabel"
			_fps_label.position = Vector2(16, 250)
			_fps_label.add_theme_font_size_override("font_size", 14)
			_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
			add_child(_fps_label)
		_fps_label.visible = true
		_fps_accum += delta
		_fps_frames += 1
		if _fps_accum >= 0.5:
			_fps_label.text = "%d FPS" % int(_fps_frames / maxf(_fps_accum, 0.001))
			_fps_accum = 0.0
			_fps_frames = 0
	elif _fps_label != null:
		_fps_label.visible = false
	# Respawn countdown (10 Hz is plenty for a second-resolution label).
	if _dead:
		var overlay := get_node_or_null("RespawnOverlay") as Label
		var delay := Match.respawn_delay() if Match != null else 2.5
		var remaining := delay - (Time.get_ticks_msec() / 1000.0 - _died_at)
		var text := "DOWN — RESPAWNING IN %d" % maxi(0, ceili(remaining))
		if overlay != null and text != _last_respawn_text:
			_last_respawn_text = text
			overlay.text = text


# ------------------------------------------------------------------- radar ---

## Mini-radar drawn as a Control subclass. World X/Z map to screen right/down;
## the local bike sits at the centre. Redraws at ~10 Hz via queue_redraw().
class RadarControl extends Control:
	var local_bike_path: NodePath = ^""
	var _local: Node3D = null
	var _accum := 0.0
	const RADIUS := 76.0
	const WORLD_RANGE := 50.0

	func _process(delta: float) -> void:
		if _local == null:
			_local = get_node_or_null(local_bike_path) as Node3D
			if _local == null:
				var c := get_tree().get_first_node_in_group("local_combat")
				if c != null:
					_local = c.get_parent() as Node3D
		_accum += delta
		if _accum >= 0.1:
			_accum = 0.0
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(RADIUS, minf(size.x, size.y) * 0.5 - 4.0)
		draw_circle(c, r, Color(0.03, 0.06, 0.10, 0.62))
		draw_arc(c, r, 0.0, TAU, 48, Color(0.35, 0.85, 0.95, 0.60), 2.0)
		draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), Color(1, 1, 1, 0.11), 1.0)
		draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), Color(1, 1, 1, 0.11), 1.0)
		# local player: bright green centre dot
		draw_circle(c, 4.5, Color(0.40, 1.0, 0.55, 1.0))
		if _local == null or get_tree() == null:
			return
		var origin := _local.global_position
		for b in get_tree().get_nodes_in_group("bike"):
			if b == _local or not (b is Node3D):
				continue
			var node := b as Node3D
			if not node.visible:
				continue  # respawning proxies are hidden
			var d := node.global_position - origin
			var offset := Vector2(d.x, d.z) / WORLD_RANGE * r
			if offset.length() > r:
				offset = offset.normalized() * r
			var col := Color(1.0, 0.35, 0.25, 1.0)
			var pc = node.get("player_color")
			if pc is Color:
				col = pc as Color
			draw_circle(c + offset, 3.5, col)
