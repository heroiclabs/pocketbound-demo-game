extends GdUnitTestSuite

const FRIEND_STATE_FRIEND := 0


func test_friend_accept_and_friend_level_listing() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session_a := await client.authenticate_device_async("it-friend-a-%s" % suffix)
	var session_b := await client.authenticate_device_async("it-friend-b-%s" % suffix)

	assert_object(session_a).is_not_null()
	assert_bool(session_a.is_exception()).is_false()
	assert_bool(session_a.is_valid()).is_true()
	assert_object(session_b).is_not_null()
	assert_bool(session_b.is_exception()).is_false()
	assert_bool(session_b.is_valid()).is_true()

	var invite_result := await client.add_friends_async(session_a, [str(session_b.user_id)], null)
	assert_object(invite_result).is_not_null()
	assert_bool(invite_result.is_exception()).is_false()

	var accept_result := await client.add_friends_async(session_b, [str(session_a.user_id)], null)
	assert_object(accept_result).is_not_null()
	assert_bool(accept_result.is_exception()).is_false()

	var friends_a = await client.list_friends_async(session_a, null, 100, null)
	assert_object(friends_a).is_not_null()
	assert_bool(friends_a.is_exception()).is_false()
	var state_a := _friend_state_for(friends_a.friends, str(session_b.user_id))
	assert_int(state_a).is_equal(FRIEND_STATE_FRIEND)

	var level_key := "it_friend_level_%s" % suffix
	var submit_payload := _build_valid_submit_payload(level_key)
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(session_b, "submit_level", JSON.stringify(submit_payload))
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result.is_exception()).is_false()

	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(session_b, "publish_level", JSON.stringify({"key": level_key}))
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result.is_exception()).is_false()

	var list_result: NakamaAPI.ApiRpc = await client.rpc_async(session_a, "list_friend_levels", JSON.stringify({"limit": 100}))
	assert_object(list_result).is_not_null()
	assert_bool(list_result.is_exception()).is_false()

	var payload_variant: Variant = JSON.parse_string(list_result.payload)
	assert_bool(payload_variant is Dictionary).is_true()
	var payload: Dictionary = payload_variant as Dictionary
	var levels: Array = payload.get("levels", []) as Array
	assert_bool(_has_friend_level(levels, str(session_b.user_id), level_key)).is_true()

	var delete_level_result: NakamaAPI.ApiRpc = await client.rpc_async(session_b, "delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_level_result).is_not_null()
	assert_bool(delete_level_result.is_exception()).is_false()

	var remove_result_a = await client.delete_friends_async(session_a, [str(session_b.user_id)], null)
	assert_object(remove_result_a).is_not_null()
	assert_bool(remove_result_a.is_exception()).is_false()
	var remove_result_b = await client.delete_friends_async(session_b, [str(session_a.user_id)], null)
	assert_object(remove_result_b).is_not_null()
	assert_bool(remove_result_b.is_exception()).is_false()

	await client.delete_account_async(session_b)
	await client.delete_account_async(session_a)


func test_friend_draft_level_is_not_listed_in_friend_levels() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session_a := await client.authenticate_device_async("it-friend-draft-a-%s" % suffix)
	var session_b := await client.authenticate_device_async("it-friend-draft-b-%s" % suffix)

	assert_object(session_a).is_not_null()
	assert_bool(session_a.is_exception()).is_false()
	assert_bool(session_a.is_valid()).is_true()
	assert_object(session_b).is_not_null()
	assert_bool(session_b.is_exception()).is_false()
	assert_bool(session_b.is_valid()).is_true()

	var invite_result := await client.add_friends_async(session_a, [str(session_b.user_id)], null)
	assert_object(invite_result).is_not_null()
	assert_bool(invite_result.is_exception()).is_false()

	var accept_result := await client.add_friends_async(session_b, [str(session_a.user_id)], null)
	assert_object(accept_result).is_not_null()
	assert_bool(accept_result.is_exception()).is_false()

	var friends_a = await client.list_friends_async(session_a, null, 100, null)
	assert_object(friends_a).is_not_null()
	assert_bool(friends_a.is_exception()).is_false()
	var state_a := _friend_state_for(friends_a.friends, str(session_b.user_id))
	assert_int(state_a).is_equal(FRIEND_STATE_FRIEND)

	var level_key := "it_friend_draft_level_%s" % suffix
	var submit_payload := _build_valid_submit_payload(level_key)
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(session_b, "submit_level", JSON.stringify(submit_payload))
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result.is_exception()).is_false()

	var list_result: NakamaAPI.ApiRpc = await client.rpc_async(session_a, "list_friend_levels", JSON.stringify({"limit": 100}))
	assert_object(list_result).is_not_null()
	assert_bool(list_result.is_exception()).is_false()

	var payload_variant: Variant = JSON.parse_string(list_result.payload)
	assert_bool(payload_variant is Dictionary).is_true()
	var payload: Dictionary = payload_variant as Dictionary
	var levels: Array = payload.get("levels", []) as Array
	assert_bool(_has_friend_level(levels, str(session_b.user_id), level_key)).is_false()

	var delete_level_result: NakamaAPI.ApiRpc = await client.rpc_async(session_b, "delete_level", JSON.stringify({"key": level_key}))
	assert_object(delete_level_result).is_not_null()
	assert_bool(delete_level_result.is_exception()).is_false()

	var remove_result_a = await client.delete_friends_async(session_a, [str(session_b.user_id)], null)
	assert_object(remove_result_a).is_not_null()
	assert_bool(remove_result_a.is_exception()).is_false()
	var remove_result_b = await client.delete_friends_async(session_b, [str(session_a.user_id)], null)
	assert_object(remove_result_b).is_not_null()
	assert_bool(remove_result_b.is_exception()).is_false()

	await client.delete_account_async(session_b)
	await client.delete_account_async(session_a)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "friend level listing test",
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


func _friend_state_for(friends: Array, target_user_id: String) -> int:
	for friend in friends:
		if friend == null or friend.user == null:
			continue
		if str(friend.user.id) != target_user_id:
			continue

		var state_variant: Variant = friend.get("state")
		if state_variant is int or state_variant is float:
			return int(state_variant)
		var state_text := str(state_variant).strip_edges()
		if state_text.is_valid_int():
			return state_text.to_int()
	return -1


func _has_friend_level(levels: Array, owner_id: String, expected_key: String) -> bool:
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		if str(entry.get("user_id", "")) != owner_id:
			continue
		if _level_key(entry) == expected_key:
			return true
	return false


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()
