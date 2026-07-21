class_name GridManager
extends Node

@export var grid_size: int = LevelConfig.DEFAULT_GRID_SIZE
@export var grid_origin: Vector2 = LevelConfig.GRID_ORIGIN

const OFF_GRID_COORD := TileWorld.OFF_GRID_COORD

var cell_size: float
var world: TileWorld = null

# Presentation-only mapping: entity_id -> scene node.
var _objects_by_entity: Dictionary = {}


func _ready() -> void:
	_initialize_grid()


func _initialize_grid() -> void:
	cell_size = LevelConfig.PUZZLE_SIZE / grid_size


func is_valid_cell(x: int, y: int) -> bool:
	return x >= 0 and x < grid_size and y >= 0 and y < grid_size


func is_cell_empty(x: int, y: int) -> bool:
	if not is_valid_cell(x, y):
		return false
	if world == null:
		return true
	return world.entity_at(x, y) == -1


func place_object(x: int, y: int, object: Node2D) -> bool:
	if world == null:
		return false
	if not is_cell_empty(x, y):
		return false

	var placeable := object as PlaceableObject
	if placeable == null:
		return false

	world.set_pos(placeable.entity_id, x, y)
	world.commit()
	register_object(object)
	object.global_position = grid_to_world(Vector2i(x, y))
	return true


func remove_object(x: int, y: int) -> Node2D:
	if not is_valid_cell(x, y):
		return null
	if world == null:
		return null

	var id := world.entity_at(x, y)
	if id == -1:
		return null

	world.set_pos(id, OFF_GRID_COORD, OFF_GRID_COORD)
	world.commit()
	return _objects_by_entity.get(id, null) as Node2D


func get_object_at(x: int, y: int) -> Node2D:
	if not is_valid_cell(x, y):
		return null
	if world == null:
		return null
	var id := world.entity_at(x, y)
	if id == -1:
		return null
	return _objects_by_entity.get(id, null) as Node2D


func get_adjacent_empty_cells(x: int, y: int) -> Array[Vector2i]:
	var empties: Array[Vector2i] = []
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in directions:
		var nx := x + dir.x
		var ny := y + dir.y
		if is_cell_empty(nx, ny):
			empties.append(Vector2i(nx, ny))
	return empties


func move_object(from: Vector2i, to: Vector2i) -> bool:
	if world == null:
		return false
	if not is_valid_cell(from.x, from.y):
		return false
	if not is_valid_cell(to.x, to.y):
		return false
	if not is_cell_empty(to.x, to.y):
		return false

	var id := world.entity_at(from.x, from.y)
	if id == -1:
		return false

	world.set_pos(id, to.x, to.y)
	world.commit()
	return true


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	var world_x = grid_origin.x + grid_pos.x * cell_size + cell_size / 2.0
	var world_y = grid_origin.y + grid_pos.y * cell_size + cell_size / 2.0
	return Vector2(world_x, world_y)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	var grid_x = floori((world_pos.x - grid_origin.x) / cell_size)
	var grid_y = floori((world_pos.y - grid_origin.y) / cell_size)
	return Vector2i(grid_x, grid_y)


func is_in_grid_area(world_pos: Vector2) -> bool:
	var grid_pos = world_to_grid(world_pos)
	return is_valid_cell(grid_pos.x, grid_pos.y)


func register_object(object: Node2D) -> void:
	if object == null:
		return
	var placeable := object as PlaceableObject
	if placeable == null:
		return
	_objects_by_entity[placeable.entity_id] = object


func unregister_entity(entity_id: int) -> void:
	_objects_by_entity.erase(entity_id)


func clear_object_registry() -> void:
	_objects_by_entity.clear()
