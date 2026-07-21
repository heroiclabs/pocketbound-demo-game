@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const LEVEL_PLAYER_SCENE := "res://level_player/level_player.tscn"


func test_get_level_returns_owner_username() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var session_username := str(OnlineSession.session.username).strip_edges()
	assert_str(session_username).is_not_empty()

	var level_key := "it_username_get_%d" % Time.get_ticks_msec()
	var submit_result: Variant = await OnlineSession.call_rpc(
		"submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var user_id := str(OnlineSession.session.user_id)
	var get_result: Variant = await OnlineSession.call_rpc(
		"get_level", JSON.stringify({"user_id": user_id, "key": level_key})
	)
	assert_object(get_result).is_not_null()
	assert_bool(get_result is Dictionary).is_true()

	var response := get_result as Dictionary
	var response_username := str(response.get("username", "")).strip_edges()
	assert_str(response_username).is_equal(session_username)

	var delete_result: Variant = await OnlineSession.call_rpc(
		"delete_level", JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()


func test_list_my_levels_returns_username() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var session_username := str(OnlineSession.session.username).strip_edges()
	assert_str(session_username).is_not_empty()

	var level_key := "it_username_my_%d" % Time.get_ticks_msec()
	var submit_result: Variant = await OnlineSession.call_rpc(
		"submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var list_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(list_result).is_not_null()
	assert_bool(list_result is Dictionary).is_true()

	var levels: Array = (list_result as Dictionary).get("levels", []) as Array
	var entry: Dictionary = _find_level_entry(levels, level_key)
	assert_bool(not entry.is_empty()).override_failure_message(
		"Level '%s' not found in list_my_levels response" % level_key
	).is_true()

	var entry_username := str(entry.get("username", "")).strip_edges()
	assert_str(entry_username).is_equal(session_username)

	var delete_result: Variant = await OnlineSession.call_rpc(
		"delete_level", JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()


func test_list_all_levels_returns_username() -> void:
	OnlineSession.session = null
	OnlineSession.client = null
	await OnlineSession.start(true)

	var session_username := str(OnlineSession.session.username).strip_edges()
	assert_str(session_username).is_not_empty()

	var level_key := "it_username_all_%d" % Time.get_ticks_msec()
	var submit_result: Variant = await OnlineSession.call_rpc(
		"submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result is Dictionary).is_true()

	var publish_result: Variant = await OnlineSession.call_rpc(
		"publish_level", JSON.stringify({"key": level_key})
	)
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result is Dictionary).is_true()

	var list_result: Variant = await OnlineSession.call_rpc(
		"list_all_levels", JSON.stringify({"limit": 100})
	)
	assert_object(list_result).is_not_null()
	assert_bool(list_result is Dictionary).is_true()

	var levels: Array = (list_result as Dictionary).get("levels", []) as Array
	var entry: Dictionary = _find_level_entry(levels, level_key)
	assert_bool(not entry.is_empty()).override_failure_message(
		"Level '%s' not found in list_all_levels response" % level_key
	).is_true()

	var entry_username := str(entry.get("username", "")).strip_edges()
	assert_str(entry_username).is_equal(session_username)

	var delete_result: Variant = await OnlineSession.call_rpc(
		"delete_level", JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()


func test_list_friend_levels_returns_publisher_username() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session_a := await client.authenticate_device_async("it-username-fl-a-%s" % suffix)
	var session_b := await client.authenticate_device_async("it-username-fl-b-%s" % suffix)

	assert_object(session_a).is_not_null()
	assert_bool(session_a.is_exception()).is_false()
	assert_object(session_b).is_not_null()
	assert_bool(session_b.is_exception()).is_false()

	var publisher_username := str(session_b.username).strip_edges()
	assert_str(publisher_username).is_not_empty()

	var invite_result := await client.add_friends_async(session_a, [str(session_b.user_id)], null)
	assert_bool(invite_result.is_exception()).is_false()
	var accept_result := await client.add_friends_async(session_b, [str(session_a.user_id)], null)
	assert_bool(accept_result.is_exception()).is_false()

	var level_key := "it_username_fl_%s" % suffix
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session_b, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_bool(submit_result.is_exception()).is_false()
	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session_b, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_bool(publish_result.is_exception()).is_false()

	var list_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session_a, "list_friend_levels", JSON.stringify({"limit": 100})
	)
	assert_bool(list_result.is_exception()).is_false()

	var payload_variant: Variant = JSON.parse_string(list_result.payload)
	assert_bool(payload_variant is Dictionary).is_true()
	var levels: Array = (payload_variant as Dictionary).get("levels", []) as Array
	var entry: Dictionary = _find_level_entry(levels, level_key)
	assert_bool(not entry.is_empty()).override_failure_message(
		"Level '%s' not found in list_friend_levels response" % level_key
	).is_true()

	var entry_username := str(entry.get("username", "")).strip_edges()
	assert_str(entry_username).is_equal(publisher_username)

	await client.rpc_async(session_b, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_friends_async(session_a, [str(session_b.user_id)], null)
	await client.delete_friends_async(session_b, [str(session_a.user_id)], null)
	await client.delete_account_async(session_b)
	await client.delete_account_async(session_a)


func test_resolve_creator_name_uses_response_username() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()

	level_player.set("_play_source", "community")
	var level_data := {"name": "Test Level"}
	var level_response := {"user_id": "00000000-0000-0000-0000-000000000000", "username": "CoolPlayer42"}

	level_player._apply_level_metadata(level_data, level_response)
	await runner.simulate_frames(1)

	var creator_label := level_player.get("_creator_label") as Label
	assert_object(creator_label).is_not_null()
	assert_str(creator_label.text).is_equal("CoolPlayer42")


func test_resolve_creator_name_falls_back_without_username() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()

	level_player.set("_play_source", "community")
	var level_data := {"name": "Test Level"}
	var level_response := {"user_id": "abcd1234-5678-9012-3456-789012345678"}

	level_player._apply_level_metadata(level_data, level_response)
	await runner.simulate_frames(1)

	var creator_label := level_player.get("_creator_label") as Label
	assert_object(creator_label).is_not_null()
	assert_str(creator_label.text).is_equal("abcd1234")


func test_resolve_creator_name_returns_heroic_labs_for_campaign() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()

	level_player.set("_play_source", "campaign")
	var level_data := {"name": "Campaign Level"}
	var level_response := {"user_id": "some-uuid", "username": "SomeUser"}

	level_player._apply_level_metadata(level_data, level_response)
	await runner.simulate_frames(1)

	var creator_label := level_player.get("_creator_label") as Label
	assert_object(creator_label).is_not_null()
	assert_str(creator_label.text).is_equal("Heroic Labs")


func _load_level_player() -> LevelPlayer:
	return auto_free(load(LEVEL_PLAYER_SCENE).instantiate()) as LevelPlayer


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "username integration test",
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


func _find_level_entry(levels: Array, expected_key: String) -> Dictionary:
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		if _level_key(entry) == expected_key:
			return entry
	return {}


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()
