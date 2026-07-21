@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const LEVEL_CREATOR_SCENE := "res://level_creator/level_creator.tscn"


func test_level_creator_submits_level_to_localhost() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	assert_object(OnlineSession.client).is_not_null()
	assert_object(OnlineSession.session).is_not_null()
	assert_str(OnlineSession.client.host).is_equal("127.0.0.1")
	assert_int(OnlineSession.client.port).is_equal(7350)
	assert_str(OnlineSession.client.scheme).is_equal("http")

	var runner := scene_runner(_load_level_creator())
	await runner.simulate_frames(2)
	var creator := runner.scene() as LevelCreator
	assert_object(creator).is_not_null()

	creator.start_new_level()
	await await_idle_frame()

	var level_name := "it_local_submit_%d" % Time.get_ticks_msec()
	var level_key := level_name
	creator.tile_palette.level_name = level_name
	creator.tile_palette.level_description = "integration submit smoke"

	_build_minimal_valid_level(creator)

	var save_error: String = await creator._save_level()
	assert_str(save_error).is_empty()

	var list_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(list_result).is_not_null()
	assert_bool(list_result is Dictionary).is_true()

	var levels: Array = (list_result as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(levels, level_key)).is_true()

	var delete_result: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_result).is_not_null()


func test_submit_level_with_publish_is_server_managed() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var level_key := "it_local_publish_%d" % Time.get_ticks_msec()
	var submit_payload: Dictionary = _build_valid_submit_payload(level_key, false)
	var submit_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(submit_payload))
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var publish_result: Variant = await OnlineSession.call_rpc("publish_level", JSON.stringify({"key": level_key}))
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result is Dictionary).is_true()

	var my_levels_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(my_levels_result).is_not_null()
	assert_bool(my_levels_result is Dictionary).is_true()

	var my_levels: Array = (my_levels_result as Dictionary).get("levels", []) as Array
	var my_entry: Dictionary = _find_level_entry(my_levels, level_key)
	assert_bool(not my_entry.is_empty()).is_true()

	var my_value: Dictionary = my_entry.get("value", {}) as Dictionary
	assert_str(str(my_value.get("created_at", ""))).is_not_empty()
	assert_str(str(my_value.get("updated_at", ""))).is_not_empty()
	assert_str(str(my_value.get("published_at", ""))).is_not_empty()

	var all_levels_result: Variant = await OnlineSession.call_rpc("list_all_levels", JSON.stringify({"limit": 100}))
	assert_object(all_levels_result).is_not_null()
	assert_bool(all_levels_result is Dictionary).is_true()
	var all_levels: Array = (all_levels_result as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(all_levels, level_key)).is_true()

	# Published levels are immutable by design.
	var resubmit_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(submit_payload))
	assert_bool(resubmit_result == null).is_true()

	var delete_result: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_result).is_not_null()


func test_published_level_cannot_be_edited() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var level_key := "it_local_publish_immutable_%d" % Time.get_ticks_msec()
	var original_description := "original description before publish"
	var edited_description := "edited description after publish"

	var submit_payload: Dictionary = _build_valid_submit_payload(level_key, false)
	submit_payload["description"] = original_description
	var submit_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(submit_payload))
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var publish_result: Variant = await OnlineSession.call_rpc("publish_level", JSON.stringify({"key": level_key}))
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result is Dictionary).is_true()

	var edit_payload: Dictionary = _build_valid_submit_payload(level_key, false)
	edit_payload["description"] = edited_description
	var edit_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(edit_payload))
	assert_bool(edit_result == null).is_true()
	assert_bool("published levels are read-only" in OnlineSession.last_rpc_error.to_lower()).is_true()

	var user_id := str(OnlineSession.session.user_id)
	var get_result: Variant = await OnlineSession.call_rpc(
		"get_level",
		JSON.stringify({"user_id": user_id, "key": level_key})
	)
	assert_object(get_result).is_not_null()
	assert_bool(get_result is Dictionary).is_true()

	var value: Dictionary = (get_result as Dictionary).get("value", {}) as Dictionary
	assert_str(str(value.get("description", ""))).is_equal(original_description)
	assert_str(str(value.get("published_at", ""))).is_not_empty()

	var delete_result: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_result).is_not_null()


func test_submit_level_with_publish_accepts_float_encoded_numbers() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var level_key := "it_local_publish_float_%d" % Time.get_ticks_msec()
	var submit_payload: Dictionary = _build_valid_submit_payload(level_key, true)
	var float_payload_variant: Variant = _to_float_encoded_numbers(submit_payload)
	assert_bool(float_payload_variant is Dictionary).is_true()
	var float_payload: Dictionary = float_payload_variant as Dictionary

	var submit_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(float_payload))
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var my_levels_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(my_levels_result).is_not_null()
	assert_bool(my_levels_result is Dictionary).is_true()

	var my_levels: Array = (my_levels_result as Dictionary).get("levels", []) as Array
	var my_entry: Dictionary = _find_level_entry(my_levels, level_key)
	assert_bool(not my_entry.is_empty()).is_true()
	var my_value: Dictionary = my_entry.get("value", {}) as Dictionary
	assert_str(str(my_value.get("published_at", ""))).is_not_empty()

	var delete_result: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_result).is_not_null()


func test_loaded_level_numbers_are_ints_not_floats() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var level_key := "it_local_int_parse_%d" % Time.get_ticks_msec()
	var submit_result: Variant = await OnlineSession.call_rpc(
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(level_key, false))
	)
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var my_levels_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(my_levels_result).is_not_null()
	assert_bool(my_levels_result is Dictionary).is_true()
	var my_levels: Array = (my_levels_result as Dictionary).get("levels", []) as Array
	var my_entry: Dictionary = _find_level_entry(my_levels, level_key)
	assert_bool(not my_entry.is_empty()).is_true()
	var my_value: Dictionary = my_entry.get("value", {}) as Dictionary
	_assert_level_numbers_are_ints(my_value)

	var user_id := str(OnlineSession.session.user_id)
	var get_result: Variant = await OnlineSession.call_rpc(
		"get_level",
		JSON.stringify({"user_id": user_id, "key": level_key})
	)
	assert_object(get_result).is_not_null()
	assert_bool(get_result is Dictionary).is_true()
	var get_value: Dictionary = (get_result as Dictionary).get("value", {}) as Dictionary
	_assert_level_numbers_are_ints(get_value)

	var delete_result: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_result).is_not_null()


func test_submit_level_rejects_duplicate_name_for_same_user() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var level_a := "it_dup_a_%d" % Time.get_ticks_msec()
	var level_b := "it_dup_b_%d" % Time.get_ticks_msec()

	var submit_a: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(_build_valid_submit_payload(level_a, false)))
	assert_object(submit_a).is_not_null()
	assert_bool(submit_a is Dictionary).is_true()

	var submit_b: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(_build_valid_submit_payload(level_b, false)))
	assert_object(submit_b).is_not_null()
	assert_bool(submit_b is Dictionary).is_true()

	var rename_payload: Dictionary = _build_valid_submit_payload(level_a, false)
	rename_payload["key"] = level_b
	var rename_result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(rename_payload))
	assert_bool(rename_result == null).is_true()

	var delete_a: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_a}))
	assert_object(delete_a).is_not_null()
	var delete_b: Variant = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": level_b}))
	assert_object(delete_b).is_not_null()


func test_submit_level_rejects_profane_level_name() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var payload: Dictionary = _build_valid_submit_payload("fuck", false)
	var result: Variant = await OnlineSession.call_rpc("submit_level", JSON.stringify(payload))
	assert_bool(result == null).is_true()
	assert_bool("name contains prohibited content" in OnlineSession.last_rpc_error.to_lower()).is_true()


func _load_level_creator() -> LevelCreator:
	return auto_free(load(LEVEL_CREATOR_SCENE).instantiate()) as LevelCreator


func _build_minimal_valid_level(creator: LevelCreator) -> void:
	var world: TileWorld = creator.world
	var grid_size: int = creator.grid_manager.grid_size

	_add_edge_tile(world, grid_size, Vector2i(-1, 1), "portal", ComponentRegistry.START)
	_add_edge_tile(world, grid_size, Vector2i(grid_size, 1), "cat1", ComponentRegistry.END)
	_add_room_tile(
		world,
		Vector2i(0, 1),
		"EW.png",
		[ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.WEST]
	)
	_add_room_tile(
		world,
		Vector2i(1, 1),
		"EW.png",
		[ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.WEST]
	)

	world.commit()


func _add_edge_tile(world: TileWorld, grid_size: int, pos: Vector2i, sprite: String, role_component: String) -> void:
	var entity_id := world.create_entity(pos.x, pos.y, sprite)
	world.add(ComponentRegistry.WALKABLE, entity_id)
	world.add(role_component, entity_id)
	var inward_component := LevelConfig.edge_inward_component(pos, grid_size)
	if not inward_component.is_empty():
		world.add(inward_component, entity_id)


func _add_room_tile(world: TileWorld, pos: Vector2i, sprite: String, components: Array[String]) -> void:
	var entity_id := world.create_entity(pos.x, pos.y, sprite)
	for component in components:
		world.add(component, entity_id)


func _has_level_key(levels: Array, expected_key: String) -> bool:
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		if _level_key(entry) == expected_key:
			return true
	return false


func _find_level_entry(levels: Array, expected_key: String) -> Dictionary:
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		if _level_key(entry) == expected_key:
			return entry
	return {}


func _build_valid_submit_payload(level_key: String, publish: bool) -> Dictionary:
	var payload := {
		"name": level_key,
		"description": "integration publish smoke",
		"grid_size": 4,
		"x": [-1, 4, 0, 1],
		"y": [1, 1, 1, 1],
		"sprite": ["portal", "cat1", "EW.png", "EW.png"],
		"start": [0],
		"end": [1],
		"walkable": [0, 1, 2, 3],
		"east": [0, 2, 3],
		"west": [1, 2, 3],
	}
	if publish:
		# Server treats this only as intent; timestamp is assigned server-side.
		payload["published_at"] = "2000-01-01T00:00:00Z"
	return payload


func _to_float_encoded_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var output := {}
		for key in (value as Dictionary).keys():
			output[key] = _to_float_encoded_numbers((value as Dictionary)[key])
		return output
	if value is Array:
		var output: Array = []
		for item in value as Array:
			output.append(_to_float_encoded_numbers(item))
		return output
	if value is int:
		return float(value)
	return value


func _assert_level_numbers_are_ints(level_value: Dictionary) -> void:
	assert_bool(level_value.get("grid_size", null) is int).is_true()
	var array_keys := ["x", "y", "start", "end", "walkable", "north", "east", "south", "west", "blocked"]
	for key in array_keys:
		var value_variant: Variant = level_value.get(key, null)
		if value_variant == null:
			continue
		assert_bool(value_variant is Array).is_true()
		if value_variant is Array:
			for item in value_variant as Array:
				assert_bool(item is int).is_true()


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()
