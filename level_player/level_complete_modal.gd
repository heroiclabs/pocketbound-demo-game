class_name LevelCompleteModal
extends CanvasLayer

signal next_level_requested
signal main_menu_requested

const FILTER_ALL_TIME := "all_time"
const FILTER_THIS_WEEK := "this_week"
const FILTER_FRIENDS := "friends"
const VOTE_LIKE := "like"
const VOTE_DISLIKE := "dislike"
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")
const LABEL_COLOR := Color(0.647059, 0.866667, 0.372549, 1)
const LABEL_FONT_SIZE := 20

@onready var _time_label: Label = %TimeLabel
@onready var _slides_label: Label = %SlidesLabel
@onready var _rank_label: Label = %RankLabel
@onready var _level_name_label: Label = %LevelNameLabel
@onready var _leaderboard_list: VBoxContainer = %LeaderboardList
@onready var _filter_all_time: Button = %FilterAllTime
@onready var _filter_this_week: Button = %FilterThisWeek
@onready var _filter_friends: Button = %FilterFriends
@onready var _next_btn: Button = %NextBtn
@onready var _menu_btn: Button = %MenuBtn
@onready var _like_btn: Button = %LikeBtn
@onready var _dislike_btn: Button = %DislikeBtn

var _filter_buttons: Dictionary = {}
var _vote_buttons: Array[Button] = []
var _active_filter: String = FILTER_ALL_TIME
var _level_key: String = ""
var _level_owner_id: String = ""
var _leaderboard_seq: int = 0
var _vote_locked := false


func _ready() -> void:
	_filter_buttons = {
		FILTER_ALL_TIME: _filter_all_time,
		FILTER_THIS_WEEK: _filter_this_week,
		FILTER_FRIENDS: _filter_friends,
	}

	_filter_all_time.pressed.connect(func(): _on_filter_pressed(FILTER_ALL_TIME))
	_filter_this_week.pressed.connect(func(): _on_filter_pressed(FILTER_THIS_WEEK))
	_filter_friends.pressed.connect(func(): _on_filter_pressed(FILTER_FRIENDS))
	_like_btn.pressed.connect(func(): _on_vote_pressed(VOTE_LIKE))
	_dislike_btn.pressed.connect(func(): _on_vote_pressed(VOTE_DISLIKE))
	_next_btn.pressed.connect(func(): next_level_requested.emit())
	_menu_btn.pressed.connect(func(): main_menu_requested.emit())
	_vote_buttons = [_like_btn, _dislike_btn]

	var all_buttons: Array[Button] = [
		_filter_all_time,
		_filter_this_week,
		_filter_friends,
		_like_btn,
		_dislike_btn,
		_next_btn,
		_menu_btn,
	]
	for btn in all_buttons:
		btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
		btn.pressed.connect(func(): AudioManager.play("click"))

	_apply_scrollbar_theme_to_all(self)
	set_filter(FILTER_ALL_TIME, false)
	_reset_vote_state()


func open_for_level(level_key: String, owner_id: String, level_name: String, time_ms: int, slides: int, rank: int) -> void:
	_level_key = level_key
	_level_owner_id = owner_id
	_reset_vote_state()
	set_level_title(level_name, level_key)
	set_summary(time_ms, slides, rank)
	visible = true
	set_filter(FILTER_ALL_TIME, false)
	_load_leaderboard(FILTER_ALL_TIME)


func set_next_level_available(available: bool) -> void:
	_next_btn.visible = available
	_next_btn.disabled = not available


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

		var rank_lbl := _make_label("#%d" % int(entry.get("rank", 0)))
		rank_lbl.custom_minimum_size = Vector2(40, 0)
		row.add_child(rank_lbl)

		var name_lbl := _make_label(str(entry.get("username", "")))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var time_lbl := _make_label("%.2fs" % (int(entry.get("time_ms", 0)) / 1000.0))
		row.add_child(time_lbl)

		var slide_lbl := _make_label("%d sl" % int(entry.get("slide_count", 0)))
		row.add_child(slide_lbl)

	if _leaderboard_list.get_child_count() == 0:
		show_empty()


func _on_filter_pressed(filter_name: String) -> void:
	set_filter(filter_name)


func _on_vote_pressed(vote: String) -> void:
	if _vote_locked:
		return
	if _level_key.is_empty() or _level_owner_id.is_empty():
		return

	_set_vote_buttons_enabled(false)

	var payload := JSON.stringify({
		"level_owner_id": _level_owner_id,
		"level_key": _level_key,
		"vote": vote,
	})
	var result: Variant = await OnlineSession.call_rpc("submit_level_vote", payload)

	if not is_instance_valid(self) or not visible:
		return

	if result is Dictionary:
		var result_dict := result as Dictionary
		var likes := int(result_dict.get("likes", 0))
		var dislikes := int(result_dict.get("dislikes", 0))
		var selected_vote := str(result_dict.get("vote", vote)).strip_edges().to_lower()
		_update_vote_button_labels(likes, dislikes)
		_set_vote_selection(selected_vote)
		_vote_locked = true
		_set_vote_buttons_enabled(false)
		return

	var rpc_error := str(OnlineSession.last_rpc_error).to_lower()
	if "already voted" in rpc_error:
		_vote_locked = true
		_set_vote_buttons_enabled(false)
		return

	_set_vote_buttons_enabled(true)


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
		show_empty()
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


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	return lbl


func _set_leaderboard_message(message: String) -> void:
	_clear_children(_leaderboard_list)
	var lbl := _make_label(message)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_list.add_child(lbl)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _reset_vote_state() -> void:
	_vote_locked = false
	_set_vote_buttons_enabled(true)
	_update_vote_button_labels()
	_set_vote_selection("")


func _set_vote_buttons_enabled(enabled: bool) -> void:
	for button in _vote_buttons:
		button.disabled = not enabled


func _set_vote_selection(vote: String) -> void:
	for button in _vote_buttons:
		button.modulate = Color(1, 1, 1, 1)
	if vote == VOTE_LIKE:
		_like_btn.modulate = Color(1, 1, 0.75, 1)
	elif vote == VOTE_DISLIKE:
		_dislike_btn.modulate = Color(1, 1, 0.75, 1)


func _update_vote_button_labels(likes: int = -1, dislikes: int = -1) -> void:
	_like_btn.text = "Like" if likes < 0 else "Like (%d)" % likes
	_dislike_btn.text = "Dislike" if dislikes < 0 else "Dislike (%d)" % dislikes


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
