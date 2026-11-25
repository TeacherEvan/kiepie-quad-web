extends RefCounted
class_name CombatAoe
## Shared AOE blast resolver for RocketProjectile, MeteorStrike, and FuelDrum.
## Handles bike radial falloff damage, remote-proxy damage-number dedup,
## chained FuelDrum ignition, and DestructibleBuilding smashing.

const VFX := preload("res://src/game/VfxFactory.gd")


static func apply_blast(tree: SceneTree, fx: Node3D, center: Vector3, radius: float,
		base_damage: float, full_frac: float, edge_mult: float, owner_id: String,
		owner_node: Variant, token: String, skip_owner: bool = true,
		smash_impulse: float = 12.0, hit_destructibles: bool = true,
		chain_hazards: bool = true, skip_bike: Node = null) -> bool:
	if tree == null:
		return false

	var local_uid := ""
	var sb := tree.root.get_node_or_null("Supabase")
	if sb != null and "user_id" in sb:
		local_uid = str(sb.get("user_id"))
	var net: Node = null
	if tree.current_scene is Node:
		net = tree.current_scene.get_node_or_null("ArenaNet")

	var hit_any_enemy := false
	for b in tree.get_nodes_in_group("bike"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var bike_node := b as Node3D
		if not bike_node.visible or bike_node.get("is_respawning") == true:
			continue
		# A rocket's directly-hit proxy is lethal on the victim's own client;
		# showing a 90 number here would suppress the authoritative 100 number.
		if skip_bike != null and bike_node == skip_bike:
			var skip_tid := str(bike_node.get("player_id")) if "player_id" in bike_node else ""
			if owner_id != "" and owner_id == local_uid and skip_tid != local_uid:
				hit_any_enemy = true
			continue
		var dist := bike_node.global_position.distance_to(center)
		if dist > radius:
			continue
		if skip_owner and is_instance_valid(owner_node) and bike_node == owner_node:
			continue
		var target_id := str(bike_node.get("player_id")) if "player_id" in bike_node else ""
		var falloff := 1.0
		if full_frac < 1.0 and dist > radius * full_frac:
			var t := (dist - radius * full_frac) / maxf(0.01, radius * (1.0 - full_frac))
			falloff = lerpf(1.0, edge_mult, t)
		var applied_dmg := roundf(base_damage * falloff)
		var controller: Node = bike_node.get_node_or_null("CombatController")
		if controller == null:
			for child in bike_node.get_children():
				if child.has_method("take_damage"):
					controller = child
					break
		if controller != null and controller.has_method("take_damage"):
			var hit_tok := ("%s:v%s" % [token, target_id]) if (token != "" and target_id != "") else token
			controller.call("take_damage", applied_dmg, owner_id, bike_node.global_position, hit_tok)
		elif owner_id != "" and owner_id == local_uid and target_id != local_uid:
			VFX.damage_number(fx, bike_node.global_position + Vector3(0.0, 0.55, 0.0),
					float(applied_dmg), Color(1.0, 0.85, 0.22))
			if target_id != "" and net != null and net.has_method("note_local_damage_shown"):
				net.call("note_local_damage_shown", target_id)
		if owner_id != "" and owner_id == local_uid and target_id != local_uid:
			hit_any_enemy = true

	if chain_hazards:
		for h in tree.get_nodes_in_group("hazard"):
			if not is_instance_valid(h) or not (h is Node3D):
				continue
			var hz := h as Node3D
			if not hz.visible or bool(hz.get("_ignited")):
				continue
			if hz.global_position.distance_to(center) <= radius and hz.has_method("ignite"):
				var drum_tok := ("%s:d%d" % [token, hz.get_instance_id()]) if token != "" else ""
				hz.call("ignite", owner_id, drum_tok)
				if owner_id != "" and owner_id == local_uid:
					hit_any_enemy = true

	if hit_destructibles:
		for d in tree.get_nodes_in_group("destructible"):
			if not is_instance_valid(d) or not (d is Node3D):
				continue
			var db := d as Node3D
			if db.global_position.distance_to(center) <= radius and db.has_method("smash"):
				var diff := db.global_position - center
				var push_dir := diff.normalized() if diff.length_squared() > 1e-6 else Vector3.UP
				db.call("smash", push_dir * smash_impulse)

	if hit_any_enemy:
		var local_combat := tree.get_first_node_in_group("local_combat")
		if local_combat != null and local_combat.has_signal("hit_confirmed"):
			local_combat.emit_signal("hit_confirmed")
	return hit_any_enemy


static func apply_lethal_blast(tree: SceneTree, fx: Node3D, center: Vector3,
		radius: float, owner_id: String, owner_node: Variant,
		token: String, skip_owner: bool = true) -> bool:
	## Devil Hand special: same radial/chaining/hit_confirmed structure as
	## apply_blast, but every rider in the zone is killed outright through its
	## own CombatController.take_lethal_hit() instead of taking falloff damage.
	## `fx` is reserved for call-site symmetry (no damage numbers are shown:
	## the victim's lethal controller emits the authoritative death/score event).
	if tree == null:
		return false

	var local_uid := ""
	var sb := tree.root.get_node_or_null("Supabase")
	if sb != null and "user_id" in sb:
		local_uid = str(sb.get("user_id"))

	var hit_any_enemy := false
	for b in tree.get_nodes_in_group("bike"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var bike_node := b as Node3D
		if not bike_node.visible or bike_node.get("is_respawning") == true:
			continue
		var dist := bike_node.global_position.distance_to(center)
		if dist > radius:
			continue
		if skip_owner and is_instance_valid(owner_node) and bike_node == owner_node:
			continue
		var target_id := str(bike_node.get("player_id")) if "player_id" in bike_node else ""
		# Fail closed: a remote proxy (or an unidentified bike) is never killed
		# from this client; the victim's own CombatController resolves its death.
		if local_uid == "" or target_id == "" or target_id != local_uid:
			continue
		var controller: Node = bike_node.get_node_or_null("CombatController")
		if controller == null or not controller.has_method("take_lethal_hit"):
			controller = null
			for child in bike_node.get_children():
				if child.has_method("take_lethal_hit"):
					controller = child
					break
		if controller != null:
			# Same-shot multi-kill sub-token contract as RocketProjectile: the
			# host's 1 s rate limiter grants the burst exemption for ":v<id>".
			var hit_tok := ("%s:v%s" % [token, target_id]) if (token != "" and target_id != "") else token
			controller.call("take_lethal_hit", owner_id, bike_node.global_position, hit_tok)
		if owner_id != "" and owner_id == local_uid and target_id != local_uid:
			hit_any_enemy = true

	for h in tree.get_nodes_in_group("hazard"):
		if not is_instance_valid(h) or not (h is Node3D):
			continue
		var hz := h as Node3D
		if not hz.visible or bool(hz.get("_ignited")):
			continue
		if hz.global_position.distance_to(center) <= radius and hz.has_method("ignite"):
			var drum_tok := ("%s:d%d" % [token, hz.get_instance_id()]) if token != "" else ""
			hz.call("ignite", owner_id, drum_tok)
			if owner_id != "" and owner_id == local_uid:
				hit_any_enemy = true

	for d in tree.get_nodes_in_group("destructible"):
		if not is_instance_valid(d) or not (d is Node3D):
			continue
		var db := d as Node3D
		if db.global_position.distance_to(center) <= radius and db.has_method("smash"):
			var diff := db.global_position - center
			var push_dir := diff.normalized() if diff.length_squared() > 1e-6 else Vector3.UP
			db.call("smash", push_dir * 16.0)

	if hit_any_enemy:
		var local_combat := tree.get_first_node_in_group("local_combat")
		if local_combat != null and local_combat.has_signal("hit_confirmed"):
			local_combat.emit_signal("hit_confirmed")
	return hit_any_enemy
