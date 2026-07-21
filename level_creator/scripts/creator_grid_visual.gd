extends Node2D

var grid_manager: GridManager
var _restricted_grid_cells: Array[Vector2i] = []
var _restricted_edge_slots: Array[Vector2i] = []
var empty_cell_texture: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/background.tres")
var restricted_cell_texture: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/restrict.tres")


func _draw() -> void:
	if not grid_manager:
		return

	var origin = grid_manager.grid_origin
	var size = grid_manager.grid_size
	var cs = grid_manager.cell_size
	var restricted_grid_lookup := _to_lookup(_restricted_grid_cells)
	var restricted_edge_lookup := _to_lookup(_restricted_edge_slots)

	# Draw empty in-grid cells using the background room atlas texture.
	if empty_cell_texture:
		for y in range(size):
			for x in range(size):
				if not grid_manager.is_cell_empty(x, y):
					continue
				var gp := Vector2i(x, y)
				var cell_texture := empty_cell_texture
				if restricted_cell_texture and restricted_grid_lookup.has(gp):
					cell_texture = restricted_cell_texture
				var empty_rect := Rect2(origin + Vector2(x * cs, y * cs), Vector2(cs, cs))
				draw_texture_rect(cell_texture, empty_rect, false)
		# Draw empty edge slots (no corners) for start/end placement in creator only.
		for x in range(size):
			var top_pos := Vector2i(x, -1)
			var top_texture := empty_cell_texture
			if restricted_cell_texture and restricted_edge_lookup.has(top_pos):
				top_texture = restricted_cell_texture
			var top_rect := Rect2(origin + Vector2(x * cs, -1.0 * cs), Vector2(cs, cs))
			draw_texture_rect(top_texture, top_rect, false)

			var bottom_pos := Vector2i(x, size)
			var bottom_texture := empty_cell_texture
			if restricted_cell_texture and restricted_edge_lookup.has(bottom_pos):
				bottom_texture = restricted_cell_texture
			var bottom_rect := Rect2(origin + Vector2(x * cs, size * cs), Vector2(cs, cs))
			draw_texture_rect(bottom_texture, bottom_rect, false)

		for y in range(size):
			var left_pos := Vector2i(-1, y)
			var left_texture := empty_cell_texture
			if restricted_cell_texture and restricted_edge_lookup.has(left_pos):
				left_texture = restricted_cell_texture
			var left_rect := Rect2(origin + Vector2(-1.0 * cs, y * cs), Vector2(cs, cs))
			draw_texture_rect(left_texture, left_rect, false)

			var right_pos := Vector2i(size, y)
			var right_texture := empty_cell_texture
			if restricted_cell_texture and restricted_edge_lookup.has(right_pos):
				right_texture = restricted_cell_texture
			var right_rect := Rect2(origin + Vector2(size * cs, y * cs), Vector2(cs, cs))
			draw_texture_rect(right_texture, right_rect, false)


func set_edge_highlights(cells: Array[Vector2i]) -> void:
	_restricted_edge_slots.clear()
	_restricted_grid_cells.clear()
	if not grid_manager:
		queue_redraw()
		return

	var allowed := {}
	for cell in cells:
		allowed[cell] = true

	for edge_pos in _all_edge_slots():
		if not allowed.has(edge_pos):
			_restricted_edge_slots.append(edge_pos)

	# Special tiles can only be dropped on edges, so all grid cells are restricted.
	_restricted_grid_cells = _all_grid_slots()

	queue_redraw()


func clear_edge_highlights() -> void:
	_restricted_edge_slots.clear()
	queue_redraw()


func set_grid_highlights(cells: Array[Vector2i]) -> void:
	_restricted_grid_cells.clear()
	_restricted_edge_slots.clear()
	if not grid_manager:
		queue_redraw()
		return

	var allowed := {}
	for cell in cells:
		allowed[cell] = true

	for gp in _all_grid_slots():
		if not allowed.has(gp):
			_restricted_grid_cells.append(gp)

	# Regular tiles cannot be dropped on edge slots.
	_restricted_edge_slots = _all_edge_slots()

	queue_redraw()


func clear_grid_highlights() -> void:
	_restricted_grid_cells.clear()
	queue_redraw()


func _to_lookup(cells: Array[Vector2i]) -> Dictionary:
	var lookup := {}
	for cell in cells:
		lookup[cell] = true
	return lookup


func _all_grid_slots() -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if not grid_manager:
		return slots
	var s := grid_manager.grid_size
	for y in range(s):
		for x in range(s):
			slots.append(Vector2i(x, y))
	return slots


func _all_edge_slots() -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if not grid_manager:
		return slots
	var s := grid_manager.grid_size
	for y in range(s):
		slots.append(Vector2i(-1, y))
		slots.append(Vector2i(s, y))
	for x in range(s):
		slots.append(Vector2i(x, -1))
		slots.append(Vector2i(x, s))
	return slots
