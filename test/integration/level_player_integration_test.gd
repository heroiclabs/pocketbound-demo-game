@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const LEVEL_PLAYER_SCENE := "res://level_player/level_player.tscn"
const OPTIONS_PANEL_NAME := "OptionsPanel"


func test_level_player_scene_initializes_core_dependencies() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()

	assert_object(level_player.world).is_not_null()
	assert_object(level_player.grid_manager).is_not_null()
	assert_object(level_player.grid_visual).is_not_null()
	assert_object(level_player.slide_manager).is_not_null()
	assert_object(level_player.object_container).is_not_null()
	assert_object(level_player.grid_manager.world).is_same(level_player.world)
	assert_object(level_player.slide_manager.world).is_same(level_player.world)

	assert_object(level_player.find_child("Hud", true, false)).is_not_null()
	assert_object(level_player.find_child("OptionsBtn", true, false)).is_not_null()


func test_level_player_options_overlay_single_instance() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(1)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()

	runner.invoke("_show_options_overlay")
	await await_idle_frame()
	assert_int(_count_direct_children_named(level_player, OPTIONS_PANEL_NAME)).is_equal(1)

	runner.invoke("_show_options_overlay")
	await await_idle_frame()
	assert_int(_count_direct_children_named(level_player, OPTIONS_PANEL_NAME)).is_equal(1)


func test_click_move_records_one_step() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()
	_setup_slide_test_board(level_player, 5, Vector2i(1, 2), [])

	await _click_move_tile(runner, level_player, Vector2i(1, 2), Vector2i(2, 2))

	assert_int(level_player.world.entity_at(1, 2)).is_equal(-1)
	assert_int(level_player.world.entity_at(2, 2)).is_equal(0)
	assert_int(level_player.get("_slide_count")).is_equal(1)


func test_click_move_records_four_steps_in_single_action() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()
	_setup_slide_test_board(level_player, 5, Vector2i(0, 1), [])

	await _click_move_tile(runner, level_player, Vector2i(0, 1), Vector2i(4, 1))

	assert_int(level_player.world.entity_at(0, 1)).is_equal(-1)
	assert_int(level_player.world.entity_at(4, 1)).is_equal(0)
	assert_int(level_player.get("_slide_count")).is_equal(4)


func test_click_move_stops_at_obstacle_and_records_reached_steps() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()
	_setup_slide_test_board(level_player, 5, Vector2i(0, 1), [Vector2i(3, 1)])

	await _click_move_tile(runner, level_player, Vector2i(0, 1), Vector2i(4, 1))

	assert_int(level_player.world.entity_at(0, 1)).is_equal(-1)
	assert_int(level_player.world.entity_at(2, 1)).is_equal(0)
	assert_int(level_player.world.entity_at(3, 1)).is_equal(1)
	assert_int(level_player.get("_slide_count")).is_equal(2)


func test_click_move_supports_multiple_moves_with_direction_changes() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()
	_setup_slide_test_board(level_player, 5, Vector2i(1, 1), [])

	await _click_move_tile(runner, level_player, Vector2i(1, 1), Vector2i(4, 1))
	await _click_move_tile(runner, level_player, Vector2i(4, 1), Vector2i(4, 3))
	await _click_move_tile(runner, level_player, Vector2i(4, 3), Vector2i(2, 3))

	assert_int(level_player.world.entity_at(2, 3)).is_equal(0)
	assert_int(level_player.get("_slide_count")).is_equal(7)


func test_tile_moves_can_open_path_and_player_reaches_goal() -> void:
	var runner := scene_runner(_load_level_player())
	await runner.simulate_frames(2)

	var level_player := runner.scene() as LevelPlayer
	assert_object(level_player).is_not_null()
	_setup_goal_reach_board(level_player)
	await runner.simulate_frames(2)

	var controller := level_player.get("_player_controller") as PlayerController
	assert_object(controller).is_not_null()

	var on_reached_end := Callable(level_player, "_on_reached_end")
	if controller.reached_end.is_connected(on_reached_end):
		controller.reached_end.disconnect(on_reached_end)

	var goal_state := {"reached": false}
	controller.reached_end.connect(func(): goal_state["reached"] = true)

	await _click_move_tile(runner, level_player, Vector2i(1, 0), Vector2i(1, 1))
	assert_int(level_player.get("_slide_count")).is_equal(1)
	assert_int(level_player.world.entity_at(1, 1)).is_equal(3)

	await _move_player_steps(runner, "ui_right", 5)

	var end_pos := level_player.get("_end_pos") as Vector2i
	assert_bool(bool(goal_state["reached"])).is_true()
	assert_int(controller.current_pos.x).is_equal(end_pos.x)
	assert_int(controller.current_pos.y).is_equal(end_pos.y)


func _load_level_player() -> LevelPlayer:
	return auto_free(load(LEVEL_PLAYER_SCENE).instantiate()) as LevelPlayer


func _count_direct_children_named(parent: Node, node_name: String) -> int:
	var count := 0
	for child in parent.get_children():
		if child is Node and child.name == node_name:
			count += 1
	return count


func _setup_slide_test_board(
	level_player: LevelPlayer,
	grid_size: int,
	mover_pos: Vector2i,
	blockers: Array[Vector2i]
) -> void:
	level_player._cleanup()
	level_player._setup_grid(grid_size)
	level_player.world.from_dict(_build_slide_test_payload(grid_size, mover_pos, blockers))
	level_player._build_tiles_from_world()
	level_player.slide_manager.locked_cell = Vector2i(-99, -99)
	level_player.set("_slide_count", 0)


func _build_slide_test_payload(grid_size: int, mover_pos: Vector2i, blockers: Array[Vector2i]) -> Dictionary:
	var xs: Array[int] = [mover_pos.x]
	var ys: Array[int] = [mover_pos.y]
	var sprites: Array[String] = ["background"]
	var blocked_ids: Array[int] = []

	for blocker_pos in blockers:
		xs.append(blocker_pos.x)
		ys.append(blocker_pos.y)
		sprites.append("block")
		blocked_ids.append(xs.size() - 1)

	var payload: Dictionary = {
		"grid_size": grid_size,
		"x": xs,
		"y": ys,
		"sprite": sprites,
	}
	if not blocked_ids.is_empty():
		payload[ComponentRegistry.BLOCKED] = blocked_ids
	return payload


func _setup_goal_reach_board(level_player: LevelPlayer) -> void:
	level_player._cleanup()
	level_player._setup_grid(4)
	level_player.world.from_dict(_build_goal_reach_payload())
	level_player._build_tiles_from_world()
	level_player.set("_current_pos", level_player.get("_start_pos"))
	level_player.set("_slide_count", 0)
	level_player._spawn_player()


func _build_goal_reach_payload() -> Dictionary:
	return {
		"grid_size": 4,
		"x": [-1, 4, 0, 1, 2, 3],
		"y": [1, 1, 1, 0, 1, 1],
		"sprite": ["E", "W", "EW", "EW", "EW", "EW"],
		ComponentRegistry.START: [0],
		ComponentRegistry.END: [1],
		ComponentRegistry.EAST: [0, 2, 3, 4, 5],
		ComponentRegistry.WEST: [1, 2, 3, 4, 5],
	}


func _click_move_tile(
	runner: GdUnitSceneRunner,
	level_player: LevelPlayer,
	from_grid: Vector2i,
	towards_grid: Vector2i
) -> void:
	var from_world := level_player.grid_manager.grid_to_world(from_grid)
	var towards_world := level_player.grid_manager.grid_to_world(towards_grid)

	runner.simulate_mouse_move(from_world)
	await runner.await_input_processed()
	runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await runner.await_input_processed()

	runner.simulate_mouse_move(towards_world)
	await runner.await_input_processed()
	runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await runner.await_input_processed()
	await runner.simulate_frames(20)


func _move_player_steps(runner: GdUnitSceneRunner, action: String, steps: int) -> void:
	var level_player := runner.scene() as LevelPlayer
	var controller := level_player.get("_player_controller") as PlayerController
	for _step in range(steps):
		await _wait_player_idle(runner, controller)
		runner.simulate_action_pressed(action)
		await runner.await_input_processed()
		await runner.simulate_frames(2)
	await _wait_player_idle(runner, controller)


func _wait_player_idle(runner: GdUnitSceneRunner, controller: PlayerController) -> void:
	for _i in range(120):
		if not controller.get("_moving"):
			return
		await runner.simulate_frames(1)
