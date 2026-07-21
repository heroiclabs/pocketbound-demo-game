extends CanvasLayer

signal menu_requested

@onready var _menu_btn: Button = %MenuBtn


func _ready() -> void:
	if _menu_btn:
		_menu_btn.pressed.connect(_on_menu_pressed)


func _on_menu_pressed() -> void:
	menu_requested.emit()
	queue_free()
