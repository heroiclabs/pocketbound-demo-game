@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const COMMUNITY_LEVELS_SCENE := "res://scenes/community_levels.tscn"
const FRIEND_STATE_FRIEND := 0


func test_switching_from_newest_to_friends_filter_shows_only_friend_levels() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var viewer_session := await client.authenticate_device_async("it-filter-viewer-%s" % suffix)
	var friend_session := await client.authenticate_device_async("it-filter-friend-%s" % suffix)
	var stranger_session := await client.authenticate_device_async("it-filter-stranger-%s" % suffix)
	assert_object(viewer_session).is_not_null()
	assert_bool(viewer_session.is_exception()).is_false()
	assert_bool(viewer_session.is_valid()).is_true()
	assert_object(friend_session).is_not_null()
	assert_bool(friend_session.is_exception()).is_false()
	assert_bool(friend_session.is_valid()).is_true()
	assert_object(stranger_session).is_not_null()
	assert_bool(stranger_session.is_exception()).is_false()
	assert_bool(stranger_session.is_valid()).is_true()

	# Make viewer and friend_session mutual friends
	var invite := await client.add_friends_async(viewer_session, [str(friend_session.user_id)], null)
	assert_object(invite).is_not_null()
	assert_bool(invite.is_exception()).is_false()
	var accept := await client.add_friends_async(friend_session, [str(viewer_session.user_id)], null)
	assert_object(accept).is_not_null()
	assert_bool(accept.is_exception()).is_false()

	# Verify friendship
	var viewer_friends = await client.list_friends_async(viewer_session, null, 100, null)
	assert_object(viewer_friends).is_not_null()
	assert_bool(viewer_friends.is_exception()).is_false()
	assert_int(_friend_state_for(viewer_friends.friends, str(friend_session.user_id))).is_equal(FRIEND_STATE_FRIEND)

	# Friend publishes a level
	var friend_key := "it_filter_friend_level_%s" % suffix
	var submit_friend: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_session,
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(friend_key))
	)
	assert_object(submit_friend).is_not_null()
	assert_bool(submit_friend.is_exception()).is_false()
	var publish_friend: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_session,
		"publish_level",
		JSON.stringify({"key": friend_key})
	)
	assert_object(publish_friend).is_not_null()
	assert_bool(publish_friend.is_exception()).is_false()

	# Stranger publishes a level (should only appear in Newest, not Friends)
	var stranger_key := "it_filter_stranger_level_%s" % suffix
	var submit_stranger: NakamaAPI.ApiRpc = await client.rpc_async(
		stranger_session,
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(stranger_key))
	)
	assert_object(submit_stranger).is_not_null()
	assert_bool(submit_stranger.is_exception()).is_false()
	var publish_stranger: NakamaAPI.ApiRpc = await client.rpc_async(
		stranger_session,
		"publish_level",
		JSON.stringify({"key": stranger_key})
	)
	assert_object(publish_stranger).is_not_null()
	assert_bool(publish_stranger.is_exception()).is_false()

	# Set up scene (default filter is Newest)
	OnlineSession.client = client
	OnlineSession.session = viewer_session

	var runner := scene_runner(_load_community_levels())
	await runner.simulate_frames(3)

	var community_levels := runner.scene() as CanvasLayer
	assert_object(community_levels).is_not_null()
	runner.invoke("open")

	# Wait for Newest tab to load — should contain at least both levels
	await _wait_until(
		runner,
		func() -> bool:
			var entries: Variant = community_levels.get("_entries")
			if not (entries is Array):
				return false
			var arr := entries as Array
			return _has_level_key(arr, friend_key) and _has_level_key(arr, stranger_key),
		900,
		"Newest tab did not load both friend and stranger levels."
	)

	var newest_entries: Array = community_levels.get("_entries") as Array
	assert_bool(_has_level_key(newest_entries, friend_key)).is_true()
	assert_bool(_has_level_key(newest_entries, stranger_key)).is_true()

	# Switch to Friends filter — this is where the crash used to happen
	var friends_btn := community_levels.find_child("ListFilterFriends", true, false) as Button
	assert_object(friends_btn).is_not_null()
	friends_btn.emit_signal("pressed")

	# Wait for Friends tab to load with only friend levels
	await _wait_until(
		runner,
		func() -> bool:
			var entries: Variant = community_levels.get("_entries")
			if not (entries is Array):
				return false
			var arr := entries as Array
			return arr.size() >= 1 and _has_level_key(arr, friend_key),
		900,
		"Friends tab did not load friend levels."
	)

	var friends_entries: Array = community_levels.get("_entries") as Array
	assert_bool(_has_level_key(friends_entries, friend_key)) \
		.override_failure_message("Friend's level should appear in Friends tab.") \
		.is_true()
	assert_bool(_has_level_key(friends_entries, stranger_key)) \
		.override_failure_message("Stranger's level should NOT appear in Friends tab.") \
		.is_false()

	# Switch back to Newest — both levels should reappear
	var newest_btn := community_levels.find_child("ListFilterNewest", true, false) as Button
	assert_object(newest_btn).is_not_null()
	newest_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool:
			var entries: Variant = community_levels.get("_entries")
			if not (entries is Array):
				return false
			var arr := entries as Array
			return _has_level_key(arr, friend_key) and _has_level_key(arr, stranger_key),
		900,
		"Newest tab did not reload both levels after switching back."
	)

	var newest_again: Array = community_levels.get("_entries") as Array
	assert_bool(_has_level_key(newest_again, friend_key)).is_true()
	assert_bool(_has_level_key(newest_again, stranger_key)).is_true()

	# Cleanup
	await client.rpc_async(friend_session, "delete_level", JSON.stringify({"key": friend_key}))
	await client.rpc_async(stranger_session, "delete_level", JSON.stringify({"key": stranger_key}))

	await client.delete_friends_async(viewer_session, [str(friend_session.user_id)], null)
	await client.delete_friends_async(friend_session, [str(viewer_session.user_id)], null)

	OnlineSession.session = null
	OnlineSession.client = null

	await client.delete_account_async(stranger_session)
	await client.delete_account_async(friend_session)
	await client.delete_account_async(viewer_session)


func _load_community_levels() -> CanvasLayer:
	return auto_free(load(COMMUNITY_LEVELS_SCENE).instantiate()) as CanvasLayer


func _wait_until(runner, predicate: Callable, max_frames: int, failure_message: String) -> void:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return
		await runner.simulate_frames(1)
	assert_bool(bool(predicate.call())).override_failure_message(failure_message).is_true()


func _has_level_key(entries: Array, key: String) -> bool:
	for entry in entries:
		if not (entry is Dictionary):
			continue
		if _level_key(entry as Dictionary) == key:
			return true
	return false


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()


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


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "filter switch integration test",
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
