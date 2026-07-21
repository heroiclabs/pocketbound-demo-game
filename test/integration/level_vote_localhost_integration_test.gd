@warning_ignore_start("redundant_await")
extends GdUnitTestSuite


func test_submit_level_vote_allows_single_vote_per_player_per_level() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-level-vote-owner-%s" % suffix)
	assert_object(owner_session).is_not_null()
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(owner_session.is_valid()).is_true()

	var voter_a_session := await client.authenticate_device_async("it-level-vote-a-%s" % suffix)
	assert_object(voter_a_session).is_not_null()
	assert_bool(voter_a_session.is_exception()).is_false()
	assert_bool(voter_a_session.is_valid()).is_true()

	var voter_b_session := await client.authenticate_device_async("it-level-vote-b-%s" % suffix)
	assert_object(voter_b_session).is_not_null()
	assert_bool(voter_b_session.is_exception()).is_false()
	assert_bool(voter_b_session.is_valid()).is_true()

	var level_key := "it_level_vote_%s" % suffix
	var submit_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"submit_level",
		JSON.stringify(_build_valid_submit_payload(level_key))
	)
	assert_object(submit_result).is_not_null()
	assert_bool(submit_result.is_exception()).is_false()

	var publish_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"publish_level",
		JSON.stringify({"key": level_key})
	)
	assert_object(publish_result).is_not_null()
	assert_bool(publish_result.is_exception()).is_false()

	var vote_like_result: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_a_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"vote": "like",
		})
	)
	assert_object(vote_like_result).is_not_null()
	assert_bool(vote_like_result.is_exception()).is_false()
	var vote_like_payload_variant: Variant = JSON.parse_string(vote_like_result.payload)
	assert_bool(vote_like_payload_variant is Dictionary).is_true()
	var vote_like_payload := vote_like_payload_variant as Dictionary
	assert_int(int(vote_like_payload.get("likes", -1))).is_equal(1)
	assert_int(int(vote_like_payload.get("dislikes", -1))).is_equal(0)
	assert_str(str(vote_like_payload.get("vote", ""))).is_equal("like")

	var duplicate_vote_result: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_a_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"vote": "dislike",
		})
	)
	assert_object(duplicate_vote_result).is_not_null()
	assert_bool(duplicate_vote_result.is_exception()).is_true()

	var vote_dislike_result: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_b_session,
		"submit_level_vote",
		JSON.stringify({
			"level_owner_id": str(owner_session.user_id),
			"level_key": level_key,
			"vote": "dislike",
		})
	)
	assert_object(vote_dislike_result).is_not_null()
	assert_bool(vote_dislike_result.is_exception()).is_false()
	var vote_dislike_payload_variant: Variant = JSON.parse_string(vote_dislike_result.payload)
	assert_bool(vote_dislike_payload_variant is Dictionary).is_true()
	var vote_dislike_payload := vote_dislike_payload_variant as Dictionary
	assert_int(int(vote_dislike_payload.get("likes", -1))).is_equal(1)
	assert_int(int(vote_dislike_payload.get("dislikes", -1))).is_equal(1)
	assert_str(str(vote_dislike_payload.get("vote", ""))).is_equal("dislike")

	var get_level_result: NakamaAPI.ApiRpc = await client.rpc_async(
		voter_a_session,
		"get_level",
		JSON.stringify({
			"user_id": str(owner_session.user_id),
			"key": level_key,
		})
	)
	assert_object(get_level_result).is_not_null()
	assert_bool(get_level_result.is_exception()).is_false()
	var get_level_payload_variant: Variant = JSON.parse_string(get_level_result.payload)
	assert_bool(get_level_payload_variant is Dictionary).is_true()
	var get_level_payload := get_level_payload_variant as Dictionary
	var level_value := get_level_payload.get("value", {}) as Dictionary
	assert_int(int(level_value.get("likes", -1))).is_equal(1)
	assert_int(int(level_value.get("dislikes", -1))).is_equal(1)

	var delete_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"delete_level",
		JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()
	assert_bool(delete_result.is_exception()).is_false()

	await client.delete_account_async(voter_b_session)
	await client.delete_account_async(voter_a_session)
	await client.delete_account_async(owner_session)


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "level vote integration",
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
