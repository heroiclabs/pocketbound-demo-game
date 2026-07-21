@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const COMMUNITY_LEVELS_SCENE := "res://scenes/community_levels.tscn"
const FRIEND_STATE_FRIEND := 0


func test_community_levels_ranking_button_sorts_by_score_desc() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var viewer_session := await client.authenticate_device_async("it-community-rank-viewer-%s" % suffix)
	var owner_session := await client.authenticate_device_async("it-community-rank-owner-%s" % suffix)
	var voter_a_session := await client.authenticate_device_async("it-community-rank-voter-a-%s" % suffix)
	var voter_b_session := await client.authenticate_device_async("it-community-rank-voter-b-%s" % suffix)
	assert_object(viewer_session).is_not_null()
	assert_bool(viewer_session.is_exception()).is_false()
	assert_bool(viewer_session.is_valid()).is_true()
	assert_object(owner_session).is_not_null()
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(owner_session.is_valid()).is_true()
	assert_object(voter_a_session).is_not_null()
	assert_bool(voter_a_session.is_exception()).is_false()
	assert_bool(voter_a_session.is_valid()).is_true()
	assert_object(voter_b_session).is_not_null()
	assert_bool(voter_b_session.is_exception()).is_false()
	assert_bool(voter_b_session.is_valid()).is_true()

	var invite_result := await client.add_friends_async(viewer_session, [str(owner_session.user_id)], null)
	assert_object(invite_result).is_not_null()
	assert_bool(invite_result.is_exception()).is_false()
	var accept_result := await client.add_friends_async(owner_session, [str(viewer_session.user_id)], null)
	assert_object(accept_result).is_not_null()
	assert_bool(accept_result.is_exception()).is_false()

	var viewer_friends = await client.list_friends_async(viewer_session, null, 100, null)
	assert_object(viewer_friends).is_not_null()
	assert_bool(viewer_friends.is_exception()).is_false()
	assert_int(_friend_state_for(viewer_friends.friends, str(owner_session.user_id))).is_equal(FRIEND_STATE_FRIEND)

	var low_key := "aaa_it_community_rank_%s" % suffix
	var high_key := "zzz_it_community_rank_%s" % suffix

	var submit_low: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(low_key))
	)
	assert_object(submit_low).is_not_null()
	assert_bool(submit_low.is_exception()).is_false()

	var publish_low: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"publish_level",
		JSON.stringify({"key": low_key})
	)
	assert_object(publish_low).is_not_null()
	assert_bool(publish_low.is_exception()).is_false()

	var submit_high: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(high_key))
	)
	assert_object(submit_high).is_not_null()
	assert_bool(submit_high.is_exception()).is_false()

	var publish_high: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"publish_level",
		JSON.stringify({"key": high_key})
	)
	assert_object(publish_high).is_not_null()
	assert_bool(publish_high.is_exception()).is_false()

	var vote_high_a: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_a_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": high_key,
			"vote": "like",
		})
	)
	assert_object(vote_high_a).is_not_null()
	assert_bool(vote_high_a.is_exception()).is_false()

	var vote_high_b: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_b_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": high_key,
			"vote": "like",
		})
	)
	assert_object(vote_high_b).is_not_null()
	assert_bool(vote_high_b.is_exception()).is_false()

	var vote_low_a: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_a_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": low_key,
			"vote": "dislike",
		})
	)
	assert_object(vote_low_a).is_not_null()
	assert_bool(vote_low_a.is_exception()).is_false()

	OnlineSession.client = client
	OnlineSession.session = viewer_session

	var runner := scene_runner(_load_community_levels())
	await runner.simulate_frames(3)

	var community_levels := runner.scene() as CanvasLayer
	assert_object(community_levels).is_not_null()
	runner.invoke("open")
	await _wait_until(
		runner,
		func() -> bool:
			var entries_variant: Variant = community_levels.get("_entries")
			return entries_variant is Array and (entries_variant as Array).size() == 2,
		900,
		"Community levels did not load expected entries."
	)

	var initial_entries: Array = community_levels.get("_entries") as Array
	assert_int(initial_entries.size()).is_equal(2)
	assert_str(_level_key(initial_entries[0] as Dictionary)).is_equal(low_key)
	assert_str(_level_key(initial_entries[1] as Dictionary)).is_equal(high_key)

	var ranking_btn := community_levels.find_child("ListFilterBestScore", true, false) as Button
	assert_object(ranking_btn).is_not_null()
	ranking_btn.emit_signal("pressed")
	await runner.simulate_frames(1)

	var ranked_entries: Array = community_levels.get("_entries") as Array
	assert_int(ranked_entries.size()).is_equal(2)
	assert_str(_level_key(ranked_entries[0] as Dictionary)).is_equal(high_key)
	assert_str(_level_key(ranked_entries[1] as Dictionary)).is_equal(low_key)

	var delete_low: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"delete_level",
		JSON.stringify({"key": low_key})
	)
	assert_object(delete_low).is_not_null()
	assert_bool(delete_low.is_exception()).is_false()

	var delete_high: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"delete_level",
		JSON.stringify({"key": high_key})
	)
	assert_object(delete_high).is_not_null()
	assert_bool(delete_high.is_exception()).is_false()

	var remove_viewer = await client.delete_friends_async(viewer_session, [str(owner_session.user_id)], null)
	assert_object(remove_viewer).is_not_null()
	assert_bool(remove_viewer.is_exception()).is_false()
	var remove_owner = await client.delete_friends_async(owner_session, [str(viewer_session.user_id)], null)
	assert_object(remove_owner).is_not_null()
	assert_bool(remove_owner.is_exception()).is_false()

	OnlineSession.session = null
	OnlineSession.client = null

	await client.delete_account_async(voter_b_session)
	await client.delete_account_async(voter_a_session)
	await client.delete_account_async(owner_session)
	await client.delete_account_async(viewer_session)


func _load_community_levels() -> CanvasLayer:
	return auto_free(load(COMMUNITY_LEVELS_SCENE).instantiate()) as CanvasLayer


func _wait_until(runner, predicate: Callable, max_frames: int, failure_message: String) -> void:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return
		await runner.simulate_frames(1)
	assert_bool(bool(predicate.call())).override_failure_message(failure_message).is_true()


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


func _level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "community ranking integration",
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
