extends Node2D

@onready var _background: Sprite2D = $Fullbackground
@onready var _stars: CPUParticles2D = $StarParticles


func _ready() -> void:
	get_viewport().size_changed.connect(_layout_to_viewport)
	_layout_to_viewport()


func _layout_to_viewport() -> void:
	var vp_size := get_viewport_rect().size
	_layout_background(vp_size)
	_layout_stars(vp_size)


func _layout_background(vp_size: Vector2) -> void:
	if _background == null or _background.texture == null:
		return
	var tex_size := _background.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	var scale_factor := maxf(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
	_background.scale = Vector2.ONE * scale_factor
	_background.position = vp_size * 0.5


func _layout_stars(vp_size: Vector2) -> void:
	if _stars == null:
		return
	_stars.position = Vector2(vp_size.x * 0.5, vp_size.y)
	_stars.emission_rect_extents = Vector2(vp_size.x * 0.5, 1.0)
