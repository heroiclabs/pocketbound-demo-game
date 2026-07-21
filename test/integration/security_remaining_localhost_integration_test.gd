@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

# ── Finding #11: Orphaned leaderboards after level deletion ──────────────────
# When a level is deleted, its leaderboard persists with stale data.
# Expected: get_leaderboard returns empty entries after the level is deleted.

func test_leaderboard_is_cleaned_up_after_level_delete() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-orphan-lb-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-orphan-lb-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_orphan_lb_%s" % suffix
	await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		owner_session, "publish_level", JSON.stringify({"key": level_key})
	)

	# Submit a score to create the leaderboard.
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 5000,
			"slide_count": 10,
		})
	)
	assert_bool(score_result.is_exception()).is_false()

	# Delete the level.
	var delete_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "delete_level", JSON.stringify({"key": level_key})
	)
	assert_bool(delete_result.is_exception()).is_false()

	# The leaderboard should be empty after the level is deleted.
	var lb_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "get_leaderboard", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_result.is_exception()).is_false()
	var lb := JSON.parse_string(lb_result.payload) as Dictionary
	var entries: Array = lb.get("entries", []) as Array
	assert_int(entries.size()).override_failure_message(
		"Finding #11: Leaderboard still has %d entries after level deletion (orphaned data)" % entries.size()
	).is_equal(0)

	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


# ── Finding #11 (variant): Scores cannot be submitted to a deleted level ─────

func test_submit_score_for_deleted_level_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-delscore-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-delscore-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_delscore_%s" % suffix
	await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		owner_session, "publish_level", JSON.stringify({"key": level_key})
	)

	# Submit one score while level exists — should succeed.
	var first_score: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 5000,
			"slide_count": 10,
		})
	)
	assert_bool(first_score.is_exception()).is_false()

	# Delete the level.
	await client.rpc_async(
		owner_session, "delete_level", JSON.stringify({"key": level_key})
	)

	# Submit another score after deletion — should be rejected.
	var second_score: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 3000,
			"slide_count": 5,
		})
	)
	assert_object(second_score).is_not_null()
	assert_bool(second_score.is_exception()).override_failure_message(
		"Finding #11: Server accepted score for a deleted level"
	).is_true()

	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


# ── Finding #9: Leaderboard ID uniqueness across users ───────────────────────
# Two different users with the same level key should have separate leaderboards.

func test_leaderboard_ids_are_unique_per_user() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_a := await client.authenticate_device_async("it-lbid-owner-a-%s" % suffix)
	var owner_b := await client.authenticate_device_async("it-lbid-owner-b-%s" % suffix)
	var player := await client.authenticate_device_async("it-lbid-player-%s" % suffix)
	assert_bool(owner_a.is_exception()).is_false()
	assert_bool(owner_b.is_exception()).is_false()
	assert_bool(player.is_exception()).is_false()

	# Both owners create a level with the same key name.
	var level_key := "it_lbid_shared_%s" % suffix
	await client.rpc_async(
		owner_a, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		owner_a, "publish_level", JSON.stringify({"key": level_key})
	)
	await client.rpc_async(
		owner_b, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		owner_b, "publish_level", JSON.stringify({"key": level_key})
	)

	# Player submits different scores to each owner's level.
	await client.rpc_async(player, "submit_score", JSON.stringify({
		"level_owner_id": str(owner_a.user_id),
		"level_key": level_key,
		"time_ms": 3000,
		"slide_count": 5,
	}))
	await client.rpc_async(player, "submit_score", JSON.stringify({
		"level_owner_id": str(owner_b.user_id),
		"level_key": level_key,
		"time_ms": 9000,
		"slide_count": 20,
	}))

	# Each leaderboard should have exactly 1 entry with distinct times.
	var lb_a: NakamaAPI.ApiRpc = await client.rpc_async(
		player, "get_leaderboard", JSON.stringify({
			"level_owner_id": str(owner_a.user_id),
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_a.is_exception()).is_false()
	var entries_a: Array = (JSON.parse_string(lb_a.payload) as Dictionary).get("entries", []) as Array
	assert_int(entries_a.size()).is_equal(1)
	assert_int(int((entries_a[0] as Dictionary).get("time_ms", 0))).override_failure_message(
		"Finding #9: Leaderboard for owner_a has wrong time — possible ID collision"
	).is_equal(3000)

	var lb_b: NakamaAPI.ApiRpc = await client.rpc_async(
		player, "get_leaderboard", JSON.stringify({
			"level_owner_id": str(owner_b.user_id),
			"level_key": level_key,
			"filter": "all_time",
		})
	)
	assert_bool(lb_b.is_exception()).is_false()
	var entries_b: Array = (JSON.parse_string(lb_b.payload) as Dictionary).get("entries", []) as Array
	assert_int(entries_b.size()).is_equal(1)
	assert_int(int((entries_b[0] as Dictionary).get("time_ms", 0))).override_failure_message(
		"Finding #9: Leaderboard for owner_b has wrong time — possible ID collision"
	).is_equal(9000)

	# Cleanup.
	await client.rpc_async(owner_a, "delete_level", JSON.stringify({"key": level_key}))
	await client.rpc_async(owner_b, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player)
	await client.delete_account_async(owner_b)
	await client.delete_account_async(owner_a)


# ── Finding #25: Cross-user authorization — delete ───────────────────────────
# User B cannot delete User A's levels.

func test_user_cannot_delete_another_users_level() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var user_a := await client.authenticate_device_async("it-xauth-del-a-%s" % suffix)
	var user_b := await client.authenticate_device_async("it-xauth-del-b-%s" % suffix)
	assert_bool(user_a.is_exception()).is_false()
	assert_bool(user_b.is_exception()).is_false()

	var level_key := "it_xauth_del_%s" % suffix
	await client.rpc_async(
		user_a, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		user_a, "publish_level", JSON.stringify({"key": level_key})
	)

	# User B tries to delete User A's level — should get "not found".
	var delete_result: NakamaAPI.ApiRpc = await client.rpc_async(
		user_b, "delete_level", JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()
	assert_bool(delete_result.is_exception()).override_failure_message(
		"Finding #25: User B was able to delete User A's level"
	).is_true()

	# Verify User A's level still exists.
	var get_result: NakamaAPI.ApiRpc = await client.rpc_async(
		user_a, "get_level", JSON.stringify({
			"user_id": str(user_a.user_id),
			"key": level_key,
		})
	)
	assert_bool(get_result.is_exception()).is_false()
	var level := JSON.parse_string(get_result.payload) as Dictionary
	assert_str(str(level.get("key", ""))).is_equal(level_key)

	await client.rpc_async(user_a, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(user_b)
	await client.delete_account_async(user_a)


# ── Finding #25: Cross-user authorization — publish ──────────────────────────
# User B cannot publish User A's draft level.

func test_user_cannot_publish_another_users_level() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var user_a := await client.authenticate_device_async("it-xauth-pub-a-%s" % suffix)
	var user_b := await client.authenticate_device_async("it-xauth-pub-b-%s" % suffix)
	assert_bool(user_a.is_exception()).is_false()
	assert_bool(user_b.is_exception()).is_false()

	var level_key := "it_xauth_pub_%s" % suffix
	await client.rpc_async(
		user_a, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)

	# User B tries to publish User A's level — should get "not found".
	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(
		user_b, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result.is_exception()).override_failure_message(
		"Finding #25: User B was able to publish User A's draft level"
	).is_true()

	# Verify the level is still a draft.
	var get_result: NakamaAPI.ApiRpc = await client.rpc_async(
		user_a, "get_level", JSON.stringify({
			"user_id": str(user_a.user_id),
			"key": level_key,
		})
	)
	assert_bool(get_result.is_exception()).is_false()
	var value := (JSON.parse_string(get_result.payload) as Dictionary).get("value", {}) as Dictionary
	assert_bool(value.has("published_at")).override_failure_message(
		"Level should still be a draft (no published_at)"
	).is_false()

	await client.rpc_async(user_a, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(user_b)
	await client.delete_account_async(user_a)


# ── Finding #8: Reading another user's level doesn't corrupt their data ──────
# The server sanitizes levels on read. If it writes cleaned data back to another
# user's storage, it shouldn't corrupt valid levels.

func test_listing_levels_does_not_corrupt_other_users_data() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-foreign-wr-owner-%s" % suffix)
	var reader_session := await client.authenticate_device_async("it-foreign-wr-reader-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(reader_session.is_exception()).is_false()

	# Owner creates and publishes a level.
	var level_key := "it_foreign_wr_%s" % suffix
	await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	await client.rpc_async(
		owner_session, "publish_level", JSON.stringify({"key": level_key})
	)

	# Capture the level state before the reader accesses it.
	var before_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "get_level", JSON.stringify({
			"user_id": str(owner_session.user_id),
			"key": level_key,
		})
	)
	assert_bool(before_result.is_exception()).is_false()
	var before_value := (JSON.parse_string(before_result.payload) as Dictionary).get("value", {}) as Dictionary

	# Reader fetches the level (triggers sanitization + possible write-back).
	var reader_get: NakamaAPI.ApiRpc = await client.rpc_async(
		reader_session, "get_level", JSON.stringify({
			"user_id": str(owner_session.user_id),
			"key": level_key,
		})
	)
	assert_bool(reader_get.is_exception()).is_false()

	# Also trigger list_all_levels from reader which can also write-back.
	await client.rpc_async(reader_session, "list_all_levels", JSON.stringify({}))

	# Verify the owner's level data is unchanged.
	var after_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "get_level", JSON.stringify({
			"user_id": str(owner_session.user_id),
			"key": level_key,
		})
	)
	assert_bool(after_result.is_exception()).is_false()
	var after_value := (JSON.parse_string(after_result.payload) as Dictionary).get("value", {}) as Dictionary

	assert_int(int(after_value.get("grid_size", 0))).override_failure_message(
		"Finding #8: grid_size changed after foreign read"
	).is_equal(int(before_value.get("grid_size", 0)))
	assert_int(int(after_value.get("likes", -1))).override_failure_message(
		"Finding #8: likes changed after foreign read"
	).is_equal(int(before_value.get("likes", -1)))
	assert_int(int(after_value.get("dislikes", -1))).override_failure_message(
		"Finding #8: dislikes changed after foreign read"
	).is_equal(int(before_value.get("dislikes", -1)))
	assert_str(str(after_value.get("name", ""))).override_failure_message(
		"Finding #8: name changed after foreign read"
	).is_equal(str(before_value.get("name", "")))

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(reader_session)
	await client.delete_account_async(owner_session)


# ── Finding #25: Cross-user authorization — vote on unpublished level ────────
# User B cannot vote on User A's unpublished draft level.

func test_voting_on_unpublished_level_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-xauth-vote-owner-%s" % suffix)
	var voter_session := await client.authenticate_device_async("it-xauth-vote-voter-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(voter_session.is_exception()).is_false()

	var level_key := "it_xauth_vote_%s" % suffix
	# Submit but do NOT publish.
	await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)

	# Voter tries to vote on unpublished level — should be rejected.
	var vote_result: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_session, "submit_level_vote", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"vote": "like",
		})
	)
	assert_object(vote_result).is_not_null()
	assert_bool(vote_result.is_exception()).override_failure_message(
		"Server allowed voting on an unpublished level"
	).is_true()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(voter_session)
	await client.delete_account_async(owner_session)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "security remaining integration test",
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
