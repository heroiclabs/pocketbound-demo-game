@warning_ignore_start("redundant_await")
extends GdUnitTestSuite


func test_self_voting_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-sec-selfvote-%s" % suffix)
	assert_object(owner_session).is_not_null()
	assert_bool(owner_session.is_exception()).is_false()

	var level_key := "it_sec_selfvote_%s" % suffix
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_bool(submit_result.is_exception()).is_false()
	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "publish_level", JSON.stringify({"key": level_key})
	)
	assert_bool(publish_result.is_exception()).is_false()

	# Owner tries to vote on their own level — should be rejected.
	var vote_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "submit_level_vote", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"vote": "like",
		})
	)
	assert_object(vote_result).is_not_null()
	assert_bool(vote_result.is_exception()).is_true()

	# Verify vote count is still 0.
	var get_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session, "get_level", JSON.stringify({
			"user_id": str(owner_session.user_id),
			"key": level_key,
		})
	)
	assert_bool(get_result.is_exception()).is_false()
	var level_value := (JSON.parse_string(get_result.payload) as Dictionary).get("value", {}) as Dictionary
	assert_int(int(level_value.get("likes", -1))).is_equal(0)
	assert_int(int(level_value.get("dislikes", -1))).is_equal(0)

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(owner_session)


func test_negative_time_ms_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-sec-negtime-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-sec-negtime-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_sec_negtime_%s" % suffix
	await client.rpc_async(owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(owner_session, "publish_level", JSON.stringify({"key": level_key}))

	# Submit a negative time — should be rejected.
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": -1000,
			"slide_count": 5,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_true()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


func test_zero_time_ms_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-sec-zerotime-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-sec-zerotime-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_sec_zerotime_%s" % suffix
	await client.rpc_async(owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(owner_session, "publish_level", JSON.stringify({"key": level_key}))

	# Submit zero time — should be rejected (not a valid completion).
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 0,
			"slide_count": 5,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_true()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


func test_negative_slide_count_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-sec-negslide-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-sec-negslide-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_sec_negslide_%s" % suffix
	await client.rpc_async(owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))
	await client.rpc_async(owner_session, "publish_level", JSON.stringify({"key": level_key}))

	# Submit a negative slide count — should be rejected.
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 5000,
			"slide_count": -3,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_true()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


func test_submit_score_for_nonexistent_level_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var player_session := await client.authenticate_device_async("it-sec-phantom-%s" % suffix)
	assert_bool(player_session.is_exception()).is_false()

	# Submit score for a level that doesn't exist — should be rejected.
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": "00000000-0000-0000-0000-000000000000",
			"level_key": "nonexistent_level_%s" % suffix,
			"time_ms": 5000,
			"slide_count": 10,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_true()

	await client.delete_account_async(player_session)


func test_submit_score_for_unpublished_draft_is_rejected() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-sec-draft-owner-%s" % suffix)
	var player_session := await client.authenticate_device_async("it-sec-draft-player-%s" % suffix)
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(player_session.is_exception()).is_false()

	var level_key := "it_sec_draft_%s" % suffix
	# Submit but do NOT publish.
	await client.rpc_async(owner_session, "submit_level", JSON.stringify(_build_valid_submit_payload(level_key)))

	# Submit score for an unpublished draft — should be rejected.
	var score_result: NakamaAPI.ApiRpc = await client.rpc_async(
		player_session, "submit_score", JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"time_ms": 5000,
			"slide_count": 10,
		})
	)
	assert_object(score_result).is_not_null()
	assert_bool(score_result.is_exception()).is_true()

	await client.rpc_async(owner_session, "delete_level", JSON.stringify({"key": level_key}))
	await client.delete_account_async(player_session)
	await client.delete_account_async(owner_session)


func test_user_cannot_exceed_max_level_count() -> void:
	var client := Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var session := await client.authenticate_device_async("it-sec-maxlevels-%s" % suffix)
	assert_bool(session.is_exception()).is_false()

	# Create levels up to the limit (50).
	var created_keys: Array[String] = []
	for i in range(50):
		var key := "it_sec_max_%s_%d" % [suffix, i]
		var result: NakamaAPI.ApiRpc = await client.rpc_async(
			session, "submit_level", JSON.stringify(_build_valid_submit_payload(key))
		)
		assert_bool(result.is_exception()).override_failure_message(
			"Failed to create level %d of 50" % i
		).is_false()
		created_keys.append(key)

	# The 51st level should be rejected.
	var overflow_key := "it_sec_max_%s_overflow" % suffix
	var overflow_result: NakamaAPI.ApiRpc = await client.rpc_async(
		session, "submit_level", JSON.stringify(_build_valid_submit_payload(overflow_key))
	)
	assert_object(overflow_result).is_not_null()
	assert_bool(overflow_result.is_exception()).is_true()

	# Cleanup all created levels.
	for key in created_keys:
		await client.rpc_async(session, "delete_level", JSON.stringify({"key": key}))
	await client.delete_account_async(session)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "security integration test",
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
