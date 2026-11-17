extends GdUnitTestSuite
## GdUnit4 suite for the Kiepie Bike pad. Complements the SceneTree gates in
## tools/ (truth_test/verify_touch/... remain the canonical raw checks; this
## suite proves the framework and gives CI-style assertions). Keep tests
## deterministic and synchronous except one deferred-_ready touch test.

var _roots: Array = []

func after_test() -> void:
	for r in _roots:
		if is_instance_valid(r):
			r.free()
	_roots.clear()

func _boot_pad() -> Node3D:
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root := scene.instantiate() as Node3D
	_roots.append(root)
	add_child(root)
	return root

func test_pad_boots_with_hud_and_touch() -> void:
	var root := _boot_pad()
	assert_object(root.get_node_or_null("KiepieBike")).is_not_null()
	assert_object(root.get_node_or_null("HUD")).is_not_null()
	assert_object(root.get_node_or_null("TouchHUD")).is_not_null()
	var smashed := root.get_node("HUD").get_node_or_null("Smashed") as Label
	assert_object(smashed).is_not_null()
	assert_str(smashed.text).is_equal("Buildings smashed: 0 / 4")

func test_smash_increments_hud_counter() -> void:
	var root := _boot_pad()
	var workshop := root.get_node_or_null("Workshop")
	assert_object(workshop).is_not_null()
	workshop.smash()
	var smashed := root.get_node("HUD").get_node_or_null("Smashed") as Label
	assert_str(smashed.text).is_equal("Buildings smashed: 1 / 4")

func test_touch_gas_holds_and_releases_action() -> void:
	var root := _boot_pad()
	# _ready is deferred (AGENTS.md gotcha) - let the tree settle before probing
	await get_tree().create_timer(0.1).timeout
	var gas := root.get_node("TouchHUD").get_node_or_null("BtnGas") as Button
	assert_object(gas).is_not_null()
	gas.button_down.emit()
	assert_bool(Input.is_action_pressed("move_forward")).is_true()
	gas.button_up.emit()
	assert_bool(Input.is_action_pressed("move_forward")).is_false()


func test_main_menu_attaches_mobile_text_input() -> void:
	var scene: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu := scene.instantiate() as Control
	_roots.append(menu)
	add_child(menu)
	await get_tree().process_frame
	var code_field := menu.get_node_or_null("SafeMargin/Card/VBox/JoinRow/CodeField") as LineEdit
	assert_object(code_field).is_not_null()
	assert_object(code_field.get_node_or_null("MobileTextInput")).is_not_null()


func test_mobile_text_input_applies_dom_state() -> void:
	var mobile_input := load("res://src/ui/MobileTextInput.gd")
	var le := LineEdit.new()
	_roots.append(le)
	add_child(le)
	var submitted := []
	le.text_submitted.connect(func(t: String) -> void: submitted.append(t))

	# Room code submit: uppercases and emits text_submitted
	mobile_input.apply_dom_state(le, {"text": "ab12", "submitted": true}, true, false)
	assert_str(le.text).is_equal("AB12")
	assert_array(submitted).is_equal(["AB12"])

	# Room code close without submit: preserves typed text, does NOT auto-submit
	submitted.clear()
	mobile_input.apply_dom_state(le, {"text": "xy99", "closed": true}, true, false)
	assert_str(le.text).is_equal("XY99")
	assert_array(submitted).is_empty()

	# Display name close with commit_on_close: preserves case and commits
	mobile_input.apply_dom_state(le, {"text": "Lea", "closed": true}, false, true)
	assert_str(le.text).is_equal("Lea")
	assert_array(submitted).is_equal(["Lea"])


func test_match_state_all_ready_and_scoreboard_badges() -> void:
	var m: Node = get_tree().root.get_node("Match")
	var prev_lobby: Dictionary = (m.get("lobby") as Dictionary).duplicate(true)
	var prev_players: Dictionary = (m.get("players") as Dictionary).duplicate(true)
	m.set("lobby", {"id": "1", "host_id": "1", "status": "waiting", "settings": {}})
	m.set("players", {"1": {"user_id": "1", "display_name": "Host", "is_ready": true, "score": 0}})
	assert_bool(bool(m.call("all_ready"))).is_false()
	m.set("players", {
		"1": {"user_id": "1", "display_name": "Host", "is_ready": true, "score": 0},
		"2": {"user_id": "2", "display_name": "Guest", "is_ready": false, "score": 0},
	})
	assert_bool(bool(m.call("all_ready"))).is_false()
	m.set("players", {
		"1": {"user_id": "1", "display_name": "Host", "is_ready": true, "score": 0},
		"2": {"user_id": "2", "display_name": "Guest", "is_ready": true, "score": 0},
	})
	assert_bool(bool(m.call("all_ready"))).is_true()
	var board: Array = m.call("scoreboard")
	assert_int(board.size()).is_equal(2)
	assert_bool(bool((board[0] as Dictionary).get("is_ready", false))).is_true()
	m.set("lobby", prev_lobby)
	m.set("players", prev_players)
