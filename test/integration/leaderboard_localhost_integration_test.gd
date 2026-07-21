@warning_ignore_start("redundant_await")
extends GdUnitTestSuite


func test_submit_score_returns_rank_and_time() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-lb-submit-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-lb-submit-player-%s" % suffix)
	assert_object(owner_session).is_not_null()
	assert_bool(owner_session.is_exception()).is_false()
	assert_object(player_session).is_not_null()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_lb_submit_%s" % suffix
	var submit_level: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_bool(submit_level.is_exception()).is_false()
	var publish_level: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_bool(publish_level.is_exception()).is_false()

	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 5000,
			"slide_count": 12,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_false()

	var payload: Variant = JSON.parse_string(score_result.payload)
	assert_bool(payload is Dictionary).is_true()
	var response := payload as Dictionary
	assert_int(int(response.get("rank", 0))).is_equal(1)
	assert_int(int(response.get("time_ms", 0))).is_equal(5000)
	assert_int(int(response.get("slide_count", 0))).is_equal(12)

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


func test_submit_score_best_operator_keeps_fastest_time() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-lb-best-op-%s" % suffix)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()

	var level_key := "it_lb_best_%s" % suffix
	var submit_level: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_bool(submit_level.is_exception()).is_false()
	var publish_level: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_bool(publish_level.is_exception()).is_false()

	var owner_id := str(session.user_id)

	# First score: 8000ms
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 8000, "slide_count": 20,
	}))

	# Better score: 3000ms — should replace
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 3000, "slide_count": 8,
	}))

	# Worse score: 9000ms — should NOT replace
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 9000, "slide_count": 25,
	}))

	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_leaderboard", JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_object(lb_result).is_not_null()
	assert_bool(lb_result.is_exception()).is_false()

	var lb: Variant = JSON.parse_string(lb_result.payload)
	assert_bool(lb is Dictionary).is_true()
	var lb_dict := lb as Dictionary
	assert_int(int(lb_dict.get("best_time_ms", 0))).is_equal(3000)
	assert_int(int(lb_dict.get("best_slide_count", 0))).is_equal(8)

	var entries: Array = lb_dict.get("entries", []) as Array
	assert_int(entries.size()).is_equal(1)
	assert_int(int((entries[0] as Dictionary).get("time_ms", 0))).is_equal(3000)
	assert_int(int((entries[0] as Dictionary).get("slide_count", 0))).is_equal(8)

	await client.rpc_async(session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(session)


func test_get_leaderboard_all_time_ranks_multiple_players() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-lb-rank-owner-%s" % suffix)
	var fast_player := await client.authenticate_device_async("it-lb-rank-fast-%s" % suffix)
	var mid_player := await client.authenticate_device_async("it-lb-rank-mid-%s" % suffix)
	var slow_player := await client.authenticate_device_async("it-lb-rank-slow-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(fast_player.is_exception()).is_false()
	assert_bool(mid_player.is_exception()).is_false()
	assert_bool(slow_player.is_exception()).is_false()

	var level_key := "it_lb_rank_%s" % suffix
	await client.rpc_async(owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(owner_session, "publish_level", JSON.stringify({"key": level_key}))

	var owner_id := str(owner_session.user_id)
	await client.rpc_async(slow_player, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 10000, "slide_count": 30,
	}))
	await client.rpc_async(fast_player, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 2000, "slide_count": 5,
	}))
	await client.rpc_async(mid_player, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 6000, "slide_count": 15,
	}))

	# Query from mid_player's perspective to also check player_rank
	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		mid_player, "get_leaderboard", JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()

	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	var entries: Array = lb.get("entries", []) as Array
	assert_int(entries.size()).is_equal(3)

	# Sorted ascending by time (fastest first)
	assert_int(int((entries[0] as Dictionary).get("time_ms", 0))).is_equal(2000)
	assert_int(int((entries[1] as Dictionary).get("time_ms", 0))).is_equal(6000)
	assert_int(int((entries[2] as Dictionary).get("time_ms", 0))).is_equal(10000)

	# Ranks should be 1, 2, 3
	assert_int(int((entries[0] as Dictionary).get("rank", 0))).is_equal(1)
	assert_int(int((entries[1] as Dictionary).get("rank", 0))).is_equal(2)
	assert_int(int((entries[2] as Dictionary).get("rank", 0))).is_equal(3)

	# mid_player queried, so player_rank should be 2
	assert_int(int(lb.get("player_rank", 0))).is_equal(2)

	# best_time_ms is the fastest
	assert_int(int(lb.get("best_time_ms", 0))).is_equal(2000)

	# play_count equals total submissions (3 players, 1 each)
	assert_int(int(lb.get("play_count", 0))).is_equal(3)

	# Entries include usernames (not empty)
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		assert_str(str(entry.get("username", "")).strip_edges()).is_not_empty()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(slow_player)
	await client.delete_account_async(mid_player)
	await client.delete_account_async(fast_player)
	await client.delete_account_async(owner_session)


func test_get_leaderboard_tracks_play_count_across_resubmissions() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-lb-playcount-%s" % suffix)
	assert_bool(session.is_exception()).is_false()

	var level_key := "it_lb_plays_%s" % suffix
	await client.rpc_async(session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(session, "publish_level", JSON.stringify({"key": level_key}))

	var owner_id := str(session.user_id)

	# Submit 3 scores from the same player
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 5000, "slide_count": 10,
	}))
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 4000, "slide_count": 8,
	}))
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 6000, "slide_count": 14,
	}))

	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_leaderboard", JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()

	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	# Only 1 entry (same player, "best" operator). play_count = 2 because the
	# third submission (6000ms) was worse than the best (4000ms) and the "best"
	# operator does not increment NumScore for rejected writes.
	assert_int((lb.get("entries", []) as Array).size()).is_equal(1)
	assert_int(int(lb.get("play_count", 0))).is_equal(2)

	await client.rpc_async(session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(session)


func test_get_leaderboard_friends_filter_shows_only_friends() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var level_owner := await client.authenticate_device_async("it-lb-friends-owner-%s" % suffix)
	var friend_a := await client.authenticate_device_async("it-lb-friends-a-%s" % suffix)
	var friend_b := await client.authenticate_device_async("it-lb-friends-b-%s" % suffix)
	var stranger := await client.authenticate_device_async("it-lb-friends-stranger-%s" % suffix)
	assert_bool(level_owner.is_exception()).is_false()
	assert_bool(friend_a.is_exception()).is_false()
	assert_bool(friend_b.is_exception()).is_false()
	assert_bool(stranger.is_exception()).is_false()

	# Make friend_a and friend_b mutual friends
	await client.add_friends_async(friend_a, [str(friend_b.user_id)], null)
	await client.add_friends_async(friend_b, [str(friend_a.user_id)], null)

	var level_key := "it_lb_friends_%s" % suffix
	await client.rpc_async(level_owner, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(level_owner, "publish_level", JSON.stringify({"key": level_key}))

	var owner_id := str(level_owner.user_id)

	# All three play the level
	await client.rpc_async(friend_a, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 4000, "slide_count": 10,
	}))
	await client.rpc_async(friend_b, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 7000, "slide_count": 18,
	}))
	await client.rpc_async(stranger, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 1000, "slide_count": 3,
	}))

	# friend_a asks for "friends" filter — should see self + friend_b, NOT stranger
	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		friend_a, "get_leaderboard", JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "friends",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()

	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	var entries: Array = lb.get("entries", []) as Array
	assert_int(entries.size()).is_equal(2)

	# Sorted ascending by time: friend_a (4000) then friend_b (7000)
	assert_int(int((entries[0] as Dictionary).get("time_ms", 0))).is_equal(4000)
	assert_int(int((entries[1] as Dictionary).get("time_ms", 0))).is_equal(7000)

	# friend_a's player_rank should be 1 in the friends filter
	assert_int(int(lb.get("player_rank", 0))).is_equal(1)

	# Stranger is NOT in the list
	var stranger_username := str(stranger.username).strip_edges()
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		assert_str(str(entry.get("username", ""))).is_not_equal(stranger_username)

	# Cleanup
	await client.rpc_async(level_owner, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_friends_async(friend_a, [str(friend_b.user_id)], null)
	await client.delete_friends_async(friend_b, [str(friend_a.user_id)], null)
	await client.delete_account_async(stranger)
	await client.delete_account_async(friend_b)
	await client.delete_account_async(friend_a)
	await client.delete_account_async(level_owner)


func test_get_leaderboard_returns_empty_for_unplayed_level() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-lb-empty-%s" % suffix)
	assert_bool(session.is_exception()).is_false()

	var level_key := "it_lb_empty_%s" % suffix
	await client.rpc_async(session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(session, "publish_level", JSON.stringify({"key": level_key}))

	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_leaderboard", JSON.stringify({
			"level_owner_id": str(session.user_id),
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()

	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	assert_int((lb.get("entries", []) as Array).size()).is_equal(0)
	assert_int(int(lb.get("player_rank", 0))).is_equal(0)
	assert_int(int(lb.get("play_count", 0))).is_equal(0)

	await client.rpc_async(session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(session)


func test_submit_score_slide_count_appears_in_leaderboard_entries() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-lb-subscore-%s" % suffix)
	assert_bool(session.is_exception()).is_false()

	var level_key := "it_lb_subscore_%s" % suffix
	await client.rpc_async(session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(session, "publish_level", JSON.stringify({"key": level_key}))

	var owner_id := str(session.user_id)
	await client.rpc_async(session, "submit_score", JSON.stringify({
		"level_owner_id": owner_id, "level_key": level_key,
		"time_ms": 7777, "slide_count": 42,
	}))

	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "get_leaderboard", JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()

	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	var entries: Array = lb.get("entries", []) as Array
	assert_int(entries.size()).is_equal(1)

	var entry := entries[0] as Dictionary
	assert_int(int(entry.get("time_ms", 0))).is_equal(7777)
	assert_int(int(entry.get("slide_count", 0))).is_equal(42)
	assert_str(str(entry.get("username", "")).strip_edges()).is_equal(
		str(session.username).strip_edges()
	)

	await client.rpc_async(session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(session)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "leaderboard integration test",
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
