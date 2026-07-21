class_name PlaceableObject
extends Node2D

enum Dir {
	NORTH = 1,
	EAST = 2,
	SOUTH = 4,
	WEST = 8,
}

var entity_id: int = -1
var grid_pos: Vector2i = Vector2i(-1, -1)
var sprite_path: String = ""


func _ready() -> void:
	var sprite := _main_sprite()
	if sprite:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_texture(texture: Texture2D) -> void:
	var sprite := _main_sprite()
	if sprite:
		sprite.texture = texture
	_set_overlay_texture(null)


func set_layered_textures(
	base_texture: Texture2D,
	overlay_texture: Texture2D,
	overlay_rotation_degrees: float = 0.0,
	overlay_scale_ratio: float = 0.0
) -> void:
	var sprite := _main_sprite()
	if sprite:
		sprite.texture = base_texture
	_set_overlay_texture(overlay_texture, overlay_rotation_degrees, overlay_scale_ratio)


static func vec_to_dir(v: Vector2i) -> int:
	if v == Vector2i(0, -1): return Dir.NORTH
	if v == Vector2i(1, 0): return Dir.EAST
	if v == Vector2i(0, 1): return Dir.SOUTH
	if v == Vector2i(-1, 0): return Dir.WEST
	return 0


static func opposite_dir(dir: int) -> int:
	match dir:
		Dir.NORTH: return Dir.SOUTH
		Dir.SOUTH: return Dir.NORTH
		Dir.EAST: return Dir.WEST
		Dir.WEST: return Dir.EAST
	return 0


func slide_to(target_world: Vector2, new_grid_pos: Vector2i) -> void:
	grid_pos = new_grid_pos
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_world, LevelConfig.SLIDE_DURATION) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


func _main_sprite() -> Sprite2D:
	return get_node_or_null("Sprite2D") as Sprite2D


func _overlay_sprite() -> Sprite2D:
	return get_node_or_null("OverlaySprite2D") as Sprite2D


func _set_overlay_texture(texture: Texture2D, overlay_rotation_degrees: float = 0.0, overlay_scale_ratio: float = 0.0) -> void:
	var overlay := _overlay_sprite()
	if texture == null:
		if overlay:
			overlay.queue_free()
		return

	if overlay == null:
		overlay = Sprite2D.new()
		overlay.name = "OverlaySprite2D"
		overlay.centered = true
		overlay.position = Vector2.ZERO
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.z_index = 1
		add_child(overlay)

	overlay.texture = texture
	overlay.rotation_degrees = overlay_rotation_degrees
	overlay.scale = _overlay_scale_for(texture, overlay_scale_ratio)


func _overlay_scale_for(overlay_texture: Texture2D, overlay_scale_ratio: float) -> Vector2:
	if overlay_scale_ratio <= 0.0:
		return Vector2.ONE

	var base_sprite := _main_sprite()
	if base_sprite == null or base_sprite.texture == null:
		return Vector2.ONE

	var base_size: Vector2 = base_sprite.texture.get_size()
	var overlay_size: Vector2 = overlay_texture.get_size()
	if base_size.x <= 0.0 or overlay_size.x <= 0.0:
		return Vector2.ONE

	var target_width: float = base_size.x * overlay_scale_ratio
	var scale_factor: float = target_width / overlay_size.x
	return Vector2.ONE * scale_factor
