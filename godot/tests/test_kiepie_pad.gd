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
	assert_str(smashed.text).is_equal("Buildings smashed: 0 / 3")

func test_smash_increments_hud_counter() -> void:
	var root := _boot_pad()
	var workshop := root.get_node_or_null("Workshop")
	assert_object(workshop).is_not_null()
	workshop.smash()
	var smashed := root.get_node("HUD").get_node_or_null("Smashed") as Label
	assert_str(smashed.text).is_equal("Buildings smashed: 1 / 3")

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
