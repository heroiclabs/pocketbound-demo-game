extends GdUnitTestSuite

const EXPECTED_DEFAULT_LEVEL_KEYS := [
	"Split crown",
	"Short Bend",
	"Box Shuffle",
	"Single shift",
	"The worm",
	"The blocked hallway",
]


func test_new_device_user_starts_with_expected_default_levels() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var device_id := "it-default-levels-%d" % Time.get_ticks_usec()
	var session := await client.authenticate_device_async(device_id)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()
	assert_bool(session.is_valid()).is_true()
	assert_bool(session.created).is_true()

	var rpc_result: NakamaAPI.ApiRpc = await client.rpc_async(session, "list_single_player_levels", "")
	assert_object(rpc_result).is_not_null()
	assert_bool(rpc_result.is_exception()).is_false()

	var payload_variant: Variant = JSON.parse_string(rpc_result.payload)
	assert_bool(payload_variant is Dictionary).is_true()

	var payload: Dictionary = payload_variant as Dictionary
	var levels: Array = payload.get("levels", []) as Array
	assert_int(levels.size()).is_equal(6)

	var keys := _extract_level_keys(levels)
	assert_int(keys.size()).is_equal(6)
	for expected_key in EXPECTED_DEFAULT_LEVEL_KEYS:
		assert_bool(keys.has(expected_key)).is_true()

	var my_levels_result: NakamaAPI.ApiRpc = await client.rpc_async(session, "list_my_levels", "")
	assert_object(my_levels_result).is_not_null()
	assert_bool(my_levels_result.is_exception()).is_false()
	var my_levels_payload_variant: Variant = JSON.parse_string(my_levels_result.payload)
	assert_bool(my_levels_payload_variant is Dictionary).is_true()
	var my_levels_payload: Dictionary = my_levels_payload_variant as Dictionary
	var my_levels: Array = my_levels_payload.get("levels", []) as Array
	assert_int(my_levels.size()).is_equal(0)

	var get_level_payload := JSON.stringify({
		"user_id": session.user_id,
		"key": "Single shift",
	})
	var get_level_result: NakamaAPI.ApiRpc = await client.rpc_async(session, "get_level", get_level_payload)
	assert_object(get_level_result).is_not_null()
	assert_bool(get_level_result.is_exception()).is_false()

	var get_level_payload_variant: Variant = JSON.parse_string(get_level_result.payload)
	assert_bool(get_level_payload_variant is Dictionary).is_true()
	var get_level_response: Dictionary = get_level_payload_variant as Dictionary
	var level_value: Dictionary = get_level_response.get("value", {}) as Dictionary
	assert_str(str(level_value.get("name", ""))).is_equal("Single shift")

	await client.delete_account_async(session)


func _extract_level_keys(levels: Array) -> Array[String]:
	var keys: Array[String] = []
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var key := _level_key(entry)
		if key.is_empty():
			continue
		keys.append(key)
	return keys


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()
