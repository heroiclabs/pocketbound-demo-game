class_name LevelTestingComplete
extends CanvasLayer

signal main_menu_requested
signal save_requested
signal edit_requested(level_key: String, owner_id: String)
signal publish_requested(level_key: String)

const FILTER_ALL_TIME := "all_time"
const FILTER_THIS_WEEK := "this_week"
const FILTER_FRIENDS := "friends"
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")

@onready var _time_label: Label = %TimeLabel
@onready var _slides_label: Label = %SlidesLabel
@onready var _rank_label: Label = %RankLabel
@onready var _level_name_label: Label = %LevelNameLabel
@onready var _leaderboard_list: VBoxContainer = %LeaderboardList
@onready var _filter_all_time: Button = %FilterAllTime
@onready var _filter_this_week: Button = %FilterThisWeek
@onready var _filter_friends: Button = %FilterFriends
@onready var _menu_btn: Button = %MenuBtn
@onready var _save_btn: Button = %SaveBtn
@onready var _edit_btn: Button = %EditBtn
@onready var _publish_btn: Button = %PublishBtn
@onready var _status_label: Label = %StatusLabel

var _filter_buttons: Dictionary = {}
var _action_buttons: Array[Button] = []
var _active_filter: String = FILTER_ALL_TIME
var _level_key: String = ""
var _level_owner_id: String = ""
var _leaderboard_seq: int = 0
var _publish_pulse_tween: Tween
var _publish_base_scale := Vector2.ONE


func _ready() -> void:
	_filter_buttons = {
		FILTER_ALL_TIME: _filter_all_time,
		FILTER_THIS_WEEK: _filter_this_week,
		FILTER_FRIENDS: _filter_friends,
	}

	_filter_all_time.pressed.connect(func(): _on_filter_pressed(FILTER_ALL_TIME))
	_filter_this_week.pressed.connect(func(): _on_filter_pressed(FILTER_THIS_WEEK))
	_filter_friends.pressed.connect(func(): _on_filter_pressed(FILTER_FRIENDS))
	_save_btn.pressed.connect(_on_save_pressed)
	_edit_btn.pressed.connect(_on_edit_pressed)
	_publish_btn.pressed.connect(_on_publish_pressed)
	_menu_btn.pressed.connect(func(): main_menu_requested.emit())
	_action_buttons = [_save_btn, _edit_btn, _publish_btn]

	var all_buttons: Array[Button] = [
		_filter_all_time,
		_filter_this_week,
		_filter_friends,
		_save_btn,
		_edit_btn,
		_publish_btn,
		_menu_btn,
	]
	for btn in all_buttons:
		btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
		btn.pressed.connect(func(): AudioManager.play("click"))

	_publish_base_scale = _publish_btn.scale
	_clear_status()
	set_filter(FILTER_ALL_TIME, false)
	_apply_scrollbar_theme_to_all(self)
	_update_publish_highlight()


func open_for_level(level_key: String, owner_id: String, level_name: String, time_ms: int, slides: int, rank: int) -> void:
	_level_key = level_key
	_level_owner_id = owner_id
	set_level_title(level_name, level_key)
	set_summary(time_ms, slides, rank)
	set_action_buttons_enabled(true)
	_edit_btn.disabled = _level_key.is_empty() or _level_owner_id.is_empty()
	_publish_btn.disabled = _level_key.is_empty()
	visible = true
	_clear_status()
	set_filter(FILTER_ALL_TIME, false)
	_update_publish_highlight()
	_load_leaderboard(FILTER_ALL_TIME)


func set_level_title(level_name: String, fallback_level_key: String = "") -> void:
	var text := level_name.strip_edges()
	if text.is_empty():
		text = fallback_level_key.strip_edges()
	if text.is_empty():
		text = "Untitled Level"
	_level_name_label.text = text


func set_summary(time_ms: int, slides: int, rank: int) -> void:
	_time_label.text = "Time: %.2fs" % (time_ms / 1000.0)
	_slides_label.text = "Tile Slides: %d" % slides
	_rank_label.visible = rank > 0
	if rank > 0:
		_rank_label.text = "Global Rank: #%d" % rank


func set_filter(filter_name: String, load_scores: bool = true) -> void:
	if not _filter_buttons.has(filter_name):
		filter_name = FILTER_ALL_TIME
	_active_filter = filter_name

	for key in _filter_buttons.keys():
		var btn := _filter_buttons[key] as Button
		if btn == null:
			continue
		btn.flat = false
		btn.modulate = Color(1, 1, 1, 1) if key == _active_filter else Color(1, 1, 1, 0.55)

	if load_scores:
		_load_leaderboard(_active_filter)


func set_action_buttons_enabled(enabled: bool) -> void:
	for button in _action_buttons:
		button.disabled = not enabled
	_update_publish_highlight()


func set_publish_enabled(enabled: bool) -> void:
	_publish_btn.disabled = not enabled
	_update_publish_highlight()


func set_save_enabled(enabled: bool) -> void:
	_save_btn.disabled = not enabled


func set_edit_enabled(enabled: bool) -> void:
	_edit_btn.disabled = not enabled


func show_action_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.visible = not text.strip_edges().is_empty()
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.85, 0.3, 0.3) if is_error else Color(0.3, 0.75, 0.4)
	)


func show_loading() -> void:
	_set_leaderboard_message("Loading...")


func show_empty(message: String = "No scores yet") -> void:
	_set_leaderboard_message(message)


func set_leaderboard_entries(entries: Array, player_rank: int) -> void:
	_clear_children(_leaderboard_list)
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if player_rank > 0 and int(entry.get("rank", 0)) == player_rank:
			row.modulate = Color(1.0, 1.0, 0.5)
		_leaderboard_list.add_child(row)

		var rank_lbl := Label.new()
		rank_lbl.text = "#%d" % int(entry.get("rank", 0))
		rank_lbl.custom_minimum_size = Vector2(40, 0)
		row.add_child(rank_lbl)

		var name_lbl := Label.new()
		name_lbl.text = str(entry.get("username", ""))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var time_lbl := Label.new()
		time_lbl.text = "%.2fs" % (int(entry.get("time_ms", 0)) / 1000.0)
		row.add_child(time_lbl)

		var slide_lbl := Label.new()
		slide_lbl.text = "%d sl" % int(entry.get("slide_count", 0))
		row.add_child(slide_lbl)

	if _leaderboard_list.get_child_count() == 0:
		show_empty()


func _on_filter_pressed(filter_name: String) -> void:
	set_filter(filter_name)


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_edit_pressed() -> void:
	if _level_key.is_empty() or _level_owner_id.is_empty():
		return
	edit_requested.emit(_level_key, _level_owner_id)


func _on_publish_pressed() -> void:
	if _level_key.is_empty():
		return
	publish_requested.emit(_level_key)


func _notification(what: int) -> void:
	if what == CanvasItem.NOTIFICATION_VISIBILITY_CHANGED:
		_update_publish_highlight()
	elif what == Node.NOTIFICATION_PREDELETE:
		_stop_publish_pulse()


func _load_leaderboard(filter_name: String) -> void:
	if _level_key.is_empty() or _level_owner_id.is_empty():
		show_empty()
		return

	_leaderboard_seq += 1
	var request_id := _leaderboard_seq
	show_loading()

	var payload := JSON.stringify({
		"level_owner_id": _level_owner_id,
		"level_key": _level_key,
		"filter": filter_name,
	})
	var result: Variant = await OnlineSession.call_rpc("get_leaderboard", payload)

	if not is_instance_valid(self) or not visible:
		return
	if request_id != _leaderboard_seq:
		return

	if not (result is Dictionary):
		show_empty("Could not load scores.")
		return

	var result_dict := result as Dictionary
	var entries_variant: Variant = result_dict.get("entries", [])
	if not (entries_variant is Array):
		show_empty()
		return

	var entries: Array = entries_variant as Array
	if entries.is_empty():
		show_empty()
		return

	var player_rank := int(result_dict.get("player_rank", 0))
	set_leaderboard_entries(entries, player_rank)


func _set_leaderboard_message(message: String) -> void:
	_clear_children(_leaderboard_list)
	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_list.add_child(lbl)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _clear_status() -> void:
	_status_label.text = ""
	_status_label.visible = false


func _update_publish_highlight() -> void:
	if _publish_btn == null:
		return
	if visible and not _publish_btn.disabled:
		_start_publish_pulse()
	else:
		_stop_publish_pulse()


func _start_publish_pulse() -> void:
	if _publish_btn == null:
		return
	if _publish_base_scale == Vector2.ZERO:
		_publish_base_scale = Vector2.ONE
	if _publish_pulse_tween != null:
		return

	_publish_btn.pivot_offset = _publish_btn.size * 0.5
	var target := _publish_base_scale * 1.08
	_publish_pulse_tween = create_tween()
	_publish_pulse_tween.set_loops()
	_publish_pulse_tween.tween_property(_publish_btn, "scale", target, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_publish_pulse_tween.tween_property(_publish_btn, "scale", _publish_base_scale, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_publish_pulse() -> void:
	if _publish_pulse_tween != null:
		_publish_pulse_tween.kill()
		_publish_pulse_tween = null
	if _publish_btn != null:
		_publish_btn.scale = _publish_base_scale


func _make_scroll_style(texture: Texture2D, margin: int = 2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.draw_center = true
	return style


func _apply_scrollbar_theme_to_all(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children("", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll == null:
			continue
		_apply_scrollbar_theme(scroll)


func _apply_scrollbar_theme(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v_scroll := scroll.get_v_scroll_bar()
	if v_scroll:
		var min_size_v := v_scroll.custom_minimum_size
		min_size_v.x = 12
		v_scroll.custom_minimum_size = min_size_v
		v_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))

	var h_scroll := scroll.get_h_scroll_bar()
	if h_scroll:
		var min_size_h := h_scroll.custom_minimum_size
		min_size_h.y = 12
		h_scroll.custom_minimum_size = min_size_h
		h_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
