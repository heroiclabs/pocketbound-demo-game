extends Node2D

var grid_manager: GridManager
@export var highlight_color: Color = Palette.LIGHT
@export var move_arrow_color: Color = Palette.DARKEST

var empty_cell_texture: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/background.tres")

var _highlighted_cells: Array[Vector2i] = []
var _arrow_active := false
var _arrow_start: Vector2i = Vector2i.ZERO
var _arrow_end: Vector2i = Vector2i.ZERO


func _draw() -> void:
	if not grid_manager:
		return

	var origin = grid_manager.grid_origin
	var size = grid_manager.grid_size
	var cs = grid_manager.cell_size

	# Draw empty in-grid cells using the room background texture.
	if empty_cell_texture:
		for y in range(size):
			for x in range(size):
				if not grid_manager.is_cell_empty(x, y):
					continue
				var empty_rect := Rect2(origin + Vector2(x * cs, y * cs), Vector2(cs, cs))
				draw_texture_rect(empty_cell_texture, empty_rect, false)

	# Draw highlighted cells
	for cell in _highlighted_cells:
		var rect_pos = Vector2(origin.x + cell.x * cs, origin.y + cell.y * cs)
		draw_rect(Rect2(rect_pos, Vector2(cs, cs)), highlight_color)

	_draw_move_arrow()

func set_highlights(cells: Array[Vector2i]) -> void:
	_highlighted_cells = cells
	queue_redraw()


func clear_highlights() -> void:
	_highlighted_cells.clear()
	queue_redraw()


func set_move_arrow(start_cell: Vector2i, end_cell: Vector2i) -> void:
	_arrow_start = start_cell
	_arrow_end = end_cell
	_arrow_active = true
	queue_redraw()


func clear_move_arrow() -> void:
	_arrow_active = false
	queue_redraw()


func _draw_move_arrow() -> void:
	if not _arrow_active or grid_manager == null:
		return
	if _arrow_start == _arrow_end:
		return

	var from := grid_manager.grid_to_world(_arrow_start)
	var to := grid_manager.grid_to_world(_arrow_end)
	var delta := to - from
	if delta.length_squared() < 0.01:
		return

	var dir := delta.normalized()
	var line_width := maxf(3.0, grid_manager.cell_size * 0.08)
	var head_length := minf(grid_manager.cell_size * 0.26, delta.length() * 0.45)
	var head_width := head_length * 0.65
	var line_end := to - dir * (head_length * 0.7)

	draw_line(from, line_end, move_arrow_color, line_width, true)

	var perp := Vector2(-dir.y, dir.x)
	var base := to - dir * head_length
	var left := base + perp * head_width * 0.5
	var right := base - perp * head_width * 0.5
	var points := PackedVector2Array([to, left, right])
	var colors := PackedColorArray([move_arrow_color, move_arrow_color, move_arrow_color])
	draw_polygon(points, colors)
