@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const LEVEL_CREATOR_SCENE := "res://level_creator/level_creator.tscn"
const PLACEABLE_SCENE := preload("res://level_player/placeable_object.tscn")


func test_special_tile_cannot_be_placed_in_front_of_block_tile() -> void:
	var runner := scene_runner(_load_level_creator())
	await runner.simulate_frames(2)

	var creator := runner.scene() as LevelCreator
	assert_object(creator).is_not_null()

	var blocked_edge_slot := Vector2i(-1, 1)
	_add_block_tile(creator, Vector2i(0, 1))

	var can_place := bool(creator.drag_manager.call("_can_place_special", blocked_edge_slot))
	assert_bool(can_place).is_false()

	var available_slots := creator.drag_manager.call("_get_available_edge_slots") as Array[Vector2i]
	assert_bool(available_slots.has(blocked_edge_slot)).is_false()


func test_test_button_is_disabled_until_level_meets_save_requirements() -> void:
	var runner := scene_runner(_load_level_creator())
	await runner.simulate_frames(2)

	var creator := runner.scene() as LevelCreator
	assert_object(creator).is_not_null()
	assert_bool(creator.tile_palette.is_test_enabled()).is_false()

	_build_minimal_valid_level(creator)
	creator._test_button_dirty = true
	await runner.simulate_frames(1)
	assert_bool(creator.tile_palette.is_test_enabled()).is_true()

	var walkable_id := creator.world.entity_at(1, 1)
	assert_bool(walkable_id != -1).is_true()
	creator.world.remove_entity(walkable_id)
	creator.world.commit()
	creator._test_button_dirty = true
	await runner.simulate_frames(1)
	assert_bool(creator.tile_palette.is_test_enabled()).is_false()


func _load_level_creator() -> LevelCreator:
	return auto_free(load(LEVEL_CREATOR_SCENE).instantiate()) as LevelCreator


func _build_minimal_valid_level(creator: LevelCreator) -> void:
	var world: TileWorld = creator.world
	var grid_size: int = creator.grid_manager.grid_size

	_add_edge_tile(world, grid_size, Vector2i(-1, 1), "portal", ComponentRegistry.START)
	_add_edge_tile(world, grid_size, Vector2i(grid_size, 1), "cat1", ComponentRegistry.END)
	_add_room_tile(
		world,
		Vector2i(0, 1),
		"EW.png",
		[ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.WEST]
	)
	_add_room_tile(
		world,
		Vector2i(1, 1),
		"EW.png",
		[ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.WEST]
	)

	world.commit()


func _add_edge_tile(world: TileWorld, grid_size: int, pos: Vector2i, sprite: String, role_component: String) -> void:
	var entity_id := world.create_entity(pos.x, pos.y, sprite)
	world.add(ComponentRegistry.WALKABLE, entity_id)
	world.add(role_component, entity_id)
	var inward_component := LevelConfig.edge_inward_component(pos, grid_size)
	if not inward_component.is_empty():
		world.add(inward_component, entity_id)


func _add_room_tile(world: TileWorld, pos: Vector2i, sprite: String, components: Array[String]) -> void:
	var entity_id := world.create_entity(pos.x, pos.y, sprite)
	for component in components:
		world.add(component, entity_id)


func _add_block_tile(creator: LevelCreator, cell: Vector2i) -> void:
	var entity_id := creator.world.create_entity(cell.x, cell.y, "block")
	creator.world.add(ComponentRegistry.BLOCKED, entity_id)
	creator.world.commit()

	var obj := PLACEABLE_SCENE.instantiate() as PlaceableObject
	obj.entity_id = entity_id
	obj.grid_pos = cell
	obj.global_position = creator.grid_manager.grid_to_world(cell)
	creator.object_container.add_child(obj)
	creator.grid_manager.register_object(obj)
