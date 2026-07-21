@warning_ignore_start("redundant_await")
extends GdUnitTestSuite


func test_full_lifecycle_create_publish_score_vote_delete() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var creator_session := await client.authenticate_device_async("it-lifecycle-creator-%s" % suffix)
	var player_a := await client.authenticate_device_async("it-lifecycle-player-a-%s" % suffix)
	var player_b := await client.authenticate_device_async("it-lifecycle-player-b-%s" % suffix)
	assert_bool(creator_session.is_exception()).is_false()
	assert_bool(player_a.is_exception()).is_false()
	assert_bool(player_b.is_exception()).is_false()

	# ── Step 1: Create and publish a level ──
	var level_key := "it_lifecycle_%s" % suffix
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(
		creator_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_bool(submit_result.is_exception()).is_false()

	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(
		creator_session, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_bool(publish_result.is_exception()).is_false()

	# ── Step 2: Verify another player can fetch the published level ──
	var creator_id := str(creator_session.user_id)
	var get_published: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "get_level", JSON.stringify({
			"user_id": creator_id, "key": level_key,
		})
	)
	assert_bool(get_published.is_exception()).is_false()
	var get_pub_data := JSON.parse_string(get_published.payload) as Dictionary
	var get_pub_value := get_pub_data.get("value", {}) as Dictionary
	assert_str(str(get_pub_value.get("published_at", ""))).is_not_empty()

	# ── Step 3: Two players submit scores ──

	var score_a: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "submit_score", JSON.stringify({
			"level_owner_id": creator_id, "level_key": level_key,
			"time_ms": 3500, "slide_count": 9,
		})
	)
	assert_bool(score_a.is_exception()).is_false()
	var score_a_data := JSON.parse_string(score_a.payload) as Dictionary
	assert_int(int(score_a_data.get("rank", 0))).is_equal(1)

	var score_b: NakamaAPI.ApiRpc = await client.rpc_async(
		player_b, "submit_score", JSON.stringify({
			"level_owner_id": creator_id, "level_key": level_key,
			"time_ms": 5000, "slide_count": 14,
		})
	)
	assert_bool(score_b.is_exception()).is_false()
	var score_b_data := JSON.parse_string(score_b.payload) as Dictionary
	assert_int(int(score_b_data.get("rank", 0))).is_equal(2)

	# ── Step 4: Verify leaderboard state ──
	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "get_leaderboard", JSON.stringify({
			"level_owner_id": creator_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()
	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	assert_int((lb.get("entries", []) as Array).size()).is_equal(2)
	assert_int(int(lb.get("play_count", 0))).is_equal(2)
	assert_int(int(lb.get("player_rank", 0))).is_equal(1)

	# ── Step 5: Vote on the level ──
	var vote_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "submit_level_vote", JSON.stringify({
			"level_owner_id": creator_id,
			"level_key": level_key,
			"vote": "like",
		})
	)
	assert_bool(vote_result.is_exception()).is_false()
	var vote_data := JSON.parse_string(vote_result.payload) as Dictionary
	assert_int(int(vote_data.get("likes", 0))).is_equal(1)

	# ── Step 6: Verify get_level includes votes ──
	var get_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "get_level", JSON.stringify({
			"user_id": creator_id, "key": level_key,
		})
	)
	assert_bool(get_result.is_exception()).is_false()
	var level_data := JSON.parse_string(get_result.payload) as Dictionary
	var level_value := level_data.get("value", {}) as Dictionary
	assert_int(int(level_value.get("likes", 0))).is_equal(1)

	# ── Step 7: Delete level and verify it disappears ──
	var delete_result: NakamaAPI.ApiRpc = await client.rpc_async(
		creator_session, "delete_level", JSON.stringify({"key": level_key})
	)
	assert_bool(delete_result.is_exception()).is_false()

	var post_delete: NakamaAPI.ApiRpc = await client.rpc_async(
		player_a, "get_level", JSON.stringify({
			"user_id": creator_id, "key": level_key,
		})
	)
	# get_level should fail or return null for a deleted level
	assert_bool(post_delete.is_exception()).is_true()

	await client.delete_account_async(player_b)
	await client.delete_account_async(player_a)
	await client.delete_account_async(creator_session)


func test_draft_edit_resubmit_preserves_changes() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-lifecycle-edit-%s" % suffix)
	assert_bool(session.is_exception()).is_false()

	var level_key := "it_edit_%s" % suffix
	var user_id := str(session.user_id)

	# Initial submit with "version 1"
	var payload_1 := _build_valid_submit_payload(level_key)
	payload_1["description"] = "version 1"
	var submit_1: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "submit_level", JSON.stringify(payload_1)
	)
	assert_bool(submit_1.is_exception()).is_false()

	# Re-submit with updated description only (grid/tiles unchanged)
	var payload_2 := _build_valid_submit_payload(level_key)
	payload_2["description"] = "version 2"
	var submit_2: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "submit_level", JSON.stringify(payload_2)
	)
	assert_bool(submit_2.is_exception()).is_false()

	# Verify via get_level
	var get_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_level", JSON.stringify({"user_id": user_id, "key": level_key})
	)
	assert_bool(get_result.is_exception()).is_false()
	var value := (JSON.parse_string(get_result.payload) as Dictionary).get("value", {}) as Dictionary
	assert_str(str(value.get("description", ""))).is_equal("version 2")

	# Third edit with another description change
	var payload_3 := _build_valid_submit_payload(level_key)
	payload_3["description"] = "version 3"
	var submit_3: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "submit_level", JSON.stringify(payload_3)
	)
	assert_bool(submit_3.is_exception()).is_false()

	var get_result_2: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_level", JSON.stringify({"user_id": user_id, "key": level_key})
	)
	assert_bool(get_result_2.is_exception()).is_false()
	var value_2 := (JSON.parse_string(get_result_2.payload) as Dictionary).get("value", {}) as Dictionary
	assert_str(str(value_2.get("description", ""))).is_equal("version 3")

	await client.rpc_async(session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(session)


func test_delete_published_level_removes_from_friend_levels() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var creator_session := await client.authenticate_device_async("it-lifecycle-del-creator-%s" % suffix)
	var friend_session := await client.authenticate_device_async("it-lifecycle-del-friend-%s" % suffix)
	assert_bool(creator_session.is_exception()).is_false()
	assert_bool(friend_session.is_exception()).is_false()

	# Make them friends
	await client.add_friends_async(friend_session, [str(creator_session.user_id)], null)
	await client.add_friends_async(creator_session, [str(friend_session.user_id)], null)

	# Creator publishes a level
	var level_key := "it_del_cascade_%s" % suffix
	await client.rpc_async(creator_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(creator_session, "publish_level", JSON.stringify({"key": level_key}))

	# Friend can see it in friend_levels
	var pre_delete: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_session, "list_friend_levels", JSON.stringify({"limit": 100})
	)
	assert_bool(pre_delete.is_exception()).is_false()
	var pre_levels: Array = (JSON.parse_string(pre_delete.payload) as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(pre_levels, level_key)).override_failure_message(
		"Level '%s' not visible in friend_levels before delete" % level_key
	).is_true()

	# Delete the level
	await client.rpc_async(creator_session, "delete_level", JSON.stringify({"key": level_key}))

	# Should no longer appear in friend_levels
	var post_delete: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_session, "list_friend_levels", JSON.stringify({"limit": 100})
	)
	assert_bool(post_delete.is_exception()).is_false()
	var post_levels: Array = (JSON.parse_string(post_delete.payload) as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(post_levels, level_key)).override_failure_message(
		"Deleted level '%s' still visible in friend_levels" % level_key
	).is_false()

	# Should no longer appear in list_all_levels
	var post_all: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_session, "list_all_levels", JSON.stringify({"limit": 100})
	)
	assert_bool(post_all.is_exception()).is_false()
	var post_all_levels: Array = (JSON.parse_string(post_all.payload) as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(post_all_levels, level_key)).override_failure_message(
		"Deleted level '%s' still visible in list_all_levels" % level_key
	).is_false()

	# Should no longer appear in my_levels for the creator
	var post_my: NakamaAPI.ApiRpc = await client.rpc_async(
		creator_session, "list_my_levels", ""
	)
	assert_bool(post_my.is_exception()).is_false()
	var post_my_levels: Array = (JSON.parse_string(post_my.payload) as Dictionary).get("levels", []) as Array
	assert_bool(_has_level_key(post_my_levels, level_key)).override_failure_message(
		"Deleted level '%s' still visible in list_my_levels" % level_key
	).is_false()

	# Cleanup friendships
	await client.delete_friends_async(friend_session, [str(creator_session.user_id)], null)
	await client.delete_friends_async(creator_session, [str(friend_session.user_id)], null)
	await client.delete_account_async(friend_session)
	await client.delete_account_async(creator_session)


func test_multi_user_publish_score_and_vote_then_list_ordering() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var creator := await client.authenticate_device_async("it-lifecycle-multi-creator-%s" % suffix)
	var player_1 := await client.authenticate_device_async("it-lifecycle-multi-p1-%s" % suffix)
	var player_2 := await client.authenticate_device_async("it-lifecycle-multi-p2-%s" % suffix)
	var player_3 := await client.authenticate_device_async("it-lifecycle-multi-p3-%s" % suffix)
	assert_bool(creator.is_exception()).is_false()
	assert_bool(player_1.is_exception()).is_false()
	assert_bool(player_2.is_exception()).is_false()
	assert_bool(player_3.is_exception()).is_false()

	var level_key := "it_multi_%s" % suffix
	await client.rpc_async(creator, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(creator, "publish_level", JSON.stringify({"key": level_key}))

	var creator_id := str(creator.user_id)

	# All three players score the level with different times
	await client.rpc_async(player_1, "submit_score", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key,
		"time_ms": 7000, "slide_count": 18,
	}))
	await client.rpc_async(player_2, "submit_score", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key,
		"time_ms": 2500, "slide_count": 6,
	}))
	await client.rpc_async(player_3, "submit_score", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key,
		"time_ms": 5000, "slide_count": 12,
	}))

	# All three vote: 2 likes, 1 dislike
	await client.rpc_async(player_1, "submit_level_vote", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key, "vote": "like",
	}))
	await client.rpc_async(player_2, "submit_level_vote", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key, "vote": "like",
	}))
	await client.rpc_async(player_3, "submit_level_vote", JSON.stringify({
		"level_owner_id": creator_id, "level_key": level_key, "vote": "dislike",
	}))

	# Verify leaderboard has 3 entries ranked correctly
	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_3, "get_leaderboard", JSON.stringify({
			"level_owner_id": creator_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()
	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	var entries: Array = lb.get("entries", []) as Array
	assert_int(entries.size()).is_equal(3)
	assert_int(int((entries[0] as Dictionary).get("time_ms", 0))).is_equal(2500)
	assert_int(int((entries[1] as Dictionary).get("time_ms", 0))).is_equal(5000)
	assert_int(int((entries[2] as Dictionary).get("time_ms", 0))).is_equal(7000)

	# player_3 queried, should be rank 2 (5000ms)
	assert_int(int(lb.get("player_rank", 0))).is_equal(2)
	assert_int(int(lb.get("play_count", 0))).is_equal(3)

	# Verify vote counts via get_level
	var level_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_1, "get_level", JSON.stringify({
			"user_id": creator_id, "key": level_key,
		})
	)
	assert_bool(level_result.is_exception()).is_false()
	var level_value := (JSON.parse_string(level_result.payload) as Dictionary).get("value", {}) as Dictionary
	assert_int(int(level_value.get("likes", 0))).is_equal(2)
	assert_int(int(level_value.get("dislikes", 0))).is_equal(1)

	await client.rpc_async(creator, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_3)
	await client.delete_account_async(player_2)
	await client.delete_account_async(player_1)
	await client.delete_account_async(creator)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "lifecycle integration test",
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


func _has_level_key(levels: Array, expected_key: String) -> bool:
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
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
