@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const MAIN_SCENE := "res://scenes/main.tscn"


func test_friend_level_play_modal_hidden_on_enter_and_visible_after_completion() -> void:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()

	var suffix := str(Time.get_ticks_usec())
	var owner_session := await client.authenticate_device_async("it-friend-play-owner-%s" % suffix)
	assert_object(owner_session).is_not_null()
	assert_bool(owner_session.is_exception()).is_false()
	assert_bool(owner_session.is_valid()).is_true()

	var level_key := "it_friend_play_modal_%s" % suffix
	var owner_id := str(owner_session.user_id)
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

	OnlineSession.session = null
	OnlineSession.client = null

	var runner := scene_runner(_load_main_scene_localhost())
	await runner.simulate_frames(6)
	await _wait_until(
		runner,
		func() -> bool: return OnlineSession.session != null,
		360,
		"OnlineSession was not ready in Main scene."
	)

	var main_scene: Node = runner.scene()
	var community_levels: Node = main_scene.find_child("CommunityLevels", true, false)
	var level_player := main_scene.find_child("LevelPlayer", true, false) as LevelPlayer
	var completion_modal := main_scene.find_child("LevelCompleteModal", true, false) as CanvasLayer
	assert_object(community_levels).is_not_null()
	assert_object(level_player).is_not_null()
	assert_object(completion_modal).is_not_null()
	assert_bool(completion_modal.visible).is_false()

	community_levels.emit_signal("play_requested", level_key, owner_id)

	await _wait_until(
		runner,
		func() -> bool:
			var controller: Variant = level_player.get("_player_controller")
			return level_player.visible and controller != null,
		600,
		"LevelPlayer did not enter and load the selected level."
	)
	assert_bool(completion_modal.visible).is_false()

	level_player.call("_on_reached_end")
	await _wait_until(
		runner,
		func() -> bool: return completion_modal.visible,
		900,
		"Completion modal did not become visible after finishing the level."
	)
	assert_bool(completion_modal.visible).is_true()
	var level_name_label := completion_modal.find_child("LevelNameLabel", true, false) as Label
	assert_object(level_name_label).is_not_null()
	assert_str(level_name_label.text).is_equal(level_key)
	assert_bool(level_player.visible).is_false()

	var delete_result: NakamaAPI.ApiRpc = await client.rpc_async(
		owner_session,
		"delete_level",
		JSON.stringify({"key": level_key})
	)
	assert_object(delete_result).is_not_null()
	assert_bool(delete_result.is_exception()).is_false()

	await client.delete_account_async(owner_session)


func _load_main_scene_localhost() -> Node2D:
	var main_scene := auto_free(load(MAIN_SCENE).instantiate()) as Node2D
	main_scene.set("use_local_server", true)
	return main_scene


func _wait_until(runner, predicate: Callable, max_frames: int, failure_message: String) -> void:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return
		await runner.simulate_frames(1)
	assert_bool(bool(predicate.call())).override_failure_message(failure_message).is_true()


func _build_valid_submit_payload(level_key: String) -> Dictionary:
	return {
		"name": level_key,
		"description": "friend modal play flow integration",
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
