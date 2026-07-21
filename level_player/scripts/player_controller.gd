class_name PlayerController
extends Node

signal reached_end
signal moved(pos: Vector2i)
signal goal_move_started

var grid_manager: GridManager
var world: TileWorld
var player_node: Node2D
var start_pos: Vector2i
var end_pos: Vector2i
var current_pos: Vector2i

var _moving := false


func _unhandled_input(event: InputEvent) -> void:
	if _moving:
		return

	var direction := Vector2i.ZERO

	if event.is_action_pressed("ui_right"):
		direction = Vector2i(1, 0)
	elif event.is_action_pressed("ui_left"):
		direction = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_down"):
		direction = Vector2i(0, 1)
	elif event.is_action_pressed("ui_up"):
		direction = Vector2i(0, -1)

	if direction == Vector2i.ZERO:
		return

	var target := current_pos + direction
	if _can_move_to(target, direction):
		_move_to(target)
	else:
		AudioManager.play("player_move_fail")


func _can_move_to(pos: Vector2i, direction: Vector2i) -> bool:
	return world.can_move(current_pos, pos, direction, grid_manager.grid_size)


func _move_to(target: Vector2i) -> void:
	var from_pos := current_pos
	_moving = true
	current_pos = target
	AudioManager.play("player_move")
	moved.emit(target)
	var is_goal_move := current_pos == end_pos
	if current_pos == end_pos:
		goal_move_started.emit()

	var world_pos := grid_manager.grid_to_world(target)
	if is_goal_move:
		var from_world_pos := grid_manager.grid_to_world(from_pos)
		world_pos = (from_world_pos + world_pos) * 0.5
	var tween := create_tween()
	if is_goal_move and LevelConfig.GOAL_MOVE_TWEEN_DELAY > 0.0:
		tween.tween_interval(LevelConfig.GOAL_MOVE_TWEEN_DELAY)
	tween.tween_property(player_node, "global_position", world_pos, LevelConfig.SLIDE_DURATION) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.finished.connect(_on_move_finished)


func _on_move_finished() -> void:
	_moving = false
	if current_pos == end_pos:
		reached_end.emit()
