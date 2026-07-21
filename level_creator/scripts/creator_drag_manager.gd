extends Node

signal tile_placed(obj: PlaceableObject, pos: Vector2i)
signal tile_removed(obj: PlaceableObject)

var grid_manager: GridManager
var grid_visual: Node2D
var object_container: Node2D
var edge_objects: Dictionary  # Vector2i -> PlaceableObject
var world: TileWorld

var _dragging: PlaceableObject = null
var _drag_origin_grid: Vector2i = Vector2i(-99, -99)
var _drag_from_edge: bool = false
var _pick_radius: float = 40.0


func _process(_delta: float) -> void:
	if _dragging:
		_dragging.global_position = _dragging.get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	if _dragging:
		_try_drop(event.position)
	else:
		_try_pick_up(event.position)


func start_drag(obj: PlaceableObject) -> void:
	if _dragging and _dragging != obj:
		_discard(_dragging)

	_clear_highlights()

	_dragging = obj
	_drag_origin_grid = Vector2i(-99, -99)
	_drag_from_edge = false
	obj.z_index = 10
	obj.modulate.a = 0.7

	if _is_special_tile(obj):
		_show_special_highlights()
	else:
		_show_regular_highlights(obj)


func _try_pick_up(mouse_pos: Vector2) -> void:
	# Check grid tiles
	if grid_manager.is_in_grid_area(mouse_pos):
		var gp := grid_manager.world_to_grid(mouse_pos)
		var obj := grid_manager.get_object_at(gp.x, gp.y) as PlaceableObject
		if obj:
			grid_manager.remove_object(gp.x, gp.y)
			_drag_origin_grid = gp
			_drag_from_edge = false
			start_drag(obj)
			return

	# Check edge tiles
	for edge_pos in edge_objects:
		var obj: PlaceableObject = edge_objects[edge_pos]
		if obj.global_position.distance_to(mouse_pos) <= _pick_radius:
			edge_objects.erase(edge_pos)
			_drag_origin_grid = edge_pos
			_drag_from_edge = true
			start_drag(obj)
			return


func _try_drop(mouse_pos: Vector2) -> void:
	var obj := _dragging
	_finish_drag()

	if not world.has(ComponentRegistry.START, obj.entity_id) and not world.has(ComponentRegistry.END, obj.entity_id):
		_drop_regular(obj, mouse_pos)
	else:
		_drop_special(obj, mouse_pos)

	if grid_visual:
		grid_visual.queue_redraw()


func _drop_regular(obj: PlaceableObject, mouse_pos: Vector2) -> void:
	if not grid_manager.is_in_grid_area(mouse_pos):
		_discard(obj)
		return

	var gp := grid_manager.world_to_grid(mouse_pos)
	if _can_place_regular(obj, gp) and grid_manager.place_object(gp.x, gp.y, obj):
		obj.grid_pos = gp
		tile_placed.emit(obj, gp)
	else:
		_discard(obj)


func _drop_special(obj: PlaceableObject, mouse_pos: Vector2) -> void:
	var edge_pos := _world_to_edge(mouse_pos)
	if _can_place_special(edge_pos):
		edge_objects[edge_pos] = obj
		obj.global_position = _edge_to_world(edge_pos)
		obj.grid_pos = edge_pos
		world.set_pos(obj.entity_id, edge_pos.x, edge_pos.y)
		world.commit()
		tile_placed.emit(obj, edge_pos)
	else:
		_discard(obj)


func _finish_drag() -> void:
	_clear_highlights()

	if _dragging:
		_dragging.z_index = 0
		_dragging.modulate.a = 1.0
		_dragging = null


func _discard(obj: PlaceableObject) -> void:
	tile_removed.emit(obj)
	world.remove_entity(obj.entity_id)
	world.commit()
	if grid_manager:
		grid_manager.unregister_entity(obj.entity_id)
	obj.queue_free()


func _edge_to_world(pos: Vector2i) -> Vector2:
	var origin := grid_manager.grid_origin
	var cs := grid_manager.cell_size
	var world_x := origin.x + pos.x * cs + cs / 2.0
	var world_y := origin.y + pos.y * cs + cs / 2.0
	return Vector2(world_x, world_y)


func _world_to_edge(world_pos: Vector2) -> Vector2i:
	var origin := grid_manager.grid_origin
	var cs := grid_manager.cell_size
	var gx := floori((world_pos.x - origin.x) / cs)
	var gy := floori((world_pos.y - origin.y) / cs)
	return Vector2i(gx, gy)


func _is_valid_edge_slot(pos: Vector2i) -> bool:
	var s := grid_manager.grid_size
	var x := pos.x
	var y := pos.y
	# Left/right edges
	if (x == -1 or x == s) and y >= 0 and y < s:
		return true
	# Top/bottom edges
	if (y == -1 or y == s) and x >= 0 and x < s:
		return true
	return false


func clear() -> void:
	edge_objects.clear()
	_dragging = null
	_clear_highlights()


func _is_special_tile(obj: PlaceableObject) -> bool:
	return world.has(ComponentRegistry.START, obj.entity_id) or world.has(ComponentRegistry.END, obj.entity_id)


func _show_special_highlights() -> void:
	if not grid_visual:
		return
	if not grid_visual.has_method("set_edge_highlights"):
		return

	var available := _get_available_edge_slots()
	grid_visual.call("set_edge_highlights", available)


func _show_regular_highlights(obj: PlaceableObject) -> void:
	if not grid_visual:
		return
	if not grid_visual.has_method("set_grid_highlights"):
		return

	var available := _get_available_grid_slots(obj)
	grid_visual.call("set_grid_highlights", available)


func _clear_highlights() -> void:
	if not grid_visual:
		return
	if not grid_visual.has_method("clear_edge_highlights"):
		pass
	else:
		grid_visual.call("clear_edge_highlights")

	if not grid_visual.has_method("clear_grid_highlights"):
		return
	grid_visual.call("clear_grid_highlights")


func _get_available_edge_slots() -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	var s := grid_manager.grid_size

	for y in range(s):
		var left := Vector2i(-1, y)
		if _can_place_special(left):
			slots.append(left)

		var right := Vector2i(s, y)
		if _can_place_special(right):
			slots.append(right)

	for x in range(s):
		var top := Vector2i(x, -1)
		if _can_place_special(top):
			slots.append(top)

		var bottom := Vector2i(x, s)
		if _can_place_special(bottom):
			slots.append(bottom)

	return slots


func _can_place_special(edge_pos: Vector2i) -> bool:
	if not grid_manager:
		return false
	if not _is_valid_edge_slot(edge_pos):
		return false
	if edge_objects.has(edge_pos):
		return false

	# Entrances/exits cannot be placed in front of a block tile.
	var front_cell := _front_cell_for_edge(edge_pos)
	var front_id := world.entity_at(front_cell.x, front_cell.y)
	if front_id != -1 and world.has(ComponentRegistry.BLOCKED, front_id):
		return false

	return true


func _get_available_grid_slots(obj: PlaceableObject) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	var s := grid_manager.grid_size
	for y in range(s):
		for x in range(s):
			var gp := Vector2i(x, y)
			if not grid_manager.is_cell_empty(x, y):
				continue
			if not _can_place_regular(obj, gp):
				continue
			slots.append(gp)
	return slots


func _can_place_regular(obj: PlaceableObject, gp: Vector2i) -> bool:
	if not grid_manager.is_valid_cell(gp.x, gp.y):
		return false
	if not grid_manager.is_cell_empty(gp.x, gp.y):
		return false

	# Blocks cannot be placed directly inside an entrance/exit edge slot.
	if world.has(ComponentRegistry.BLOCKED, obj.entity_id) and _is_front_of_any_edge_slot(gp):
		return false

	return true


func _is_front_of_any_edge_slot(cell: Vector2i) -> bool:
	for edge_pos_var in edge_objects.keys():
		var edge_pos := edge_pos_var as Vector2i
		if _front_cell_for_edge(edge_pos) == cell:
			return true
	return false


func _front_cell_for_edge(edge_pos: Vector2i) -> Vector2i:
	var s := grid_manager.grid_size
	if edge_pos.x == -1 and edge_pos.y >= 0 and edge_pos.y < s:
		return Vector2i(0, edge_pos.y)
	if edge_pos.x == s and edge_pos.y >= 0 and edge_pos.y < s:
		return Vector2i(s - 1, edge_pos.y)
	if edge_pos.y == -1 and edge_pos.x >= 0 and edge_pos.x < s:
		return Vector2i(edge_pos.x, 0)
	if edge_pos.y == s and edge_pos.x >= 0 and edge_pos.x < s:
		return Vector2i(edge_pos.x, s - 1)
	return Vector2i(-9999, -9999)
