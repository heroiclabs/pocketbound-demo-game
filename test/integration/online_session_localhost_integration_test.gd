extends GdUnitTestSuite


func test_online_session_auth_and_list_my_levels_via_localhost() -> void:
	OnlineSession.session = null
	OnlineSession.client = null

	await OnlineSession.start(true)

	assert_object(OnlineSession.client).is_not_null()
	assert_object(OnlineSession.session).is_not_null()

	assert_str(OnlineSession.client.host).is_equal("127.0.0.1")
	assert_int(OnlineSession.client.port).is_equal(7350)
	assert_str(OnlineSession.client.scheme).is_equal("http")
	assert_str(str(OnlineSession.client.server_key)).is_equal("defaultkey")
	assert_bool(OnlineSession.session.is_exception()).is_false()
	assert_bool(OnlineSession.session.is_valid()).is_true()

	var rpc_result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	assert_object(rpc_result).is_not_null()
	assert_bool(rpc_result is Dictionary).is_true()

	var payload: Dictionary = rpc_result as Dictionary
	var levels: Variant = payload.get("levels", null)
	assert_bool(levels is Array).is_true()

	if levels is Array:
		for entry in levels:
			assert_bool(entry is Dictionary).is_true()
