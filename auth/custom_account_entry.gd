extends CanvasLayer

signal login_requested
signal create_requested

const MENU_DESIGN_SIZE := Vector2(1280, 720)

@onready var _ui_root: Control = %UiRoot
@onready var _login_button: Button = %LoginBtn
@onready var _create_button: Button = %CreateBtn


func _ready() -> void:
	get_viewport().size_changed.connect(_layout_ui_scale)
	_layout_ui_scale()
	_login_button.pressed.connect(_on_login_pressed)
	_create_button.pressed.connect(_on_create_pressed)


func _layout_ui_scale() -> void:
	if not _ui_root:
		return

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var scale_factor := minf(vp_size.x / MENU_DESIGN_SIZE.x, vp_size.y / MENU_DESIGN_SIZE.y)
	_ui_root.scale = Vector2.ONE * scale_factor
	_ui_root.position = (vp_size - MENU_DESIGN_SIZE * scale_factor) * 0.5


func _on_login_pressed() -> void:
	login_requested.emit()


func _on_create_pressed() -> void:
	create_requested.emit()
